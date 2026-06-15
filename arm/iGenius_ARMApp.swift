import SwiftUI

@main
struct iGenius_ARMApp: App {
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
