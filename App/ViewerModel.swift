import AppKit
import PDFKit
import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct ScorePart: Identifiable {
    let id: String
    let name: String
}

@MainActor
final class ViewerModel: ObservableObject {
    @Published var title = "NWC Viewer"
    @Published private(set) var parts: [ScorePart] = []
    @Published private(set) var selectedPartIDs: Set<String> = []
    @Published var busy = false
    @Published var ready = false
    @Published var hasScore = false
    @Published var zoom = 1.0
    @Published private(set) var measuresPerLine: Int = {
        let saved = UserDefaults.standard.object(forKey: "measuresPerLine") as? Int ?? 4
        return [0, 2, 3, 4, 6, 8].contains(saved) ? saved : 4
    }()
    @Published var updatingLayout = false
    @Published var pageCount = 0
    @Published var exporting = false
    @Published var error: String?
    @Published var recentScores: [RecentScore] = []
    @Published var currentPage = 1
    @Published var measureNumbers: [Int] = []
    @Published var pageLayout = PageLayout()
    @Published var showingLocation = false
    @Published var showingLayout = false
    @Published var showingSidebar = false
    @Published var thumbnailDocument: PDFDocument?
    @Published var preparingThumbnails = false
    private let history: ReadingHistory
    private var currentURL: URL?
    private var reading = ReadingState()
    private var pendingOpen: URL?
    private var restoreAttempted = false
    private var recordHistory = true
    private var fitToWidth = true
    private var previousLayout: PageLayout?
    private var layoutRevision = 0
    private var pdfTask: Task<PDFDocument, Error>?

    init(history: ReadingHistory = ReadingHistory()) {
        self.history = history
        self.recentScores = history.entries
    }
    func clearRecentFiles() { history.clear(); recentScores = []; recordHistory = false }
    func saveReading() {
        guard let currentURL, hasScore, ready else { return }
        reading.voices = parts.count == selectedPartIDs.count ? [] : Array(selectedPartIDs)
        reading.zoom = zoom; reading.fitWidth = fitToWidth
        reading.page = currentPage; reading.measures = measuresPerLine; reading.layout = pageLayout
        if recordHistory { history.save(url: currentURL, state: reading); recentScores = history.entries }
    }
    func receivePosition(_ value: [String: Any]) {
        guard ready, !busy, !exporting, !preparingThumbnails else { return }
        currentPage = min(pageCount, max(1, value["page"] as? Int ?? 1))
        reading.pageOffset = value["offset"] as? Double ?? 0
        saveReading()
    }
    func goToPage(_ page: Int) {
        guard ready, !exporting, !preparingThumbnails else { return }
        webView?.callAsyncJavaScript("return viewer.goToPage(page)", arguments: ["page": min(pageCount, max(1, page))], in: nil, in: .page, completionHandler: nil)
    }
    func goToMeasure(_ number: Int) {
        guard ready, !exporting, !preparingThumbnails, measureNumbers.contains(number) else { return }
        webView?.callAsyncJavaScript("return viewer.goToMeasure(number)", arguments: ["number": number], in: nil, in: .page, completionHandler: nil)
    }
    func resizeToFit() { if fitToWidth && ready && !exporting && !preparingThumbnails { fitWidth() } }
    func setPageLayout(_ layout: PageLayout) {
        guard ready, !busy, !exporting, !preparingThumbnails, layout != pageLayout else { return }
        saveReading()
        previousLayout = pageLayout
        if layout.noteSize != pageLayout.noteSize { previousMeasuresPerLine = measuresPerLine; measuresPerLine = 0 }
        pageLayout = layout
        updatingLayout = true; busy = true; ready = false
        renderIfPossible()
    }
    func prepareThumbnails() {
        guard showingSidebar, ready, !exporting, !preparingThumbnails, thumbnailDocument == nil else { return }
        preparingThumbnails = true
        let revision = layoutRevision
        Task {
            defer { preparingThumbnails = false; resizeToFit() }
            do {
                let document = try await makePDF()
                if revision == layoutRevision { thumbnailDocument = document }
            } catch { self.error = error.localizedDescription }
        }
    }
    private func makePDF() async throws -> PDFDocument {
        if let cachedPDF { return cachedPDF }
        if let pdfTask { return try await pdfTask.value }
        guard let webView else { throw ViewerError.message("Unable to create PDF.") }
        let revision = layoutRevision
        let task = Task { try await ScorePDF.make(from: webView, landscape: pageLayout.landscape) }
        pdfTask = task
        defer { pdfTask = nil }
        let document = try await task.value
        if revision == layoutRevision { cachedPDF = document }
        return document
    }
    var suggestedPDFName: String {
        let names = parts.filter { selectedPartIDs.contains($0.id) }.map(\.name)
        let suffix = selectedPartIDs.count < parts.count ? " — " + names.joined(separator: ", ") : ""
        return (title + suffix).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".pdf"
    }
    weak var webView: WKWebView?
    private var xml: String?
    private var previousMeasuresPerLine: Int?
    private var webReady = false
    private var rendererHasScore = false
    private var previousPartIDs: Set<String>?
    private var cachedPDF: PDFDocument?

