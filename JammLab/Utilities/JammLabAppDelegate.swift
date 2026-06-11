import AppKit

@MainActor
final class JammLabAppDelegate: NSObject, NSApplicationDelegate {
    weak var viewModel: AudioPlayerViewModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let viewModel, viewModel.isProjectModified else {
            return .terminateNow
        }

        Task { @MainActor in
            let shouldTerminate = await Self.confirmClose(viewModel: viewModel)
            sender.reply(toApplicationShouldTerminate: shouldTerminate)
        }

        return .terminateLater
    }

    private static func confirmClose(viewModel: AudioPlayerViewModel) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save changes to this project?"
        alert.informativeText = "Your project has unsaved changes."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return await viewModel.saveProjectForClose()
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }
}
