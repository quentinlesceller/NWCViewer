import AppKit
import WebKit
import PDFKit

@MainActor
enum ScorePDF {
    /// Capture each rendered SVG separately: WKWebView's printOperation can
    /// produce blank/doubled pages on macOS. This also decouples PDF from zoom.
    static func make(from webView: WKWebView) async throws -> PDFDocument {
        let previous = try await webView.evaluateJavaScript("document.getElementById('score').style.zoom") as? String ?? "1"
        defer {
            webView.callAsyncJavaScript("document.getElementById('score').style.zoom = value;", arguments: ["value": previous], in: nil, in: .page, completionHandler: nil)
        }
        let rawRectangles = try await webView.callAsyncJavaScript("""
            document.getElementById('score').style.zoom = '1';
            return Array.from(document.querySelectorAll('.music-page svg')).map(svg => {
                const r = svg.getBoundingClientRect();
                return { x: r.left + scrollX, y: r.top + scrollY, width: r.width, height: r.height };
            });
            """, arguments: [:], in: nil, contentWorld: .page)
        let rectangles = (rawRectangles as? [[String: Any]])?.map { $0.compactMapValues { ($0 as? NSNumber)?.doubleValue } }
        guard let rectangles, !rectangles.isEmpty else { throw ViewerError.message("There are no score pages to export.") }
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { throw ViewerError.message("Unable to create PDF.") }
        var a4 = CGRect(x: 0, y: 0, width: 595.2756, height: 841.8898)
        guard let context = CGContext(consumer: consumer, mediaBox: &a4, nil) else { throw ViewerError.message("Unable to create PDF.") }
        for r in rectangles {
            let configuration = WKPDFConfiguration()
            configuration.rect = CGRect(x: r["x"] ?? 0, y: r["y"] ?? 0, width: r["width"] ?? 794, height: r["height"] ?? 1123)
            let capture: Data = try await withCheckedThrowingContinuation { continuation in
                webView.createPDF(configuration: configuration) { continuation.resume(with: $0) }
            }
            guard let page = PDFDocument(data: capture)?.page(at: 0) else { throw ViewerError.message("Unable to render a PDF page.") }
            context.beginPDFPage(nil)
            context.saveGState()
            let bounds = page.bounds(for: .mediaBox)
            context.scaleBy(x: a4.width / bounds.width, y: a4.height / bounds.height)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        guard let document = PDFDocument(data: data as Data) else { throw ViewerError.message("Unable to finish the PDF.") }
        return document
    }
}
