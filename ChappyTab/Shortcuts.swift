import AppKit
import SwiftUI
import Observation

enum BrowserAction: String, CaseIterable, Identifiable, Codable {
    case newTab, closeTab, nextTab, previousTab
    var id: String { rawValue }
    var title: LocalizedStringResource {
        switch self {
        case .newTab: "新しいタブ"
        case .closeTab: "タブを閉じる"
        case .nextTab: "右のタブに移動"
        case .previousTab: "左のタブに移動"
        }
    }
    var defaultKey: String {
        switch self {
        case .newTab: "t"
        case .closeTab: "w"
        case .nextTab: "n"
        case .previousTab: "p"
        }
    }
}

struct Shortcut: Codable, Equatable {
    var key: String
    var command = true
    var shift = false
    var option = false
    var control = false

    private enum CodingKeys: String, CodingKey { case key, command, shift, option, control }
    init(key: String, command: Bool = true, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key; self.command = command; self.shift = shift; self.option = option; self.control = control
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        key = try values.decode(String.self, forKey: .key)
        // Older saved shortcuts always included Command.
        command = try values.decodeIfPresent(Bool.self, forKey: .command) ?? true
        shift = try values.decode(Bool.self, forKey: .shift)
        option = try values.decode(Bool.self, forKey: .option)
        control = try values.decode(Bool.self, forKey: .control)
    }
    var modifiers: EventModifiers {
        var result: EventModifiers = []
        if command { result.insert(.command) }
        if shift { result.insert(.shift) }
        if option { result.insert(.option) }
        if control { result.insert(.control) }
        return result
    }
    var display: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + key.uppercased()
    }
}

@MainActor @Observable
final class ShortcutSettings {
    private var shortcuts: [String: Shortcut]
    private static let storageKey = "browser.shortcuts.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([String: Shortcut].self, from: data) {
            shortcuts = saved
        } else { shortcuts = [:] }
    }

    func shortcut(for action: BrowserAction) -> Shortcut {
        shortcuts[action.rawValue] ?? Shortcut(
            key: action.defaultKey,
            command: action == .newTab || action == .closeTab,
            control: action == .nextTab || action == .previousTab
        )
    }

    func validationError(for candidate: Shortcut, action: BrowserAction) -> String? {
        guard candidate.key.count == 1,
              candidate.key.range(of: "^[a-z0-9]$", options: .regularExpression) != nil else {
            return "半角英数字キーを使用してください。"
        }
        guard candidate.command || candidate.control || candidate.option else {
            return "Command、Control、Optionのいずれかを組み合わせてください。"
        }
        guard !BrowserAction.allCases.contains(where: { $0 != action && shortcut(for: $0) == candidate }) else {
            return "ほかのタブ操作と重複しています。"
        }
        let reserved = ["q", "h", "m", "a", "c", "v", "x", "z", "s", "o", "f", "r"]
        if candidate.command && !candidate.shift && !candidate.option && !candidate.control && reserved.contains(candidate.key) {
            return "この組み合わせは標準操作で使用されています。"
        }
        return nil
    }

    func update(_ shortcut: Shortcut, for action: BrowserAction) {
        guard validationError(for: shortcut, action: action) == nil else { return }
        shortcuts[action.rawValue] = shortcut
        save()
    }

    func reset() { shortcuts = [:]; save() }
    private func save() {
        if let data = try? JSONEncoder().encode(shortcuts) { UserDefaults.standard.set(data, forKey: Self.storageKey) }
    }
}

struct ShortcutSettingsView: View {
    let settings: ShortcutSettings
    @State private var editingAction: BrowserAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("キーボードショートカット").font(.title2.bold())
            Text("変更する操作をクリックして、キーを入力してください。")
                .foregroundStyle(.secondary)
            List(BrowserAction.allCases) { action in
                ShortcutRow(action: action, shortcut: settings.shortcut(for: action)) {
                    editingAction = action
                }
            }
            .listStyle(.inset)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Spacer()
                Button("初期設定に戻す") { settings.reset() }
            }
        }
        .padding(24)
        .frame(width: 540, height: 340)
        .sheet(item: $editingAction) { action in
            ShortcutRecordingDialog(action: action, settings: settings)
        }
    }
}

private struct ShortcutRow: View {
    let action: BrowserAction
    let shortcut: Shortcut
    let edit: () -> Void
    var body: some View {
        Button(action: edit) {
            HStack {
                Text(action.title)
                Spacer()
                Text(shortcut.display)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ShortcutRecordingDialog: View {
    let action: BrowserAction
    let settings: ShortcutSettings
    @Environment(\.dismiss) private var dismiss
    @State private var candidate: Shortcut?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            Text(action.title).font(.headline)
            Text("設定するショートカットキーを押してください")
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                Text(candidate?.display ?? "キー入力を待っています…")
                    .font(.system(.title2, design: .monospaced))
                ShortcutRecorder { shortcut in
                    candidate = shortcut
                    error = settings.validationError(for: shortcut, action: action)
                } cancel: { dismiss() }
                .frame(width: 1, height: 1)
            }
            .frame(height: 80)
            Text(error ?? "Command・Control・Optionと半角英数字を組み合わせます。")
                .font(.caption)
                .foregroundStyle(error == nil ? Color.secondary : .red)
                .frame(height: 32)
            HStack {
                Button("キャンセル") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    if let candidate { settings.update(candidate, for: action); dismiss() }
                }
                .disabled(candidate == nil || error != nil)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let record: (Shortcut) -> Void
    let cancel: () -> Void
    func makeNSView(context: Context) -> RecordingView {
        let view = RecordingView()
        view.record = record
        view.cancel = cancel
        return view
    }
    func updateNSView(_ nsView: RecordingView, context: Context) {
        nsView.record = record
        nsView.cancel = cancel
    }

    final class RecordingView: NSView {
        var record: ((Shortcut) -> Void)?
        var cancel: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self)
            }
        }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { cancel?(); return }
            if event.keyCode == 48 { super.keyDown(with: event); return }
            capture(event)
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else { return false }
            if event.keyCode == 53 { cancel?(); return true }
            capture(event)
            return true
        }
        private func capture(_ event: NSEvent) {
            guard !event.isARepeat, let key = event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else { return }
            let flags = event.modifierFlags
            record?(Shortcut(key: key, command: flags.contains(.command), shift: flags.contains(.shift),
                             option: flags.contains(.option), control: flags.contains(.control)))
        }
    }
}
