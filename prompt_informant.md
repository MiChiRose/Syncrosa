# 🚨 MANDATORY AI BEHAVIOR & GIT FLOW RULES

Every AI Coding Assistant reading this file MUST strictly adhere to the following workflow:

1. **Isolation of Tasks (Feature Branches):**
   * Never commit directly to the `main` branch.
   * All new features, refactoring, translations, or updates must be developed on a dedicated feature/fix branch (e.g., `feature/name` or `fix/issue`).
   
2. **Human-in-the-Loop (HITL) Validation:**
   * All changes must undergo local testing and verification.
   * A pull request or merge/push to `main` can ONLY be initiated after the user does manual testing and gives explicit, text-based approval (e.g., "approve", "push to main") in the chat.
   
3. **Parity Check:**
   * When implementing features or fixing bugs, verify if the change needs to be replicated in both `modern-swift` and `legacy-objc` tracks to maintain feature parity.

4. **Evaluating New Feature Requests (Feasibility Check Protocol):**
   * When the user asks: *"I have a new feature I want to apply, can we implement it? (или 'у меня есть новая фича которую я хочу применить, можем ли мы такое реализовать?')"*, the AI assistant MUST:
     1. Analyze the feature's requirements.
     2. Cross-reference the architecture mapping of all three versions (`syncrosa-swift`, `syncrosa-objc`, `syncrosa-python`).
     3. Identify which files need to be created, modified, or deleted in each target directory.
     4. Check for system API limitations (e.g. AppKit compatibility for macOS 10.13, SwiftUI compatibility for macOS 14+, Python 2.7 syntax restrictions, and SSL/TLS curl fallback constraints).
     5. Present a structured feasibility assessment: state if the feature is **Fully Feasible**, **Feasible with Workarounds (specify them)**, or **Infeasible**, and outline the planned changes for each codebase.

5. **Semantic Versioning Rule:**
   * Whenever a new feature, bugfix, or release is implemented, the version number of all three applications (`syncrosa-swift`, `syncrosa-objc`, `syncrosa-python`) MUST be updated in accordance with the rules of semantic versioning (Semantic Versioning). Keep the versions synchronized across all build files and Info.plists (e.g., `build_arm.sh`, `Info.plist`, `build_app.sh`).

---

# Syncrosa Project Guide & Prompt Informant 🎵🤖

This file serves as a comprehensive structural maps and context injector for AI coding assistants (like Antigravity) to immediately orient themselves within the Syncrosa project repository.

---

## 📌 Mapped Versions & Target Paths

The workspace contains three distinct application versions, each targetted at a specific architecture, OS range, and tech stack:

