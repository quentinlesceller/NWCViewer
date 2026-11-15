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
    weak var webView: WKWebView?
    private var xml: String?
    private var previousMeasuresPerLine: Int?
    private var webReady = false
    private var rendererHasScore = false
    private var previousPartIDs: Set<String>?
    private var cachedPDF: PDFDocument?

    func chooseFile() {
        guard !busy, !exporting else { return }
        let panel = NSOpenPanel()
        panel.message = NSLocalizedString("Choose a NoteWorthy Composer (.nwc) score.", comment: "Open panel prompt")
        panel.allowedContentTypes = [UTType(filenameExtension: "nwc") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        guard !busy, !exporting else { return }
        error = nil
        parts = []; selectedPartIDs = []; previousPartIDs = nil
        previousMeasuresPerLine = nil; updatingLayout = false
        rendererHasScore = false; cachedPDF = nil
        busy = true; ready = false; hasScore = false; xml = nil; pageCount = 0
        title = url.deletingPathExtension().lastPathComponent
        let access = url.startAccessingSecurityScopedResource()
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/nwc2xml")
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
                title = "NWC Viewer"
            }
        }
    }

    func pageLoaded() { webReady = true; rendererHasScore = false; renderIfPossible() }
    func pageFailed(_ message: String) { busy = false; ready = false; hasScore = false; error = NSLocalizedString(message, comment: "Renderer error") }
    private func renderIfPossible() {
        guard webReady, let xml, let webView else { return }
        cachedPDF = nil
        var arguments: [String: Any] = ["measures": measuresPerLine,
            "ids": selectedPartIDs.isEmpty ? NSNull() : Array(selectedPartIDs) as Any]
        if !rendererHasScore { arguments["xml"] = xml }
        let script = rendererHasScore
            ? "return await window.viewer.configure(measures, ids);"
            : "return await window.viewer.load(xml, measures, ids);"
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
                    self.previousMeasuresPerLine = nil; self.previousPartIDs = nil
                    self.pageCount = pages
                    self.ready = true; self.hasScore = true; self.fitWidth()
                case .failure:
                    if let previous = self.previousPartIDs {
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
        guard ready, !busy, !exporting, !ids.isEmpty,
              ids.isSubset(of: Set(parts.map(\.id))), ids != selectedPartIDs else { return }
        previousPartIDs = selectedPartIDs
        selectedPartIDs = ids
        updatingLayout = true; busy = true; ready = false
        renderIfPossible()
    }

    func setMeasuresPerLine(_ value: Int) {
        guard ready, !busy, !exporting, [0, 2, 3, 4, 6, 8].contains(value), value != measuresPerLine else { return }
        previousMeasuresPerLine = measuresPerLine
        measuresPerLine = value
        UserDefaults.standard.set(value, forKey: "measuresPerLine")
        updatingLayout = true; busy = true; ready = false
        renderIfPossible()
    }
    func fitWidth() {
        guard let webView else { return }
        setZoom(Double(max(1, webView.bounds.width - 40)) / 794.0)
    }
    func changeZoom(_ amount: Double) { setZoom(zoom + amount) }
    func setZoom(_ value: Double) {
        zoom = min(2, max(0.5, value))
        webView?.callAsyncJavaScript("window.viewer.zoom(value);", arguments: ["value": zoom], in: nil, in: .page, completionHandler: nil)
    }
    func printScore(export: Bool) {
        guard ready, !exporting, let webView else { return }
        var destination: URL?
        if export {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = title + ".pdf"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            destination = url
        }
        exporting = true
        Task {
            defer { exporting = false }
            do {
                let document: PDFDocument
                if let cachedPDF { document = cachedPDF }
                else {
                    document = try await ScorePDF.make(from: webView)
                    cachedPDF = document
                }
                if let destination {
                    guard let data = document.dataRepresentation() else { throw ViewerError.message("Unable to create PDF.") }
                    try data.write(to: destination, options: .atomic)
                } else {
                    let info = NSPrintInfo.shared.copy() as! NSPrintInfo
                    info.paperSize = NSSize(width: 595.2756, height: 841.8898)
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
