import SwiftUI
import WebKit

struct ContentView: View {
    let browser: BrowserModel
    var body: some View {
        VStack(spacing: 0) {
            TabBar(browser: browser)
            Divider()
            if let tab = browser.selectedTab {
                BrowserToolbar(tab: tab)
                Divider()
                if let error = tab.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                        Text(error).lineLimit(2)
                        Spacer()
                        Button("再読み込み") { tab.webView.reload() }
                    }
                    .padding(10)
                    .background(.orange.opacity(0.12))
                }
                BrowserWebView(webView: tab.webView)
                    .id(tab.id)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}

private struct TabBar: View {
    let browser: BrowserModel
    var body: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(browser.tabs) { tab in
                            TabItem(tab: tab, selected: browser.selectedID == tab.id,
                                    select: { browser.selectedID = tab.id },
                                    close: { browser.closeTab(tab.id) })
                                .id(tab.id)
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.hidden)
                .onChange(of: browser.selectedID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
            Button { browser.addTab() } label: { Image(systemName: "plus") }
                .help("新しいタブ")
                .accessibilityLabel("新しいタブ")
                .padding(.trailing, 12)
        }
        .buttonStyle(.plain)
        .background(.bar)
    }
}

private struct TabItem: View {
    let tab: BrowserTab
    let selected: Bool
    let select: () -> Void
    let close: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Button(action: select) {
                HStack(spacing: 8) {
                    Image(systemName: tab.isLoading ? "arrow.trianglehead.2.clockwise" : "bubble.left.and.bubble.right")
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                    Text(tab.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .accessibilityAddTraits(selected ? .isSelected : [])
            Button(action: close) { Image(systemName: "xmark").font(.caption) }
                .accessibilityLabel("タブを閉じる")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(width: 210)
        .background(selected ? Color(nsColor: .controlBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .help(tab.title)
    }
}

private struct BrowserToolbar: View {
    let tab: BrowserTab
    var body: some View {
        HStack(spacing: 16) {
            Button { tab.webView.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!tab.canGoBack).help("戻る")
            Button { tab.webView.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!tab.canGoForward).help("進む")
            Button {
                if tab.isLoading { tab.webView.stopLoading() } else { tab.webView.reload() }
            } label: { Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise") }
                .help(tab.isLoading ? "読み込みを停止" : "再読み込み")
            Button { tab.goHome() } label: { Image(systemName: "house") }.help("ChatGPTを開く")
            Text(tab.address)
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if tab.isLoading { ProgressView().controlSize(.small) }
            SettingsLink { Image(systemName: "gearshape") }.help("設定")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

private struct BrowserWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
