import SwiftUI
import WebKit

@MainActor
struct ScoreWebView: NSViewRepresentable {
    let model: ViewerModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "readingPosition")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.allowsMagnification = false
        model.webView = view
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web") {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else { model.pageFailed("The music renderer is missing. Reinstall NWC Viewer.") }
        return view
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let model: ViewerModel
        init(model: ViewerModel) { self.model = model }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let position = message.body as? [String: Any] { model.receivePosition(position) }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.callAsyncJavaScript("document.title = title; document.getElementById('score').setAttribute('aria-label', title); document.documentElement.lang = language;",
                arguments: ["title": NSLocalizedString("Sheet music", comment: "Accessible score label"),
                            "language": Bundle.main.preferredLocalizations.first ?? "en"],
                in: nil, in: .page, completionHandler: nil)
            model.pageLoaded()
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { model.pageFailed("The music renderer could not load.") }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { model.pageFailed("The music renderer could not load.") }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { model.pageFailed("The music renderer stopped. Close and reopen NWC Viewer.") }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(action.request.url?.isFileURL == true && action.navigationType == .other ? .allow : .cancel)
        }
    }
}
