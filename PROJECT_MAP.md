# Syncrosa Project Map 🎵🤖

This file serves as a reference map of the **Syncrosa** project. It outlines the codebase structure, entry points, routing, architectures, and features of all three platform implementations: **SwiftUI**, **Objective-C (Legacy Cocoa)**, and **Python (Tkinter Legacy)**.

---

## 📌 Project Overview
Syncrosa is an application designed to organize, fix, and enhance classic iTunes and modern Apple Music libraries. It has three separate native implementations sharing feature parity:
1. **SwiftUI (`syncrosa-swift`)**: Modern native version for macOS 14+ (Sonoma/Sequoia) running on Apple Silicon, interacting with `Music.app`.
2. **Objective-C AppKit (`syncrosa-objc`)**: Classic Cocoa version for vintage Macs running OS X 10.9 (Mavericks) up to 10.13 (High Sierra), interacting with `iTunes`.
3. **Python Tkinter (`syncrosa-python`)**: Multi-version lightweight Tkinter implementation supporting both Python 2.7 (built-in on old OS X) and Python 3 (modern macOS).

---

## 🛠 Feature Parity Matrix

| Feature | Swift (`syncrosa-swift`) | Obj-C (`syncrosa-objc`) | Python (`syncrosa-python`) |
| :--- | :--- | :--- | :--- |
| **Genius AI Playlists** | Yes (Gemini/Groq/OpenRouter) | Yes (Gemini/Groq/OpenRouter) | Yes (Gemini/Groq/OpenRouter) |
| **Media Fixer** | Yes (Apple Search API) | Yes (Apple Search API) | Yes (Apple Search API) |
| **Covers Optimizer** | Yes (AppleScript + NSImage) | Yes (AppleScript + AppKit) | Yes (AppleScript + Pillow/Lazy) |
| **USB Export** | Yes (FAT32/ExFAT compatible) | Yes (FAT32/ExFAT compatible) | No (Platform limitation) |
| **Settings Storage** | OS X Keychain (API Key) | OS X Keychain (API Key) | JSON Config `~/.syncrosa.json` |
| **Localization** | 10 Languages (Service-based) | 10 Languages (Service-based) | 10 Languages (Dictionary-based) |
| **Target Hosts** | macOS 14+ Apple Music | OS X 10.9-10.13 iTunes | OS X 10.9+ iTunes |

---

## 📂 Codebase Structures & Routing

### 1. Swift ARM (`syncrosa-swift`)
Built using SwiftUI for Apple Silicon Macs.

#### 📁 Directory Tree:
* **`SyncrosaApp.swift`** — Main entry point of the SwiftUI application.
* **`ContentView.swift`** — Core layout window hosting the tabbed navigation.
* **`Info.plist`** — Package metadata, entitlements, and target versions (macOS 14.0+).
* **`Package.swift`** — Swift Package Manager configuration.
* **`build_arm.sh`** — Compilation script to build, ad-hoc sign, and package into `Syncrosa_SwiftUI_ARM.zip` on the Desktop.
* **`Services/`** (Business Logic)
  * `AIService.swift` — AI API calls (Gemini, Groq, OpenRouter).
  * `MusicService.swift` — Scripting bridge to control `Music.app`.
  * `CoversOptimizerService.swift` — Artwork extraction, resizing via `NSImage`, backup & restore.
  * `USBService.swift` — Detection of external drives for playlist export.
  * `KeychainHelper.swift` — Secure storage of API keys in system Keychain.
  * `LocalizationService.swift` — Dict-based i18n support.
* **`Views/`** (UI Components)
  * `PlaylistGeneratorView.swift` — UI for AI Genius.
  * `MediaFixerView.swift` — UI for correcting iTunes tag information.
  * `CoversOptimizerView.swift` — UI for artwork compression.
  * `USBExportView.swift` — UI for transferring playlists to USB drives.
  * `SettingsView.swift` — Setup of provider models and API keys.

#### 🔀 Routing:
* **`ContentView.swift`** handles routing through a vertical or tabbed SwiftUI layout (`TabView`) with tabs:
  1. *Genius* -> `PlaylistGeneratorView`
  2. *Media Fixer* -> `MediaFixerView`
  3. *Covers Optimizer* -> `CoversOptimizerView`
  4. *USB Export* -> `USBExportView`
  5. *Settings* -> `SettingsView` (Modal or embedded)

---

### 2. Objective-C Cocoa (`syncrosa-objc`)
Built using AppKit for vintage macOS (Intel `x86_64` + ARM `arm64` universal binaries).

