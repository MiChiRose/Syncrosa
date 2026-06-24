# iGeniusAI Project Guide & Prompt Informant 🎵🤖

This file serves as a comprehensive structural maps and context injector for AI coding assistants (like Antigravity) to immediately orient themselves within the iGeniusAI project repository.

---

## 📌 Mapped Versions & Target Paths

The workspace contains three distinct application versions, each targetted at a specific architecture, OS range, and tech stack:

1. **Modern SwiftUI Version:**
   * **Directory:** [`/iGeniusAI-arm`](file:///Users/yuramac/Desktop/iGeniusAI/iGeniusAI-arm)
   * **Target OS:** macOS 14.0 (Sonoma) or newer
   * **Architectures:** Apple Silicon (`arm64` natively)
   * **Current Version:** `1.3.0`
   * **Primary Host Integrations:** macOS system `Music.app`
   * **Development Stage:** Stable / Production

2. **Native Objective-C Version:**
   * **Directory:** [`/iGeniusAI-legacy-objc`](file:///Users/yuramac/Desktop/iGeniusAI/iGeniusAI-legacy-objc)
   * **Target OS:** OS X 10.9 (Mavericks) up to macOS 10.13 (High Sierra)
   * **Architectures:** Universal Binary (`x86_64` + `arm64` compiled with backwards-compatible SDK)
   * **Current Version:** `2.2.0` (Beta)
   * **Primary Host Integrations:** Classic `iTunes`
   * **Development Stage:** Active Development / Beta

3. **Legacy Python Version:**
   * **Directory:** [`/iGeniusAI-legacy`](file:///Users/yuramac/Desktop/iGeniusAI/iGeniusAI-legacy)
   * **Target OS:** OS X 10.9 (Mavericks) up to macOS 10.13 (High Sierra)
   * **Architectures:** Intel (`x86_64` running on system Python 2.7.x interpreter)
   * **Current Version:** `2.1.1`
   * **Primary Host Integrations:** Classic `iTunes`
   * **Development Stage:** Stable / Maintenance (Deprecated in favor of Legacy-ObjC)

---

## 📂 Codebase Architectures & File Maps

### 1. `iGeniusAI-arm` (Modern SwiftUI Edition)
* **Entrypoint:** `iGeniusAI-armApp.swift` — initializes main App delegate and binds SwiftUI lifecycle.
* **Master Layout:** `ContentView.swift` — uses `NavigationSplitView` for left-sidebar pane switching.
* **Services Directory ([`/iGeniusAI-arm/Services`](file:///Users/yuramac/Desktop/iGeniusAI/iGeniusAI-arm/Services)):**
  * `AIService.swift` — formats prompts, syncs free OpenRouter models, and validates credentials.
  * `MusicService.swift` — manages background queue communication with `Music.app` via AppleScript.
  * `USBService.swift` — detects removable volumes via FileManager and resolves metadata using `statfs`.
  * `PlaylistExportService.swift` — filters DRM (.m4p) tracks, validates free space, and runs chunked copying (1MB).
  * `KeychainHelper.swift` — encrypts and stores API credentials natively in the macOS Keychain.
  * `LocalizationService.swift` — dynamic i18n runtime translator (10 languages).
* **Views Directory ([`/iGeniusAI-arm/Views`](file:///Users/yuramac/Desktop/iGeniusAI/iGeniusAI-arm/Views)):**
  * `PlaylistGeneratorView.swift` — AI playlist prompt editor.
  * `MediaFixerView.swift` — library consolidator (split albums fixer).
  * `FileMediaFixerView.swift` — disk folder cleaner and metadata rebuilder.
  * `USBExportView.swift` — playlist transfer control panel.
  * `SettingsView.swift` — configuration menu (API keys, models, language selector).

---

### 2. `iGeniusAI-legacy-objc` (Native Cocoa Edition)
* **Entrypoint:** `main.m` -> `AppDelegate.m` — bootstraps standard Cocoa NSApplication lifecycle.
* **Master Layout:** `IGMainWindowController.m` — programmatically creates `NSSplitView` sidebar structure (compatible down to OS X 10.9).
* **Services Directory ([`/iGeniusAI-legacy-objc/Sources/Services`](file:///Users/yuramac/Desktop/iGeniusAI/iGeniusAI-legacy-objc/Sources/Services)):**
  * `IGAIService.h/.m` — handles NSURLSession calls with manual SSL trust verification and fallback to system `curl` via `NSTask` for outdated TLS layers.
  * `IGiTunesService.h/.m` — executes in-process AppleScript commands against `iTunes`.
  * `IGUSBService.h/.m` — runs asynchronous disk discovery routines.
  * `IGMediaFixerManager.h/.m` — consolidates tracks and retrieves metadata from the iTunes Search API.
  * `IGKeychainHelper.h/.m` — calls native Keychain APIs.
  * `IGLocalizationService.h/.m` — dynamic lookup class for translations.
* **UI Panels Directory ([`/iGeniusAI-legacy-objc/Sources/UI`](file:///Users/yuramac/Desktop/iGeniusAI/iGeniusAI-legacy-objc/Sources/UI)):**
  * `IGGeniusViewController.m` — prompts interface with input counters (30 chars for Name, 150 for Prompt) and stepper.
  * `IGFixerViewController.m` — consolidator log view.
  * `IGFileFixerViewController.m` — file scanner utilizing `AVAsset` to rename files and download covers.
  * `IGUSBExportViewController.m` — manual refresh panels for copying music files to removable flash drives.
  * `IGSettingsViewController.m` — settings control with secure password fields and Keychain integration.

---

### 3. `iGeniusAI-legacy` (Original Python Edition)
* **Entrypoint:** `main.py` — starts Tkinter app loop and initializes tabs.
* **Logic Core:** `app_logic.py` — original procedural/monolithic logic sheet.
* **Core Folder ([`/iGeniusAI-legacy/core`](file:///Users/yuramac/Desktop/iGeniusAI/iGeniusAI-legacy/core)):**
  * `network.py` — urllib2 networking wrapper with SSL/TLS bypasses (injecting custom `cacert.pem` and parsing curl stdout if SSL fails).
  * `config.py` — manages local configurations stored inside `~/.itunes_genius_ai.json`.
  * `itunes_bridge.py` — runs osascript commands via shell subprocesses.
* **UI Tabs ([`/iGeniusAI-legacy/ui/tabs`](file:///Users/yuramac/Desktop/iGeniusAI/iGeniusAI-legacy/ui/tabs)):**
  * `tab_genius.py` — prompt-based layout with proportional library chunking to bypass Gemini token constraints.
  * `tab_fixer.py` — traditional listbox view showing split album groups.

---

## 🛠 Compilation & Build Commands

Always run build commands from the root directory of the respective version:

* **Swift ARM Version:**
  * Script: [`./build_arm.sh`](file:///Users/yuramac/Desktop/iGeniusAI/iGeniusAI-arm/build_arm.sh)
  * Output bundle: `/iGeniusAI-arm/iGeniusAI-arm.app`
* **Objective-C Legacy Version:**
  * Compilation project synchronizer: [`python3 update_project.py`](file:///Users/yuramac/Desktop/iGeniusAI/iGeniusAI-legacy-objc/update_project.py)
  * Script: [`./build_legacy.sh`](file:///Users/yuramac/Desktop/iGeniusAI/iGeniusAI-legacy-objc/build_legacy.sh)
  * Output bundle: `/iGeniusAI-legacy-objc/build/Debug/iGeniusAI-legacy-objc.app`
* **Python Legacy Version:**
  * Script: [`./build_app.sh`](file:///Users/yuramac/Desktop/iGeniusAI/iGeniusAI-legacy/build_app.sh)
  * Dependency: Requires `py2app` and OS X system Python 2.7.x interpreter.
  * Output bundle: `~/Desktop/iGeniusAI.app`

---

## ⚠️ Networking & SSL Trust Bypasses (Critical Legacy Knowledge)

Old versions of OS X (10.9–10.11) contain outdated root certificates and older OpenSSL versions (like OpenSSL 0.9.8) that cannot natively negotiate TLS 1.2 or TLS 1.3 handshakes against modern AI API endpoints (Google, OpenRouter).
* **Python Edition Bypass:** Intercepts urllib2 URL open errors. If it catches an SSL handshake error, it dumps the API request details to a temporary file and triggers the system `/usr/bin/curl` via subprocess.
* **Objective-C Edition Bypass:** Utilizes `NSURLSessionDelegate` configuration to manually accept connections to AI API hosts. If the networking session fails, it falls back to spawning `/usr/bin/curl` using `NSTask` and `NSPipe`, retrieving response bodies dynamically.
* *Do not touch or refactor these network bridges without preserving the curl fallback mechanisms, as doing so will break the application on OS X 10.9.*
