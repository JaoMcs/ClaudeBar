import AppKit
import SwiftUI

@main
struct ClaudeBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = SessionStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            // O símbolo diz o que está acontecendo; o número, quantas sessões
            // estão abertas — e ele fica sempre visível.
            Image(systemName: store.barState.symbolName)
            Text("\(store.openSessionCount)")
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sem Dock, sem App Switcher: o app vive só na barra de menu.
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
