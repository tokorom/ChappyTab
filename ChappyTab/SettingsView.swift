import AppKit
import SwiftUI

struct SettingsView: View {
    let shortcuts: ShortcutSettings
    @State private var selection: SettingsSection? = .shortcuts

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("キーボードショートカット", systemImage: "keyboard")
                    .tag(SettingsSection.shortcuts)
                Label("About", systemImage: "info.circle")
                    .tag(SettingsSection.about)
            }
            .listStyle(.sidebar)
            .navigationTitle("設定")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            switch selection ?? .shortcuts {
            case .shortcuts:
                ShortcutSettingsView(settings: shortcuts)
                    .navigationTitle("キーボードショートカット")
            case .about:
                AboutSettingsView()
                    .navigationTitle("About")
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 420)
    }

    private enum SettingsSection: Hashable {
        case shortcuts
        case about
    }
}

private struct AboutSettingsView: View {
    private static let appIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    private let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "ChappyTab"
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            Image(nsImage: Self.appIcon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 128, height: 128)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(appName)
                    .font(.system(size: 36, weight: .regular))
                    .accessibilityAddTraits(.isHeader)
                Text("Version \(version) (\(build))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    .textSelection(.enabled)

                Text("ChatGPTを、もっと快適に。")
                    .padding(.top, 32)
                Text("複数の会話をタブで管理するmacOSアプリ。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)

                Link("GitHub", destination: URL(string: "https://github.com/tokorom/ChappyTab")!)
                    .padding(.top, 24)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
