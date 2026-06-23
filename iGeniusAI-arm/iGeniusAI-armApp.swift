import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct iGeniusAI_armApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
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