    func chooseFile() {
        guard !busy, !exporting, !preparingThumbnails else { return }
        let panel = NSOpenPanel()
        panel.message = NSLocalizedString("Choose a NoteWorthy Composer (.nwc) score.", comment: "Open panel prompt")
        panel.allowedContentTypes = [UTType(filenameExtension: "nwc") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        if busy { pendingOpen = url; return }
        guard !exporting, !preparingThumbnails else { return }
        saveReading()
        restoreAttempted = true; recordHistory = true
        currentURL = url
        reading = history.state(for: url) ?? ReadingState(measures: measuresPerLine)
        pageLayout = reading.layout
        measuresPerLine = reading.measures
        fitToWidth = reading.fitWidth
        currentPage = reading.page
        error = nil
        parts = []; selectedPartIDs = Set(reading.voices); previousPartIDs = nil
        previousMeasuresPerLine = nil; updatingLayout = false
        rendererHasScore = false; cachedPDF = nil; thumbnailDocument = nil; layoutRevision += 1
        busy = true; ready = false; hasScore = false; xml = nil; pageCount = 0
        title = url.deletingPathExtension().lastPathComponent
        let access = url.startAccessingSecurityScopedResource()
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/score-reader")
        Task {
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let converted = try await Task.detached(priority: .userInitiated) {
                    try Converter(executable: helper).convert(url)
                }.value
                xml = converted
                renderIfPossible()
            } catch {
                self.error = error.localizedDescription
                busy = false
                title = "NWC Viewer"; currentURL = nil
                if let pending = pendingOpen { pendingOpen = nil; open(pending) }
            }
        }
    }