#### 📁 Directory Tree:
* **`update_project.py`** — Python utility script to update Xcode project files.
* **`build_legacy.sh`** — Compiles the target via `xcodebuild`, copies local outputs, and packages them into `Syncrosa_Cocoa_Legacy.zip` on the Desktop.
* **`Sources/`**
  * `main.m` — System entry point.
  * `AppDelegate.h/.m` — App delegate setting up the principal window.
  * `Base.lproj/MainMenu.xib` — Main interface definition (menus and basic window controls).
  * `Info.plist` — Target bundle configuration (OS X 10.9+).
  * **`Models/`**
    * `IGTrack.h/.m` — Model mapping tracks from iTunes.
  * **`Services/`**
    * `IGiTunesService.h/.m` — Controls Apple iTunes app via `NSAppleScript`.
    * `IGAIService.h/.m` — Network service contacting Gemini, Groq, or OpenRouter.
    * `IGCoversOptimizerViewController.h/.m` — Logic/Controller to backup, resize, and restore artwork.
    * `IGMediaFixerManager.h/.m` — Manager to fetch tags and group split albums.
    * `IGUSBService.h/.m` — USB drive detector and exporter.
    * `IGKeychainHelper.h/.m` — OS X Keychain access wrapper.
    * `IGLocalizationService.h/.m` — Dictionaries with translations.
    * `IGLogger.h/.m` — Diagnostics output logger.
  * **`UI/`**
    * `IGMainWindowController.h/.m` — Main frame controller directing navigation.
    * `IGGeniusViewController.h/.m` — Panel for Genius AI Playlist.
    * `IGFixerViewController.h/.m` — Panel for merging split albums.
    * `IGFileFixerViewController.h/.m` — Panel for fixing empty metadata.
    * `IGCoversOptimizerViewController.h/.m` — Panel for covers backup/resizing.
    * `IGUSBExportViewController.h/.m` — Panel for exporting tracks.
    * `IGSettingsViewController.h/.m` — Panel for managing API settings.

#### 🔀 Routing:
* Navigation is handled inside **`IGMainWindowController.m`** using an sidebar table view (`NSTableView` acting as a navigation sidebar) or tabs.
* It dynamically swaps view controllers inside a main container view (`NSView`):
  1. *Genius* -> `IGGeniusViewController`
  2. *Media Fixer* -> `IGFixerViewController` & `IGFileFixerViewController`
  3. *Covers Optimizer* -> `IGCoversOptimizerViewController`
  4. *USB Export* -> `IGUSBExportViewController`
  5. *Settings* -> `IGSettingsViewController`

---

### 3. Python Legacy (`syncrosa-python`)
Built using Tkinter for backward compatibility (supporting OS X 10.9 Mavericks through modern macOS). Runs on both Python 2.7.x and Python 3.x.

#### 📁 Directory Tree:
* **`main.py`** — Main application file, initializes the Tkinter root loop.
* **`build_app.sh`** — Builds a `.app` bundle structure, writes a dynamic Python version picker script as the entry executable (`Contents/MacOS/Syncrosa`), and packages the app as `Syncrosa_Python_Legacy.zip` on the Desktop.
* **`core/`**
  * `config.py` — Load and save logic settings (`~/.syncrosa.json`).
  * `localization.py` — Dict localization strings (i18n wrapper `_()`).
  * `itunes_bridge.py` — Executes `osascript` AppleScript tasks to interface with iTunes/Music.
  * `network.py` — Dual Python 2/3 compatible HTTPS client (using `urllib2` / `urllib.request` / `curl` fallback with cert package `cacert.pem`).
* **`features/`** (Processors)
  * `ai_playlist.py` — Formatting prompt structure and parsing response playlists.
  * `media_fixer.py` — Processing split items and querying iTunes search API.
  * `covers_optimizer.py` — Extracting artwork, resizing via `Pillow` (lazy dependency), backup/restore actions.
* **`ui/`** (Components & Windows)
  * `components.py` — Common widgets (like a modal progress dialog).
  * `settings.py` — API configuration and provider setups.
  * **`tabs/`**
    * `tab_genius.py` — View panel for generating playlists.
    * `tab_fixer.py` — View panel for merging albums and updating metadata tags.
    * `tab_optimizer.py` — View panel for Covers Optimizer.

#### 🔀 Routing:
* Managed in **`main.py`** inside the `App` class using a tabbed notebook container (**`ttk.Notebook`**):
  * *Tab 1: Genius* -> `GeniusTab` (`ui/tabs/tab_genius.py`)
  * *Tab 2: Media Fixer* -> `FixerTab` (`ui/tabs/tab_fixer.py`)
  * *Tab 3: Covers Optimizer* -> `OptimizerTab` (`ui/tabs/tab_optimizer.py`)
  * *Settings Window* -> Launches a separate modal dialog `SetupWindow` (`ui/settings.py`).

---

## 📦 Packaging and Distribution Rules
When running the build scripts (`build_arm.sh`, `build_legacy.sh`, `build_app.sh`):
1. **App Folder Name**: The compiled application bundle MUST be named exactly **`Syncrosa.app`**. No version suffixes should exist inside the bundle names (e.g. do not compile as `Syncrosa 2.app` or `Syncrosa v3.1.0.app`).
2. **Local Cleanup**: All build scripts must clean up their local `.app` bundles once packaged to prevent collisions and git clutter.
3. **ZIP Outputs**: The final distribution zip archives are written directly to `~/Desktop/` and named:
   * SwiftUI Version -> `Syncrosa_SwiftUI_ARM.zip`
   * Obj-C Legacy Version -> `Syncrosa_Cocoa_Legacy.zip`
   * Python Legacy Version -> `Syncrosa_Python_Legacy.zip`
