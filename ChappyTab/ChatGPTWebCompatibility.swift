import WebKit

/// Keep code blocks painted when WebKit skips offscreen content during scrolling.
@MainActor
enum ChatGPTWebCompatibility {
    static func install(in controller: WKUserContentController) {
        // Popup configurations can share their parent's user content controller.
        guard !controller.userScripts.contains(where: { $0.source == source }) else { return }
        controller.addUserScript(WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: .defaultClient
        ))
    }

    static let source = #"""
    (() => {
        if (!["chatgpt.com", "chat.openai.com"].includes(location.hostname)) return;
        const styleID = "chappytab-code-rendering";
        if (document.getElementById(styleID)) return;

        const style = document.createElement("style");
        style.id = styleID;
        // ChatGPT requires its per-document CSP nonce on inline styles.
        const nonceSource = document.querySelector('meta[name="csp-nonce"], style[nonce], script[nonce]');
        if (nonceSource?.nonce) style.nonce = nonceSource.nonce;
        // WebKit can leave content-visibility:auto subtrees blank after scrolling.
        // A stylesheet also covers code blocks added later by streaming or navigation.
        // Keep the page's code text, syntax highlighting, and copy controls intact.
        style.textContent = `
            pre,
            pre *,
            [data-markdown-copy="code-block"],
            [data-markdown-copy="code-block"] * {
                content-visibility: visible !important;
            }
        `;
        (document.head || document.documentElement).appendChild(style);
    })();
    """#
}
