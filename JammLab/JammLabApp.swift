import AppKit
import SwiftUI

@main
struct JammLabApp: App {
    @NSApplicationDelegateAdaptor(JammLabAppDelegate.self) private var appDelegate
    @StateObject private var settingsStore: AppSettingsStore
    @StateObject private var viewModel: AudioPlayerViewModel
    @StateObject private var recentProjectsStore = RecentProjectsStore.shared

    init() {
        let settingsStore = AppSettingsStore()
        _settingsStore = StateObject(wrappedValue: settingsStore)
        _viewModel = StateObject(wrappedValue: AudioPlayerViewModel(appSettingsStore: settingsStore))
    }

    var body: some Scene {
        WindowGroup("JammLab", id: "main") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: AppTheme.Window.minWidth, minHeight: AppTheme.Window.minHeight)
                .environment(\.appColors, AppThemeColors(palette: settingsStore.colorPalette))
                .onAppear {
                    appDelegate.viewModel = viewModel
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .commands {
            JammLabCommands(
                viewModel: viewModel,
                recentProjectsStore: recentProjectsStore
            )
        }

        WindowGroup("Keyboard Shortcuts", id: "hotkeys-help") {
            HotkeysHelpView()
                .environment(\.appColors, AppThemeColors(palette: settingsStore.colorPalette))
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(settingsStore: settingsStore)
                .environment(\.appColors, AppThemeColors(palette: settingsStore.colorPalette))
        }
    }
}

struct JammLabCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var viewModel: AudioPlayerViewModel
    @ObservedObject var recentProjectsStore: RecentProjectsStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project") {
                viewModel.newProject()
            }
            .keyboardShortcut("n", modifiers: [.command])

            Divider()

            Button("Open Project...") {
                Task {
                    await viewModel.openProject()
                }
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button("Import New File...") {
                Task {
                    await viewModel.importAudio()
                }
            }

            Divider()

            Text("Recently Opened")

            if recentProjectsStore.entries.isEmpty {
                Text("No Recent Projects")
            } else {
                ForEach(recentProjectsStore.entries) { entry in
                    Button(entry.displayName) {
                        Task {
                            await viewModel.openRecentProject(entry)
                        }
                    }
                }

                Button("Clear Recent Projects") {
                    recentProjectsStore.clear()
                }
            }

            Divider()

            Button("Save Project") {
                Task {
                    await viewModel.saveProject()
                }
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button("Save Project As...") {
                Task {
                    await viewModel.saveProjectAs()
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                viewModel.undoLastEdit()
            }
            .keyboardShortcut("z", modifiers: [.command])
            .disabled(!viewModel.canUndo)

            Button("Redo") {
                viewModel.redoLastEdit()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!viewModel.canRedo)
        }

        CommandGroup(after: .toolbar) {
            Button("Video Window") {
                viewModel.showVideoWindow()
            }
            .disabled(!viewModel.canShowVideoWindow)
        }

        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") {
                openWindow(id: "hotkeys-help")
            }
            .keyboardShortcut("/", modifiers: [.command])
        }
    }
}
