# Build Instructions for iGenius_OBJC

To get this project running on your MacBook Pro A1278 (macOS 10.9 with Xcode 6.2):

### 1. Create a New Xcode Project
- Open Xcode 6.2.
- File > New > Project...
- Select **OS X > Application > Cocoa Application**.
- Product Name: `iGenius_OBJC`.
- Language: **Objective-C**.
- Deployment Target: **10.9**.
- Uncheck "Use Storyboards" (we are using programmatic UI for maximum compatibility).
- Uncheck "Create Document-Based Application" and "Use Core Data".

### 2. Import the Files
- Drag and drop the following folders/files from the `iGenius_OBJC` folder into your Xcode project navigator:
  - `AppDelegate.h` and `AppDelegate.m` (Replace the ones Xcode created).
  - `main.m` (Replace the one Xcode created).
  - `Models/` folder.
  - `Services/` folder.
  - `UI/` folder.
  - `Resources/` folder (once created).

### 3. Configure Info.plist
- Ensure `NSAppleScriptEnabled` is set to `YES` if you plan to add more advanced AppleScript features later, though for `NSAppleScript` class it's not strictly required for basic execution.
- Set `NSPrincipalClass` to `NSApplication`.

### 4. Build and Run
- Select your Mac as the target.
- Hit **Cmd + R**.

### Note on AppleScript
The application talks to **iTunes**. Ensure iTunes is open for the Genius features to work. If you encounter permissions errors on later OS versions (like 10.13), you might need to grant the app "Automation" permissions in System Preferences > Security & Privacy.
