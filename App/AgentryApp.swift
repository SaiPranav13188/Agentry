import SwiftData
import SwiftUI

@main
struct AgentryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppState.shared

    var body: some Scene {
        Window("Agentry", id: "main") {
            MainView()
                .environment(app)
                .modelContainer(app.container)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { AgentryCommands(app: app) }

        MenuBarExtra {
            MenuBarView()
                .environment(app)
                .modelContainer(app.container)
        } label: {
            MenuBarLabel()
                .environment(app)
                .modelContainer(app.container)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.start()
    }

    /// Closing the window keeps Agentry running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppState.shared.bringToFront() }
        return true
    }
}

struct AgentryCommands: Commands {
    let app: AppState

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                app.section = .settings
                app.bringToFront()
            }
            .keyboardShortcut(",")
        }
        CommandMenu("Go") {
            ForEach(AppSection.allCases) { section in
                Button(section.title) { withMotion { app.section = section } }
                    .keyboardShortcut(KeyEquivalent(section.shortcut), modifiers: .command)
            }
            Divider()
            Button("Command Palette") { withMotion(Motion.quick) { app.showCommandPalette.toggle() } }
                .keyboardShortcut("k", modifiers: .command)
            Button("Check for New Mail") { app.polling.checkNow() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Keyboard Shortcuts") { app.showShortcuts = true }
        }
    }
}
