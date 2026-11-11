import WebKit

@MainActor
enum ChatGPTWebCompatibility {
    static func install(in controller: WKUserContentController) {
        // Popup configurations may share the parent's content controller.
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
        const styleID = "chappytab-code-corners";
        if (document.getElementById(styleID)) return;

        const style = document.createElement("style");
        style.id = styleID;
        const nonceSource = document.querySelector('meta[name="csp-nonce"], style[nonce], script[nonce]');
        if (nonceSource?.nonce) style.nonce = nonceSource.nonce;
        // WebKit can paint only the background of clipped code blocks using
        // corner-shape: superellipse(1.1). Ordinary round corners restore their
        // content and controls without changing the code, layout, or scrolling.
        // The selector also covers blocks added by streaming and SPA navigation.
        style.textContent = `[data-code-block] { corner-shape: round !important; }`;
        (document.head || document.documentElement).appendChild(style);
    })();
    """#
}
