# Syncrosa: Comparison of the Three Versions ⚖️🎵

This document outlines the architectural, aesthetic, and functional differences between the three distinct editions of **Syncrosa**.

---

## 📊 Summary Feature Grid

| Feature | `syncrosa-swift` (Modern) | `syncrosa-objc` (Native) | `syncrosa-python` (Python) |
| :--- | :--- | :--- | :--- |
| **Tech Stack** | Swift / SwiftUI | Objective-C / AppKit (Cocoa) | Python 2.7 / Tkinter |
| **Target OS** | macOS 14.0+ (Sonoma to Sequoia) | OS X 10.13 or newer | OS X 10.9 - macOS 10.13 |
| **Processors** | Apple Silicon (M1-M5) | Intel (2008-2013) / Apple Silicon | Intel (2008-2013) |
| **Host Music App** | macOS `Music.app` | Classic `iTunes` | Classic `iTunes` |
| **Host Bridge** | AppleScript (via Combine) | AppleScript (in-process) | AppleScript (via subprocess) |
| **Keychain Integration**| Yes (System Keychain) | Yes (System Keychain) | No (Plain JSON file) |
| **Library Capacity** | Shuffled sampling (up to 500) | Shuffled sampling (up to 500) | Proportional chunking (unlimited) |
| **Media Fixer** | Normalization (WIP) | Normalization + iTunes API | Normalization |
| **Folder Fixer** | Yes (AVFoundation + covers) | Yes (AVFoundation + covers) | No |
| **USB Export Tab** | Yes (fitAvailable + size limit) | Yes (fitAvailable + size limit) | No |
| **Languages** | 10 Languages (runtime change) | 10 Languages (runtime change) | 10 Languages (restart required) |
| **Binary Overhead** | 0% (compiled native Swift) | 0% (compiled native Obj-C) | High (requires Python interpreter) |
| **Development Stage** | Stable Release (`3.0.0`) | Active Beta (`3.0.0`) | Legacy Stable (`3.0.0`) |

---

## 🎨 Design & Aesthetic Differences

### 1. `syncrosa-swift` (Modern SwiftUI Edition)
* **Aesthetic:** Translucent, modern, and fluid design that integrates natively with current macOS Sonoma/Sequoia system interfaces.
* **Layout:** Employs a modern double-pane layout (`NavigationSplitView`) with a clean sidebar on the left.
* **Interactions:** Built-in macOS system buttons, smooth scroll views, and dynamic resizing.
* **HUD Notifications:** Uses custom overlays with animated transitions to report real-time progress.

### 2. `syncrosa-objc` (Legacy Native Edition)
* **Aesthetic:** Classic Aqua interface compiled directly with AppKit. Matches Yosemite/El Capitan aesthetics perfectly.
* **Layout:** Uses a custom programmatic `NSSplitView` for the left sidebar navigation, eliminating bulky Interface Builder layout files.
* **Interactions:** Standard native buttons and secure input fields that feel snappy and look cohesive on older systems.
* **HUD Notifications:** Renders custom overlay subviews with high-contrast text and borders designed to run cleanly on OS X 10.13.

### 3. `syncrosa-python` (Legacy Python Edition)
* **Aesthetic:** Traditional Tkinter Aqua-theme. Layout elements are slightly more rigid due to Tk widget constraints.
* **Layout:** Uses tabbed folders (`ttk.Notebook`) on top of the main window for view switching.
* **Interactions:** Classic listboxes, drop-down menus, and text fields. Includes a terminal log widget at the bottom showing command-line output.

---

## 🧠 AI Capabilities & Constraints

* **OpenRouter Synchronization:** All three versions synchronize and fetch free models from OpenRouter, making them highly resilient against country blocks.
* **API Validation:** Both the SwiftUI and Objective-C versions execute key validation checks immediately during credential entry.
* **Token Protection (Large Libraries):**
  * **Swift & Objective-C:** Select a randomized, shuffled subset of up to 500 tracks from the library to feed into the AI context window, protecting the user from "Context Limit Exceeded" errors.
  * **Python Legacy:** Implements a proportional chunking mechanism that scans the entire library in pieces to send to the AI model.

---

## 🔒 Security & Key Management

* **`syncrosa-swift` & `syncrosa-objc`:** High-security profile. Credentials are saved directly into the secure macOS Keychain. The application relies on Hardened Runtime to ensure process integrity.
* **`syncrosa-python`:** Low-security profile. API keys are written in plaintext JSON format to `~/.syncrosa.json` in the user's home directory.

---

## ⚡ Performance & CPU Footprint

* **Objective-C (syncrosa-objc):** Outstanding. Direct memory allocation, compiled native code, and background Grand Central Dispatch (GCD) queues mean zero lag on legacy Intel Core 2 Duo and early Core i3/i5 processors. Instantly launches and closes.
* **SwiftUI (syncrosa-swift):** Excellent. Leverages compiler optimizations and Apple Silicon instruction sets. Extremely low power consumption.
* **Python (syncrosa-python):** Moderate. Requires loading a Python runtime interpreter at startup, leading to slower launch times and higher memory usage.