    func pageLoaded() {
        webReady = true; rendererHasScore = false
        if !restoreAttempted, !busy, let recent = recentScores.first {
            restoreAttempted = true
            let url = recent.resolvedURL()
            if FileManager.default.fileExists(atPath: url.path) { open(url); return }
        }
        renderIfPossible()
    }
    func pageFailed(_ message: String) { busy = false; ready = false; hasScore = false; error = NSLocalizedString(message, comment: "Renderer error") }
    private func renderIfPossible() {
        guard webReady, let xml, let webView else { return }
        cachedPDF = nil; thumbnailDocument = nil; layoutRevision += 1
        var arguments: [String: Any] = ["measures": measuresPerLine, "layout": ["landscape": pageLayout.landscape, "marginMM": pageLayout.marginMM, "noteSize": pageLayout.noteSize],
            "ids": selectedPartIDs.isEmpty ? NSNull() : Array(selectedPartIDs) as Any]
        if !rendererHasScore { arguments["xml"] = xml }
        let script = rendererHasScore
            ? "return await window.viewer.configure(measures, ids, layout);"
            : "return await window.viewer.load(xml, measures, ids, layout);"
        webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.busy = false; self.updatingLayout = false
                switch result {
                case .success(let value):
                    guard let info = value as? [String: Any], let pages = info["pages"] as? Int else {
                        self.pageFailed("The sheet music could not be displayed. Try another NWC file.")
                        return
                    }
                    self.parts = (info["parts"] as? [[String: String]] ?? []).compactMap { part in
                        guard let id = part["id"], let name = part["name"] else { return nil }
                        return ScorePart(id: id, name: name)
                    }
                    self.selectedPartIDs = Set(info["selectedPartIDs"] as? [String] ?? [])
                    self.rendererHasScore = true
                    self.previousMeasuresPerLine = nil; self.previousPartIDs = nil; self.previousLayout = nil
                    self.pageCount = pages
                    self.measureNumbers = info["measureNumbers"] as? [Int] ?? []
                    self.ready = true; self.hasScore = true
                    if let pending = self.pendingOpen { self.pendingOpen = nil; self.open(pending); return }
                    if self.fitToWidth { self.fitWidth() } else { self.setZoom(self.reading.zoom, manual: false) }
                    let page = min(pages, max(1, self.reading.page))
                    self.currentPage = page
                    self.webView?.callAsyncJavaScript("viewer.goToPage(page, offset)", arguments: ["page": page, "offset": self.reading.pageOffset], in: nil, in: .page) { [weak self] _ in
                        Task { @MainActor in self?.prepareThumbnails() }
                    }
                    self.saveReading()
                case .failure:
                    if let previous = self.previousLayout {
                        self.pageLayout = previous; self.previousLayout = nil
                        if let count = self.previousMeasuresPerLine { self.measuresPerLine = count; self.previousMeasuresPerLine = nil }
                        self.error = NSLocalizedString("Unable to apply this layout. Try fewer measures per line.", comment: "Layout error")
                        self.busy = true; self.updatingLayout = true; self.renderIfPossible()
                    } else if let previous = self.previousPartIDs {
                        self.selectedPartIDs = previous; self.previousPartIDs = nil
                        self.error = NSLocalizedString("Unable to show these voices. The previous selection will be restored.", comment: "Voice error")
                        self.busy = true; self.updatingLayout = true
                        self.renderIfPossible()
                    } else if self.measuresPerLine != 0 || self.previousMeasuresPerLine != nil {
                        self.measuresPerLine = self.previousMeasuresPerLine ?? 0
                        self.previousMeasuresPerLine = nil
                        UserDefaults.standard.set(self.measuresPerLine, forKey: "measuresPerLine")
                        self.error = NSLocalizedString("Unable to apply this layout. Try fewer measures per line.", comment: "Layout error")
                        self.busy = true; self.updatingLayout = true
                        self.renderIfPossible()
                    } else {
                        self.pageFailed("The sheet music could not be displayed. Try another NWC file.")
                    }
                }
            }
        }
    }
    func setVisibleParts(_ ids: Set<String>) {
        guard ready, !busy, !exporting, !preparingThumbnails, !ids.isEmpty,
              ids.isSubset(of: Set(parts.map(\.id))), ids != selectedPartIDs else { return }
        saveReading()
        previousPartIDs = selectedPartIDs
        selectedPartIDs = ids
        updatingLayout = true; busy = true; ready = false
        renderIfPossible()
    }

    func setMeasuresPerLine(_ value: Int) {
        guard ready, !busy, !exporting, !preparingThumbnails, [0, 2, 3, 4, 6, 8].contains(value), value != measuresPerLine else { return }
        saveReading()
        previousMeasuresPerLine = measuresPerLine
        measuresPerLine = value
        UserDefaults.standard.set(value, forKey: "measuresPerLine")
        updatingLayout = true; busy = true; ready = false
        renderIfPossible()
    }
    func fitWidth() {
        guard let webView else { return }
        fitToWidth = true
        setZoom(Double(max(1, webView.bounds.width - 40)) / (pageLayout.landscape ? 1123.0 : 794.0), manual: false)
    }
    func changeZoom(_ amount: Double) { setZoom(zoom + amount) }
    func setZoom(_ value: Double, manual: Bool = true) {
        if manual { fitToWidth = false }
        zoom = min(2, max(0.25, value))
        saveReading()
        webView?.callAsyncJavaScript("window.viewer.zoom(value);", arguments: ["value": zoom], in: nil, in: .page, completionHandler: nil)
    }
    func printScore(export: Bool) {
        guard ready, !exporting, !preparingThumbnails else { return }
        var destination: URL?
        if export {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = suggestedPDFName
            guard panel.runModal() == .OK, let url = panel.url else { return }
            destination = url
        }
        exporting = true
        Task {
            defer { exporting = false }
            do {
                let document = try await makePDF()
                if let destination {
                    guard let data = document.dataRepresentation() else { throw ViewerError.message("Unable to create PDF.") }
                    try data.write(to: destination, options: .atomic)
                } else {
                    let info = NSPrintInfo.shared.copy() as! NSPrintInfo
                    info.paperSize = pageLayout.landscape ? NSSize(width: 841.8898, height: 595.2756) : NSSize(width: 595.2756, height: 841.8898)
                    info.orientation = pageLayout.landscape ? .landscape : .portrait
                    info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
                    guard let operation = document.printOperation(for: info, scalingMode: .pageScaleDownToFit, autoRotate: false) else {
                        throw ViewerError.message("Unable to start printing.")
                    }
                    operation.showsPrintPanel = true
                    operation.showsProgressPanel = true
                    operation.run()
                }
            } catch { self.error = String(format: NSLocalizedString("Printing or saving the PDF failed. %@", comment: "Export error with details"), error.localizedDescription) }
        }
    }
}
