import AppKit
import SwiftUI

@main
struct StorageLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("StorageLens") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan Home Folder") { state.startScan(.home) }
                    .keyboardShortcut("r")
                Button("Scan Whole Disk") { state.startScan(.disk) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Scan Folder…") { state.chooseFolder() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .help) {
                Button("Welcome Guide") { state.showOnboarding = true }
                Button("Full Disk Access Settings…") { state.openFullDiskAccessSettings() }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when the binary runs outside an .app bundle (`swift run`).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
