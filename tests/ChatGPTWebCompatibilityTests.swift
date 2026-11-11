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
        configuration.userContentController.addUserScript(WKUserScript(
            source: "window.existingScript = true;", injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))
        ChatGPTWebCompatibility.install(in: configuration.userContentController)
        ChatGPTWebCompatibility.install(in: configuration.userContentController)
        try require(configuration.userContentController.userScripts.count == 2,
                    "Popup installation must not duplicate scripts or remove existing scripts")

        let page = TestPage(configuration: configuration)
        for host in ["chatgpt.com", "chat.openai.com"] {
            try await page.load(host: host)
            try await page.check("window.existingScript === true", "Existing scripts must still run")
            try await page.check("""
                (() => {
                    const block = document.querySelector('[data-code-block]');
                    const style = getComputedStyle(block);
                    return style.getPropertyValue('corner-shape') === getComputedStyle(document.querySelector('#round-reference')).getPropertyValue('corner-shape')
                        && style.borderRadius === '24px' && style.overflow === 'clip'
                        && block.offsetWidth === 600
                        && block.querySelector('code').textContent === 'let value = 42'
                        && getComputedStyle(block.querySelector('span')).color === 'rgb(120, 40, 160)';
                })()
                """, "Only the code block's corner shape should change under a strict CSP")
            try await page.check("""
                (() => {
                    const block = document.createElement('div');
                    block.setAttribute('data-code-block', '');
                    block.innerHTML = '<button>Copy</button><pre><code>streamed code</code></pre>';
                    block.querySelector('button').addEventListener('click', () => window.copyClicked = true);
                    document.body.appendChild(block);
                    block.querySelector('button').click();
                    return getComputedStyle(block).getPropertyValue('corner-shape') === getComputedStyle(document.querySelector('#round-reference')).getPropertyValue('corner-shape')
                        && window.copyClicked === true;
                })()
                """, "Streamed blocks must receive the fix and retain their controls")
            _ = try await page.webView.evaluateJavaScript(ChatGPTWebCompatibility.source)
            try await page.check("document.querySelectorAll('#chappytab-code-corners').length === 1",
                                 "The stylesheet must not be duplicated")
            try await page.check("!CSS.supports('corner-shape: superellipse(1.1)') || getComputedStyle(document.querySelector('#unrelated')).getPropertyValue('corner-shape') === 'superellipse(1.1)'",
                                 "Other surfaces must keep their corner shape")
        }
        for host in ["example.com", "chatgpt.com.example.com"] {
            try await page.load(host: host)
            try await page.check("!document.getElementById('chappytab-code-corners')",
                                 "External pages must not receive the stylesheet")
        }
        print("PASS: CSP, corner fallback, layout, text, highlighting, streamed blocks, controls, host scope, popup configuration")
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
                <meta name="csp-nonce" nonce="fixture">
                <style nonce="fixture">
                [data-code-block], #unrelated { corner-shape: superellipse(1.1); }
                [data-code-block] { width: 600px; border-radius: 24px; overflow: clip; contain: inline-size; }
                #round-reference { corner-shape: round; }
                code span { color: rgb(120, 40, 160); }
                </style></head><body>
                <div data-code-block><button>Copy</button><pre><code><span>let</span> value = 42</code></pre></div>
                <div id="unrelated">Other content</div><div id="round-reference"></div>
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
