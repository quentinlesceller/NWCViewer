import AppKit
import PDFKit
import SwiftUI
import WebKit
import UniformTypeIdentifiers

@MainActor
final class ViewerModel: ObservableObject {
    @Published var title = "NWC Viewer"
    @Published var busy = false
    @Published var ready = false
    @Published var hasScore = false
    @Published var zoom = 1.0
    @Published var pageCount = 0
    @Published var exporting = false
    @Published var error: String?
    weak var webView: WKWebView?
    private var xml: String?
    private var webReady = false

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

    func pageLoaded() { webReady = true; renderIfPossible() }
    func pageFailed(_ message: String) { busy = false; ready = false; hasScore = false; error = NSLocalizedString(message, comment: "Renderer error") }
    private func renderIfPossible() {
        guard webReady, let xml, let webView else { return }
        // Arguments are serialized by WebKit, never interpolated into JavaScript/HTML.
        webView.callAsyncJavaScript("await window.viewer.load(xml); return document.querySelectorAll('.music-page svg').length;", arguments: ["xml": xml], in: nil, in: .page) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.busy = false
                switch result {
                case .success(let count):
                    self.pageCount = count as? Int ?? 0
                    self.ready = true; self.hasScore = true; self.fitWidth()
                case .failure:
                    self.pageFailed("The sheet music could not be displayed. Try another NWC file.")
                }
            }
        }
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
                let document = try await ScorePDF.make(from: webView)
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
