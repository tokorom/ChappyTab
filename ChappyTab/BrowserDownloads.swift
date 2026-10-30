import AppKit
import WebKit

/// Owned by the app rather than a tab, so closing a tab doesn't lose its downloads.
@MainActor
final class BrowserDownloads: NSObject, WKDownloadDelegate {
    static let shared = BrowserDownloads()

    private final class Transfer {
        let download: WKDownload
        weak var window: NSWindow?
        var destination: URL?
        var temporaryDirectory: URL?
        var hasSecurityScope = false

        init(download: WKDownload, window: NSWindow?) {
            self.download = download
            self.window = window
        }

        func cleanUp() {
            if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
            if hasSecurityScope { destination?.stopAccessingSecurityScopedResource() }
        }
    }

    private var transfers: [ObjectIdentifier: Transfer] = [:]

    func receive(_ download: WKDownload, window: NSWindow?) {
        transfers[ObjectIdentifier(download)] = Transfer(download: download, window: window)
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
        guard let transfer = transfers[ObjectIdentifier(download)] else {
            completionHandler(nil)
            return
        }
        let panel = NSSavePanel()
        panel.title = "ダウンロードを保存"
        panel.nameFieldStringValue = (suggestedFilename as NSString).lastPathComponent
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let choose: (NSApplication.ModalResponse) -> Void = { [self, panel] result in
            guard result == .OK, let destination = panel.url else {
                completionHandler(nil)
                finish(download)
                return
            }
            transfer.destination = destination
            transfer.hasSecurityScope = destination.startAccessingSecurityScopedResource()
            do {
                // WebKit requires a destination that doesn't exist. Stage the transfer first,
                // preserving any existing user file until the download succeeds.
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                transfer.temporaryDirectory = directory
                completionHandler(directory.appendingPathComponent("download"))
            } catch {
                completionHandler(nil)
                report(error, window: transfer.window)
                finish(download)
            }
        }
        if let window = transfer.window {
            panel.beginSheetModal(for: window, completionHandler: choose)
        } else {
            panel.begin(completionHandler: choose)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let transfer = transfers[ObjectIdentifier(download)] else { return }
        defer { finish(download) }
        guard let destination = transfer.destination, let directory = transfer.temporaryDirectory else { return }
        let source = directory.appendingPathComponent("download")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: source)
            } else {
                try FileManager.default.moveItem(at: source, to: destination)
            }
            NSWorkspace.shared.noteFileSystemChanged(destination.deletingLastPathComponent().path)
        } catch {
            report(error, window: transfer.window)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let window = transfers[ObjectIdentifier(download)]?.window
        finish(download)
        if (error as NSError).code != NSURLErrorCancelled { report(error, window: window) }
    }

    private func finish(_ download: WKDownload) {
        transfers.removeValue(forKey: ObjectIdentifier(download))?.cleanUp()
    }

    private func report(_ error: Error, window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "ダウンロードを保存できませんでした"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}
