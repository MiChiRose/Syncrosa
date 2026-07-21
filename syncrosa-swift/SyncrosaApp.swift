import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct SyncrosaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appearance = SyncrosaAppearanceService.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearance.appearanceMode.preferredColorScheme)
                .tint(appearance.selectedTheme.accent)
                // Prevent creating multiple tabs in macOS
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = false
                }
        }
        .windowStyle(.hiddenTitleBar)
        // Remove standard "New Window" and Tab commands
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .windowList) {}
        }
    }
}
