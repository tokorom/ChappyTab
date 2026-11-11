import SwiftUI

@main
struct MyApp: App {
    @State private var browser = BrowserModel()
    @State private var shortcuts = ShortcutSettings()

    var body: some Scene {
        Window("ChappyTab", id: "browser") {
            ContentView(browser: browser)
                .onAppear { browser.installShortcuts(shortcuts) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                actionButton(.newTab) { browser.addTab() }
            }
            CommandGroup(replacing: .saveItem) {
                actionButton(.closeTab) {
                    if let id = browser.selectedID { browser.closeTab(id) }
                }
                .disabled(browser.selectedTab?.webView.window == nil || NSApp.keyWindow !== browser.selectedTab?.webView.window)
            }
            CommandMenu("タブ") {
                actionButton(.nextTab) { browser.selectRelative(1) }
                actionButton(.previousTab) { browser.selectRelative(-1) }
            }
        }
        Settings {
            SettingsView(shortcuts: shortcuts)
        }
        .defaultSize(width: 780, height: 460)
    }

    private func actionButton(_ action: BrowserAction, perform: @escaping () -> Void) -> some View {
        let shortcut = shortcuts.shortcut(for: action)
        return Button(action.title, action: perform)
            .keyboardShortcut(KeyEquivalent(Character(shortcut.key)), modifiers: shortcut.modifiers)
    }
}
