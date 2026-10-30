import AppKit
import Observation
import WebKit

@MainActor @Observable
final class BrowserTab: NSObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    let id = UUID()
    let webView: WKWebView
    var title = "ChatGPT"
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var address = "https://chatgpt.com/"
    var errorMessage: String?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored var openPopup: ((WKWebViewConfiguration) -> WKWebView)?
    @ObservationIgnored var closePopup: (() -> Void)?

    init(configuration: WKWebViewConfiguration? = nil, loadHome: Bool = true) {
        let configuration = configuration ?? WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [
            webView.observe(\.title, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.title = self?.webView.title ?? "ChatGPT" }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateState() }
            },
            webView.observe(\.url, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateState() }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateState() }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateState() }
            }
        ]
        if loadHome { goHome() }
    }

    func goHome() { webView.load(URLRequest(url: URL(string: "https://chatgpt.com/")!)) }

    private func updateState() {
        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        address = webView.url?.absoluteString ?? "https://chatgpt.com/"
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        errorMessage = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        show(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        show(error)
    }

    private func show(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        errorMessage = error.localizedDescription
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        errorMessage = "ページの処理が終了しました。再読み込みしてください。"
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        openPopup?(configuration)
    }

    func webViewDidClose(_ webView: WKWebView) { closePopup?() }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?
            .split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        decisionHandler(disposition == "attachment" || !navigationResponse.canShowMIMEType ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        BrowserDownloads.shared.receive(download, window: webView.window)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        BrowserDownloads.shared.receive(download, window: webView.window)
    }


    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.cancel)
            return
        }
        if ["https", "http", "about", "blob", "data"].contains(scheme) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated { NSWorkspace.shared.open(url) }
        }
    }
}

@MainActor @Observable
final class BrowserModel {
    var tabs: [BrowserTab] = []
    @ObservationIgnored private var shortcutMonitor: Any?
    var selectedID: UUID?
    var selectedTab: BrowserTab? { tabs.first { $0.id == selectedID } }

    init() { addTab() }

    func installShortcuts(_ settings: ShortcutSettings) {
        guard shortcutMonitor == nil else { return }
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.selectedTab?.webView.window,
                  event.window === window, NSApp.keyWindow === window else { return event }
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            for action in BrowserAction.allCases {
                let shortcut = settings.shortcut(for: action)
                var expected: NSEvent.ModifierFlags = []
                if shortcut.command { expected.insert(.command) }
                if shortcut.shift { expected.insert(.shift) }
                if shortcut.option { expected.insert(.option) }
                if shortcut.control { expected.insert(.control) }
                guard flags == expected, event.charactersIgnoringModifiers?.lowercased() == shortcut.key else { continue }
                switch action {
                case .newTab: self.addTab()
                case .closeTab: if let id = self.selectedID { self.closeTab(id) }
                case .nextTab: self.selectRelative(1)
                case .previousTab: self.selectRelative(-1)
                }
                return nil
            }
            return event
        }
    }

    @discardableResult
    func addTab(configuration: WKWebViewConfiguration? = nil, loadHome: Bool = true) -> BrowserTab {
        let tab = BrowserTab(configuration: configuration, loadHome: loadHome)
        tab.openPopup = { [weak self] configuration in
            self?.addTab(configuration: configuration, loadHome: false).webView ?? WKWebView(frame: .zero, configuration: configuration)
        }
        tab.closePopup = { [weak self, weak tab] in
            guard let tab else { return }
            self?.closeTab(tab.id)
        }
        tabs.append(tab)
        selectedID = tab.id
        return tab
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].webView.stopLoading()
        tabs.remove(at: index)
        if tabs.isEmpty { addTab() }
        else if selectedID == id { selectedID = tabs[min(index, tabs.count - 1)].id }
    }

    func selectRelative(_ offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == selectedID }), !tabs.isEmpty else { return }
        selectedID = tabs[(index + offset + tabs.count) % tabs.count].id
    }
}
