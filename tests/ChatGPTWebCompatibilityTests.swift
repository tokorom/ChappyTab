// Run from the repository root:
// swiftc -parse-as-library ChappyTab/ChatGPTWebCompatibility.swift \
//   tests/ChatGPTWebCompatibilityTests.swift -o /tmp/chappytab-web-tests
// /tmp/chappytab-web-tests
import AppKit
import WebKit

@main
@MainActor
struct ChatGPTWebCompatibilityTests {
    static func main() async throws {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let existingScript = WKUserScript(source: "window.existingScript = true;",
                                          injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(existingScript)
        ChatGPTWebCompatibility.install(in: configuration.userContentController)
        ChatGPTWebCompatibility.install(in: configuration.userContentController)
        try require(configuration.userContentController.userScripts.count == 2,
                    "Installation must preserve existing scripts and avoid popup duplicates")

        let page = TestPage(configuration: configuration)
        for host in ["chatgpt.com", "chat.openai.com"] {
            try await page.load(host: host)
            try await page.check("window.existingScript === true", "Existing user scripts still run")
            try await page.check("getComputedStyle(document.querySelector('pre')).contentVisibility === 'visible'",
                                 "Existing code blocks render without content skipping")
            try await page.check("getComputedStyle(document.querySelector('code')).contentVisibility === 'visible'",
                                 "Nested code content renders without content skipping")
            try await page.check("getComputedStyle(document.querySelector('#unrelated')).contentVisibility === 'auto'",
                                 "Other content keeps its rendering optimization")
            try await page.check("getComputedStyle(document.querySelector('code span')).color === 'rgb(120, 40, 160)'",
                                 "Syntax highlighting is preserved")
            try await page.check("document.querySelector('code').textContent === 'let value = 42'",
                                 "Code text is preserved")
            try await page.check("""
                (() => {
                    const block = document.createElement('div');
                    block.setAttribute('data-markdown-copy', 'code-block');
                    block.style.contentVisibility = 'auto';
                    block.innerHTML = '<button>Copy</button><pre><code>new code</code></pre>';
                    block.querySelector('button').addEventListener('click', () => window.copyClicked = true);
                    document.body.appendChild(block);
                    block.querySelector('button').click();
                    return getComputedStyle(block).contentVisibility === 'visible' && window.copyClicked === true;
                })()
                """, "Streamed blocks receive the fix and keep their controls")
            // Repeated script execution must not accumulate styles on SPA navigation.
            _ = try await page.webView.evaluateJavaScript(ChatGPTWebCompatibility.source)
            try await page.check("document.querySelectorAll('#chappytab-code-rendering').length === 1",
                                 "The stylesheet is installed once per document")
        }
        for host in ["example.com", "chatgpt.com.example.com"] {
            try await page.load(host: host)
            try await page.check("!document.getElementById('chappytab-code-rendering')",
                                 "External pages are unchanged")
            try await page.check("getComputedStyle(document.querySelector('pre')).contentVisibility === 'auto'",
                                 "External code blocks are unchanged")
        }
        print("PASS: code rendering, streamed blocks, controls, highlighting, reloads, host scope, popup configuration")
    }

    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw TestFailure(message: message) }
    }
}

private struct TestFailure: Error {
    let message: String
}

@MainActor
private final class TestPage: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private var navigation: CheckedContinuation<Void, Error>?

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func load(host: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            navigation = continuation
            webView.loadHTMLString("""
                <!doctype html><html><head>
                <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'nonce-fixture'">
                <style nonce="fixture">
                pre, code, #unrelated { content-visibility: auto; }
                code span { color: rgb(120, 40, 160); }
                </style></head><body>
                <pre><button>Copy</button><code><span>let</span> value = 42</code></pre>
                <div id="unrelated">Other content</div>
                </body></html>
                """, baseURL: URL(string: "https://\(host)/"))
        }
    }

    func check(_ script: String, _ message: String) async throws {
        let result = try await webView.evaluateJavaScript(script)
        try ChatGPTWebCompatibilityTests.require(result as? Bool == true, message)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.navigation?.resume()
        self.navigation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.navigation?.resume(throwing: error)
        self.navigation = nil
    }
}
