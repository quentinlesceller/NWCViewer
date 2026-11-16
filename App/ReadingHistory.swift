import Foundation

struct PageLayout: Codable, Equatable {
    var landscape = false
    var marginMM = 15
    var noteSize = 100
}

struct ReadingState: Codable, Equatable {
    var voices: [String] = []
    var zoom = 1.0
    var fitWidth = true
    var page = 1
    var pageOffset = 0.0
    var measures = 4
    var layout = PageLayout()
}

struct RecentScore: Codable, Identifiable {
    var id: String
    var bookmark: Data?
    var name: String
    var state: ReadingState
    func resolvedURL() -> URL {
        var stale = false
        if let bookmark, let url = try? URL(resolvingBookmarkData: bookmark, options: .withoutUI, bookmarkDataIsStale: &stale) { return url }
        return URL(fileURLWithPath: id)
    }
}

/// Local bookmarks and reading preferences only; no score contents are stored.
final class ReadingHistory {
    private let defaults: UserDefaults
    private let key = "readingHistory.v1"
    private(set) var entries: [RecentScore]
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([RecentScore].self, from: $0) } ?? []
    }
    func state(for url: URL) -> ReadingState? {
        entries.first { $0.id == url.path || $0.resolvedURL().resolvingSymlinksInPath() == url.resolvingSymlinksInPath() }?.state
    }
    func save(url: URL, state: ReadingState) {
        // The common scroll-update path does not resolve every recent bookmark.
        let index = entries.firstIndex { $0.id == url.path } ?? entries.firstIndex { $0.resolvedURL().resolvingSymlinksInPath() == url.resolvingSymlinksInPath() }
        let existing = index.map { entries.remove(at: $0) }
        entries.insert(RecentScore(id: url.path, bookmark: existing?.bookmark ?? (try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)), name: url.deletingPathExtension().lastPathComponent, state: state), at: 0)
        entries = Array(entries.prefix(20))
        persist()
    }
    func clear() { entries = []; persist() }
    private func persist() { if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key) } }
}
