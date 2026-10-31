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
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 720, minHeight: 480)
    }
}

private struct TabBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let browser: BrowserModel
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 4) {
                // Keep the native close, minimize and fullscreen controls unobstructed.
                Color.clear.frame(width: 78)
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
                        .padding(.vertical, 5)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: browser.selectedID) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                    .onChange(of: browser.tabs.count) { _, _ in
                        if let id = browser.selectedID { proxy.scrollTo(id) }
                    }
                }
                .frame(width: min(CGFloat(browser.tabs.count) * 214 - 4,
                                  max(0, geometry.size.width - 170)))
                Button { browser.addTab() } label: {
                    Image(systemName: "plus").frame(width: 30, height: 34)
                }
                .help("新しいタブ")
                .accessibilityLabel("新しいタブ")
                WindowDragArea()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
            .frame(height: 44)
        }
        .frame(height: 44)
        .buttonStyle(.plain)
        .background(colorScheme == .dark
                    ? Color(red: 0.14, green: 0.20, blue: 0.23)
                    : Color(red: 0.73, green: 0.89, blue: 0.93))
    }

}

private struct TabItem: View {
    @Environment(\.colorScheme) private var colorScheme
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
                    Text(tab.title)
                        .fontWeight(selected ? .semibold : .regular)
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
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
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 9)
                    .fill(colorScheme == .dark ? Color(white: 0.28) : .white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(.primary.opacity(0.16), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            } else {
                HStack {
                    Spacer()
                    Rectangle().fill(.primary.opacity(0.22)).frame(width: 1, height: 16)
                }
            }
        }
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
            BrowserAddressField(address: tab.address)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
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

/// Only the empty part of the tab strip handles window dragging.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")
                switch action {
                case "Minimize": window.performMiniaturize(nil)
                case "None": break
                default: window.performZoom(nil)
                }
            } else {
                window.performDrag(with: event)
            }
        }
    }
}

/// A selectable, read-only address field. Its entire padded area selects the URL.
private struct BrowserAddressField: NSViewRepresentable {
    let address: String

    func makeNSView(context: Context) -> AddressTextField {
        let field = AddressTextField()
        field.cell = PaddedAddressCell()
        field.isEditable = false
        field.isSelectable = true
        field.isBezeled = false
        field.drawsBackground = true
        field.backgroundColor = .controlBackgroundColor
        field.textColor = .labelColor
        field.font = .systemFont(ofSize: 12)
        field.lineBreakMode = .byTruncatingMiddle
        field.wantsLayer = true
        field.layer?.cornerRadius = 8
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel("現在のURL")
        field.toolTip = "クリックでURL全体を選択・⌘Cでコピー"
        return field
    }

    func updateNSView(_ field: AddressTextField, context: Context) {
        guard field.stringValue != address else { return }
        let wasSelected = field.currentEditor() != nil
        field.stringValue = address
        if wasSelected { field.selectText(nil) }
    }

    final class AddressTextField: NSTextField {
        override func mouseDown(with event: NSEvent) {
            selectText(nil)
        }
    }

    final class PaddedAddressCell: NSTextFieldCell {
        override func drawingRect(forBounds rect: NSRect) -> NSRect {
            var bounds = super.drawingRect(forBounds: rect.insetBy(dx: 10, dy: 0))
            let height = cellSize(forBounds: bounds).height
            bounds.origin.y += max(0, (bounds.height - height) / 2)
            bounds.size.height = min(bounds.height, height)
            return bounds
        }
    }
}
