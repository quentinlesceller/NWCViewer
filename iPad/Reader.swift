import SwiftUI
import PDFKit

enum ViewerError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let key): return NSLocalizedString(key, comment: "") }
    }
}

struct ExportPDF: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf]
    let data: Data
    init(_ data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = bytes
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct Place: Codable {
    var voice: String?
    var density: Int
    var x: CGFloat
    var y: CGFloat
    var zoom: CGFloat
}
import WebKit
import UniformTypeIdentifiers

@main
struct PadViewer: App {
    var body: some Scene { WindowGroup { Reader() } }
}

@MainActor
final class Book: NSObject, ObservableObject, WKNavigationDelegate {
    let web = WKWebView()
    @Published var title = "NWC Viewer"
    @Published var busy = false
    @Published var pages = 0
    @Published var error: String?
    @Published var parts = [[String:String]]()
    @Published var voice: String?
    @Published var density = 4
    @Published var thumbnails: PDFDocument?
    @Published var showingPages = false
    @Published var exporting = false
    var file: ExportPDF?
    func partName(_ id: String) -> String {
        let name = parts.first { $0["id"] == id }?["name"] ?? id
        let names = Set(parts.compactMap { $0["name"] })
        guard Set(["S", "A", "T", "B"]).isSubset(of: names) else { return name }
        switch name {
        case "S": return NSLocalizedString("Soprano", comment: "Choir voice")
        case "A": return NSLocalizedString("Alto", comment: "Choir voice")
        case "T": return NSLocalizedString("Tenor", comment: "Choir voice")
        case "B": return NSLocalizedString("Bass", comment: "Choir voice")
        default: return name
        }
    }
    var filename: String {
        let name = voice.map(partName)
        return ([title] + [name].compactMap { $0 }).joined(separator: " — ").replacingOccurrences(of: "/", with: "-")
    }
    private var current: URL?
    private var positions = (UserDefaults.standard.data(forKey: "pad.places").flatMap { try? JSONDecoder().decode([String:Place].self, from: $0) }) ?? [:]
    private var scrollObservation: NSKeyValueObservation?
    private var saveTask: Task<Void,Never>?
    private func positionKey(for url: URL) -> String {
        // The app container can move when an update is installed.
        let documents = URL.documentsDirectory.resolvingSymlinksInPath().path + "/"
        let path = url.resolvingSymlinksInPath().path
        if path.hasPrefix(documents) { return "Documents/" + String(path.dropFirst(documents.count)) }
        return url.path
    }
    func save() {
        guard !busy, let current, pages > 0 else { return }
        let scroll = web.scrollView
        let size = scroll.contentSize
        positions[positionKey(for: current)] = Place(voice: voice, density: density, x: scroll.contentOffset.x / max(1,size.width), y: scroll.contentOffset.y / max(1,size.height), zoom: scroll.zoomScale / max(0.01,scroll.minimumZoomScale))
        if let data = try? JSONEncoder().encode(positions) { UserDefaults.standard.set(data, forKey: "pad.places") }
    }
    enum PDFAction { case pages, export, printScore }
    func preparePDF(_ action: PDFAction) {
        guard !busy, pages > 0 else { return }
        busy = true
        Task {
            defer { finish() }
            do {
                if thumbnails == nil { thumbnails = try await ScorePDF.make(from: web) }
                switch action {
                case .pages: showingPages = true
                case .printScore, .export:
                    guard let data = thumbnails?.dataRepresentation() else { throw CocoaError(.fileWriteUnknown) }
                    if action == .printScore { presentPrint(data) }
                    else { file = ExportPDF(data); exporting = true }
                }
            } catch { self.error = error.localizedDescription }
        }
    }
    func jump(_ number: Int) {
        showingPages = false
        web.callAsyncJavaScript("viewer.goToPage(page)", arguments: ["page":number], in: nil, in: .page, completionHandler: nil)
    }
    private var loaded = false
    private var pending: URL?
    private static let conversion = DispatchQueue(label: "NWC.convert")
    override init() {
        super.init()
        web.navigationDelegate = self
        scrollObservation = web.scrollView.observe(\.contentOffset) { [weak self] _,_ in
            Task { @MainActor in
                self?.saveTask?.cancel()
                self?.saveTask = Task {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if !Task.isCancelled { self?.save() }
                }
            }
        }
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        if let url = pending { pending = nil; open(url) }
        else if let data = UserDefaults.standard.data(forKey: "pad.last") {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale) { open(url) }
        }
    }
    func open(_ url: URL) {
        guard loaded, !busy else { pending = url; return }
        save()
        busy = true
        let access = url.startAccessingSecurityScopedResource()
        Task {
            defer {
                if access { url.stopAccessingSecurityScopedResource() }
                finish()
            }
            do {
                let xml: String = try await withCheckedThrowingContinuation { reply in
                    Self.conversion.async {
                        do {
                            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                            defer { try? FileManager.default.removeItem(at: dir) }
                            guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16 << 20 else { throw CocoaError(.fileReadTooLarge) }
                            let input = dir.appendingPathComponent("score.nwc")
                            try FileManager.default.copyItem(at: url, to: input)
                            guard NWCPadConvert(input.path) == 0 else { throw CocoaError(.fileReadCorruptFile) }
                            reply.resume(returning: try String(contentsOf: dir.appendingPathComponent("score.xml"), encoding: .utf8))
                        } catch { reply.resume(throwing: error) }
                    }
                }
                let place = positions[positionKey(for: url)] ?? positions[url.path]
                let ids: Any = place?.voice.map { [$0] as Any } ?? NSNull()
                let result = try await web.callAsyncJavaScript("return await viewer.load(xml, count, ids)", arguments: ["xml":xml,"count":place?.density ?? 4,"ids":ids], in: nil, contentWorld: .page)
                try accept(result)
                title = url.deletingPathExtension().lastPathComponent
                current = url
                density = place?.density ?? 4
                voice = parts.contains { $0["id"] == place?.voice } ? place?.voice : nil
                thumbnails = nil
                let scroll = web.scrollView
                scroll.layoutIfNeeded()
                scroll.setZoomScale(scroll.minimumZoomScale * (place?.zoom ?? 1), animated: false)
                if let place {
                    // WebKit has finished rendering the SVGs before UIKit updates contentSize.
                    // Wait for layout before restoring the proportional viewport.
                    _ = try await web.callAsyncJavaScript("""
                        await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
                        window.scrollTo(x * document.documentElement.scrollWidth, y * document.documentElement.scrollHeight);
                        """, arguments: ["x": place.x, "y": place.y], in: nil, contentWorld: .page)
                } else {
                    scroll.setContentOffset(.zero, animated: false)
                }
                if let bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) { UserDefaults.standard.set(bookmark, forKey: "pad.last") }
            } catch { self.error = error.localizedDescription; pages = 0 }
        }
    }
    #if DEBUG
    func runSmoke() async throws {
        func waitForReader() async throws {
            for _ in 0..<600 {
                if !busy && pages > 0 { return }
                if error != nil { throw CocoaError(.fileReadCorruptFile) }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            throw CocoaError(.fileReadUnknown)
        }
        try await waitForReader()
        guard let alto = parts.first(where: { $0["name"] == "A" })?["id"] else { throw CocoaError(.fileReadCorruptFile) }
        configure(alto, 4)
        try await waitForReader()
        preparePDF(.pages)
        try await waitForReader()
        guard let doc = thumbnails, doc.pageCount == pages, pages > 3,
              let first = doc.page(at: 0), first.thumbnail(of: CGSize(width: 100,height: 150), for: .mediaBox).size.width > 0 else { throw CocoaError(.fileReadCorruptFile) }
        jump(3)
        try await Task.sleep(nanoseconds: 400_000_000)
        save()
        preparePDF(.export)
        try await waitForReader()
        try file?.data.write(to: URL.documentsDirectory.appendingPathComponent("smoke.pdf"))
    }
    #endif
    private func finish() {
        busy = false
        save()
        if let url = pending { pending = nil; open(url) }
    }
    private func accept(_ result: Any?) throws {
        guard let info = result as? [String:Any], let count = info["pages"] as? Int, count > 0 else { throw CocoaError(.fileReadCorruptFile) }
        pages = count
        parts = info["parts"] as? [[String:String]] ?? []
    }
    private func presentPrint(_ data: Data) {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = filename
        info.outputType = .general
        controller.printInfo = info
        controller.printingItem = data
        controller.present(from: CGRect(x: web.bounds.midX, y: 0, width: 1, height: 1), in: web, animated: true) { [weak self] _, _, error in
            if let error { self?.error = error.localizedDescription }
        }
    }
    func configure(_ selection: String?, _ count: Int) {
        guard !busy else { return }
        busy = true
        Task {
            defer { finish() }
            do {
                let ids: Any = selection.map { [$0] as Any } ?? NSNull()
                let result = try await web.callAsyncJavaScript("return await viewer.configure(count, ids)", arguments: ["count":count,"ids":ids], in: nil, contentWorld: .page)
                try accept(result)
                thumbnails = nil
                voice = selection
                density = count
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct CanvasView: UIViewRepresentable {
    let web: WKWebView
    func makeUIView(context: Context) -> WKWebView { web }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

struct Reader: View {
    @StateObject private var book = Book()
    @Environment(\.scenePhase) var phase
    @State private var choosing = false
    var body: some View {
        NavigationStack {
            ZStack {
                CanvasView(web: book.web).opacity(book.pages > 0 ? 1 : 0)
                if book.busy { ProgressView().padding().background(.regularMaterial).cornerRadius(12) }
                else if book.pages == 0 {
                    VStack(spacing: 16) {
                        Text("Open a NoteWorthy Composer score to read, print, or save as PDF.").multilineTextAlignment(.center)
                        Button("Open NWC File…") { choosing = true }.buttonStyle(.borderedProminent)
                    }.padding()
                }
            }
            .navigationTitle(book.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button { choosing = true } label: { Label("Open…", systemImage: "folder") } }
                if book.pages > 0 {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Picker("Voices", selection: Binding(get: { book.voice }, set: { book.configure($0, book.density) })) {
                                Text("All voices").tag(nil as String?)
                                ForEach(book.parts.compactMap { $0["id"] }, id: \.self) { id in
                                    Text(verbatim: book.partName(id)).tag(Optional(id))
                                }
                            }.pickerStyle(.menu)
                            Picker("Measures per line", selection: Binding(get: { book.density }, set: { book.configure(book.voice, $0) })) {
                                Text("Automatic").tag(0)
                                ForEach([2,3,4,6,8], id: \.self) { count in Text(verbatim: String(count)).tag(count) }
                            }.pickerStyle(.menu)
                            Button { book.preparePDF(.pages) } label: { Label("Show Thumbnails", systemImage: "square.grid.2x2") }
                            Divider()
                            Button { book.preparePDF(.export) } label: { Label("Save PDF…", systemImage: "square.and.arrow.down") }
                            Button { book.preparePDF(.printScore) } label: { Label("Print…", systemImage: "printer") }
                        } label: { Text("Score options") }.disabled(book.busy)
                    }
                }
            }
        }
        .onChange(of: phase) { value in if value != .active { book.save() } }
        .sheet(isPresented: $book.showingPages) {
            NavigationStack {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))]) {
                        if let document = book.thumbnails {
                            ForEach(0..<document.pageCount, id: \.self) { index in
                                if let page = document.page(at: index) {
                                    Button { book.jump(index + 1) } label: {
                                        VStack {
                                            Image(uiImage: page.thumbnail(of: CGSize(width: 220,height: 310), for: .mediaBox)).resizable().scaledToFit()
                                            Text(verbatim: String(index + 1))
                                        }
                                    }
                                }
                            }
                        }
                    }.padding()
                }.navigationTitle("Pages").toolbar { Button("Cancel") { book.showingPages = false } }
            }
        }
        .fileExporter(isPresented: $book.exporting, document: book.file, contentType: .pdf, defaultFilename: book.filename) { result in
            if case .failure(let error) = result { book.error = error.localizedDescription }
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [UTType(filenameExtension: "nwc") ?? .data]) { result in
            do { book.open(try result.get()) } catch { book.error = error.localizedDescription }
        }
        #if DEBUG
        .task {
            if let name = UserDefaults.standard.string(forKey: "FixtureName"), name == URL(fileURLWithPath: name).lastPathComponent {
                book.open(URL.documentsDirectory.appendingPathComponent(name))
                if UserDefaults.standard.bool(forKey: "RunSmoke") {
                    do { try await book.runSmoke() } catch { book.error = error.localizedDescription }
                }
            }
        }
        #endif
        .onOpenURL { book.open($0) }
        .alert("Unable to open or export score", isPresented: Binding(get: { book.error != nil }, set: { if !$0 { book.error = nil } })) { Button("OK") {} } message: { Text(book.error ?? "") }
    }
}