1. **Modern SwiftUI Version:**
   * **Directory:** [`/syncrosa-swift`](file:///Users/yuramac/Desktop/Syncrosa/syncrosa-swift)
   * **Target OS:** macOS 14.0 (Sonoma) or newer
   * **Architectures:** Apple Silicon (`arm64` natively)
   * **Current Version:** `3.0.0`
   * **Primary Host Integrations:** macOS system `Music.app`
   * **Development Stage:** Stable / Production

2. **Native Objective-C Version:**
   * **Directory:** [`/syncrosa-objc`](file:///Users/yuramac/Desktop/Syncrosa/syncrosa-objc)
   * **Target OS:** OS X 10.13 (High Sierra) or newer
   * **Architectures:** Universal Binary (`x86_64` + `arm64` compiled with backwards-compatible SDK)
   * **Current Version:** `3.0.0` (Beta)
   * **Primary Host Integrations:** Classic `iTunes`
   * **Development Stage:** Active Development / Beta

3. **Legacy Python Version:**
   * **Directory:** [`/syncrosa-python`](file:///Users/yuramac/Desktop/Syncrosa/syncrosa-python)
   * **Target OS:** OS X 10.9 (Mavericks) up to macOS 10.13 (High Sierra)
   * **Architectures:** Intel (`x86_64` running on system Python 2.7.x interpreter)
   * **Current Version:** `3.0.0`
   * **Primary Host Integrations:** Classic `iTunes`
   * **Development Stage:** Stable / Maintenance (Deprecated in favor of Legacy-ObjC)

---

## 📂 Codebase Architectures & File Maps

### 1. `syncrosa-swift` (Modern SwiftUI Edition)
* **Entrypoint:** `SyncrosaApp.swift` — initializes main App delegate and binds SwiftUI lifecycle.
* **Master Layout:** `ContentView.swift` — uses `NavigationSplitView` for left-sidebar pane switching.
* **Services Directory ([`/syncrosa-swift/Services`](file:///Users/yuramac/Desktop/Syncrosa/syncrosa-swift/Services)):**
  * `AIService.swift` — formats prompts, syncs free OpenRouter models, and validates credentials.
  * `MusicService.swift` — manages background queue communication with `Music.app` via AppleScript.
  * `USBService.swift` — detects removable volumes via FileManager and resolves metadata using `statfs`.
  * `PlaylistExportService.swift` — filters DRM (.m4p) tracks, validates free space, and runs chunked copying (1MB).
  * `KeychainHelper.swift` — encrypts and stores API credentials natively in the macOS Keychain.
  * `LocalizationService.swift` — dynamic i18n runtime translator (10 languages).
* **Views Directory ([`/syncrosa-swift/Views`](file:///Users/yuramac/Desktop/Syncrosa/syncrosa-swift/Views)):**
  * `PlaylistGeneratorView.swift` — AI playlist prompt editor.
  * `MediaFixerView.swift` — library consolidator (split albums fixer).
  * `FileMediaFixerView.swift` — disk folder cleaner and metadata rebuilder.
  * `USBExportView.swift` — playlist transfer control panel.
  * `SettingsView.swift` — configuration menu (API keys, models, language selector).

---

### 2. `syncrosa-objc` (Native Cocoa Edition)
* **Entrypoint:** `main.m` -> `AppDelegate.m` — bootstraps standard Cocoa NSApplication lifecycle.
* **Master Layout:** `IGMainWindowController.m` — programmatically creates `NSSplitView` sidebar structure (compatible down to OS X 10.9).
* **Services Directory ([`/syncrosa-objc/Sources/Services`](file:///Users/yuramac/Desktop/Syncrosa/syncrosa-objc/Sources/Services)):**
  * `IGAIService.h/.m` — handles NSURLSession calls with manual SSL trust verification and fallback to system `curl` via `NSTask` for outdated TLS layers.
  * `IGiTunesService.h/.m` — executes in-process AppleScript commands against `iTunes`.
  * `IGUSBService.h/.m` — runs asynchronous disk discovery routines.
  * `IGMediaFixerManager.h/.m` — consolidates tracks and retrieves metadata from the iTunes Search API.
  * `IGKeychainHelper.h/.m` — calls native Keychain APIs.
  * `IGLocalizationService.h/.m` — dynamic lookup class for translations.
* **UI Panels Directory ([`/syncrosa-objc/Sources/UI`](file:///Users/yuramac/Desktop/Syncrosa/syncrosa-objc/Sources/UI)):**
  * `IGGeniusViewController.m` — prompts interface with input counters (30 chars for Name, 150 for Prompt) and stepper.
  * `IGFixerViewController.m` — consolidator log view.
  * `IGFileFixerViewController.m` — file scanner utilizing `AVAsset` to rename files and download covers.
  * `IGUSBExportViewController.m` — manual refresh panels for copying music files to removable flash drives.
  * `IGSettingsViewController.m` — settings control with secure password fields and Keychain integration.

---

### 3. `syncrosa-python` (Original Python Edition)
* **Entrypoint:** `main.py` — starts Tkinter app loop and initializes tabs.
* **Logic Core:** `app_logic.py` — original procedural/monolithic logic sheet.
* **Core Folder ([`/syncrosa-python/core`](file:///Users/yuramac/Desktop/Syncrosa/syncrosa-python/core)):**
  * `network.py` — urllib2 networking wrapper with SSL/TLS bypasses (injecting custom `cacert.pem` and parsing curl stdout if SSL fails).
  * `config.py` — manages local configurations stored inside `~/.syncrosa.json`.
  * `itunes_bridge.py` — runs osascript commands via shell subprocesses.
* **UI Tabs ([`/syncrosa-python/ui/tabs`](file:///Users/yuramac/Desktop/Syncrosa/syncrosa-python/ui/tabs)):**
  * `tab_genius.py` — prompt-based layout with proportional library chunking to bypass Gemini token constraints.
  * `tab_fixer.py` — traditional listbox view showing split album groups.

---

## 🛠 Compilation & Build Commands

Always run build commands from the root directory of the respective version:

* **Swift ARM Version:**
  * Script: [`./build_arm.sh`](file:///Users/yuramac/Desktop/Syncrosa/syncrosa-swift/build_arm.sh)
  * Output bundle: `/syncrosa-swift/Syncrosa.app`
* **Objective-C Legacy Version:**
  * Compilation project synchronizer: [`python3 update_project.py`](file:///Users/yuramac/Desktop/Syncrosa/syncrosa-objc/update_project.py)
  * Script: [`./build_legacy.sh`](file:///Users/yuramac/Desktop/Syncrosa/syncrosa-objc/build_legacy.sh)
  * Output bundle: `/syncrosa-objc/build/Debug/Syncrosa.app`
* **Python Legacy Version:**
  * Script: [`./build_app.sh`](file:///Users/yuramac/Desktop/Syncrosa/syncrosa-python/build_app.sh)
  * Dependency: Requires `py2app` and OS X system Python 2.7.x interpreter.
  * Output bundle: `~/Desktop/Syncrosa.app`

---

## ⚠️ Networking & SSL Trust Bypasses (Critical Legacy Knowledge)

Old versions of OS X (10.9–10.11) contain outdated root certificates and older OpenSSL versions (like OpenSSL 0.9.8) that cannot natively negotiate TLS 1.2 or TLS 1.3 handshakes against modern AI API endpoints (Google, OpenRouter).
* **Python Edition Bypass:** Intercepts urllib2 URL open errors. If it catches an SSL handshake error, it dumps the API request details to a temporary file and triggers the system `/usr/bin/curl` via subprocess.
* **Objective-C Edition Bypass:** Utilizes `NSURLSessionDelegate` configuration to manually accept connections to AI API hosts. If the networking session fails, it falls back to spawning `/usr/bin/curl` using `NSTask` and `NSPipe`, retrieving response bodies dynamically.
* *Do not touch or refactor these network bridges without preserving the curl fallback mechanisms, as doing so will break the application on OS X 10.9.*
