# Syncrosa 🎵🤖 (AI + Media Fixer)

<div align="center">
  <img src="genius.jpeg" alt="Syncrosa Logo" width="120" />
  <p><b>The ultimate power-tool for managing and creating Apple Music & iTunes playlists using AI.</b></p>
  <p align="center">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-orange" alt="Swift / SwiftUI" />
  <img src="https://img.shields.io/badge/Objective--C-Legacy%20Pro-blue" alt="Objective-C" />
  <img src="https://img.shields.io/badge/Python-Legacy%20Stable-blue" alt="Python" />
  <img src="https://img.shields.io/badge/macOS-Sonoma%20to%20Mavericks-black" alt="macOS" />
  <img src="https://img.shields.io/badge/AI-Gemini%20%7C%20Groq%20%7C%20OpenRouter-brightgreen" alt="AI providers" />
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="license" />
</p>
</div>

Welcome to the central hub for the **Syncrosa** ecosystem. This repository serves as the landing page and documentation hub for the project. 

The application is available in **three distinct versions**, tailored for different eras of Apple hardware.

---

## 🚀 The Applications

### 1. [syncrosa-swift](./syncrosa-swift) (Modern Apple Silicon)
A completely rewritten, native **SwiftUI** application designed exclusively for modern macOS (macOS 14 Sonoma and newer) running on Apple Silicon (M1/M2/M3/M4) chips.

- **Deep Music.app Integration:** Seamlessly interacts with the modern macOS Music application.
- **Modern UI:** Fast, fluid interface with a native iOS-style HUD notification system.
- **Advanced Security:** Uses macOS Keychain to securely store your API keys and employs Hardened Runtime for process safety.
- **Multi-Provider AI:** Supports generating playlists via Gemini, Groq, and OpenRouter (bypassing geo-blocks).
- **USB Export:** Transfer playlists directly to USB drives with format compatibility check and size optimization (.fitAvailable).
- **10+ Languages:** Fully localized out of the box.

### 2. [syncrosa-objc](./syncrosa-objc) (Native Legacy Cocoa)
A native, high-performance rewrite of the legacy track, built from the ground up using **Objective-C** and **Cocoa** for vintage Intel Macs running OS X 10.13 High Sierra and newer.

- **Classic iTunes Support:** Interacts directly with the legacy iTunes application.
- **Backwards-Compatible SDK:** Compiled to run natively on classic systems while maintaining modern parity.
- **Secure Keychain Storage:** Separate Keychain item storage for each AI provider.
- **Resilient Network Layer:** Spawns curl subprocesses when system openssl is too old to establish TLS 1.2+ handshakes.
- **USB Export Tab:** Native Cocoa control panel for copying files to USB drives.

### 3. [syncrosa-python](./syncrosa-python) (Legacy Python Track)
The original stable version designed for vintage Macs running OS X 10.9 Mavericks through 10.13 High Sierra using system Python 2.7.x interpreter.

- **Stable Python Core:** The current stable build ensures 100% compatibility with older OS X versions.
- **Classic iTunes Support:** Interacts directly with the legacy iTunes application.
- **Resilient Network Layer:** Bypasses outdated OpenSSL 0.9.8 limitations on old Macs.

---

## ⚙️ Engineering Highlights
- **Native Performance:** Zero-dependency compilation tracks for both Modern (SwiftUI) and Legacy (Objective-C) builds.
- **Resilient Connectivity:** Custom network layer to bypass expired SSL certificates on vintage macOS.
- **Security-First:** Native Keychain integration and Hardened Runtime for process protection.
- **Zero Bloat:** Native codebases only—no Electron, no web-wrappers, just raw performance.

---

## 📥 How to Download & Run

You can find the compiled release versions in the [Releases](https://github.com/MiChiRose/Syncrosa/releases) section of this repository.

### Running the Application (Important)
Because the application is distributed directly without an Apple Developer certificate (it uses ad-hoc signing), macOS Gatekeeper will block the first launch.

**To open the app for the first time:**
1. Download and extract the release archive.
2. **Right-click** (or Control-click) the application icon and select **"Open"**.
3. macOS will warn you about an unidentified developer. Click **"Open"** again in the warning dialog.
4. From then on, you can launch the app normally with a double-click!

---

## 🌟 Legacy App Features Guide

Below is a detailed guide on how to set up and use the legacy Syncrosa application. 

<details>
<summary><b>1. Initial Setup & AI Configuration (First Launch)</b></summary>

When you open the application for the first time, you will be greeted by the **AI Provider Setup** window. Follow these steps:

1. **Choose your AI Provider:**
 * **OpenRouter (Recommended):** Best for users in regions where direct access to AI models might be restricted. It provides a stable gateway to many free models.
 * **Google Gemini / Groq:** Select these if you already have a direct subscription or API access to these services.
 * <img width="748" height="562" alt="1st" src="https://github.com/user-attachments/assets/135f907b-ed5b-4d17-b12b-c598c816d19b" />


2. **Select an AI Model:**
 * **Author's Recommendation:** I personally suggest finding and selecting **`z-ai/glm-4.5-air:free`** (or its newer versions) in the list.
 * **Can't find the model?** Click the **Sync (🔄)** button to update the list from the server.
 * **Note:** Different models provide different results. Some might be more "creative," while others are more strictly focused on data. If one doesn't work, don't hesitate to try another!
 * <img width="750" height="560" alt="2nd" src="https://github.com/user-attachments/assets/67f51df9-f4e7-41e4-9e3f-0944ddec0226" />


3. **Get your API Key:**
 * Click the **Question Mark (?)** icon in the bottom corner of the setup window. This will open a helpful guide explaining exactly how to obtain your own free API key for each provider.
 * <img width="749" height="560" alt="3rd" src="https://github.com/user-attachments/assets/a4dda3af-2d64-429c-88d9-386396b31153" />



4. **Validate & Save:**
 * Paste your key into the input field and click **"Validate & Save Key"**.
 * **Success:** You will see a *"Success! Welcome"* message, and the window will close.
 * **Error:** If validation fails, double-check your key, ensure the selected model is currently available, and check your internet connection.

5. **Error Logging:**
 * There is a checkbox labeled **"Prompt to save text logs..."**. I recommend keeping this enabled. If the app crashes or behaves unexpectedly, these logs help me (the developer) understand exactly what went wrong.
 * <img width="751" height="564" alt="4th" src="https://github.com/user-attachments/assets/8de2b188-5ad0-4584-a5c1-b4b3064401a7" />


</details>

<details>
<summary><b>2. Generating Playlists (AI Genius Tab)</b></summary>

Using the application is designed to be simple and intuitive:

1. **Playlist Name:** Enter what you want your new iTunes playlist to be called (e.g., *"My Ultimate Drive"*).
2. **Mood / Vibe:** Describe what kind of music you want to hear. Be as specific as you like (e.g., *"Upbeat energetic 80s synth-pop for a workout"*).
3. **Track Count:** Choose how many songs should be in the playlist (default is 25). 
 * *Note: The AI will try to find as many matches as possible from your local library, but it might return fewer than requested if your library is small.*
4. **Generate:** Click **"GENERATE PLAYLIST"** and wait a moment.
 * <img width="601" height="572" alt="5th" src="https://github.com/user-attachments/assets/fbd8ba59-c213-4c24-8bf4-2645d600193f" />

5. **Troubleshooting:** If the AI finds zero songs, try slightly changing your mood description or switching to a different AI model in the settings.

</details>

<details>
<summary><b>3. Cleaning your Library (Media Fixer Tab)</b></summary>

The **Media Fixer** tab helps keep your library organized:

1. **Start Restoration:** Click this button to begin a two-phase process.
2. **Phase 1 (Smart Merge):** The app looks for albums that were split apart (e.g., *"Artist - Hits"* vs *"Artist: Hits"*) and merges them into one.
3. **Phase 2 (Metadata Fetch):** The app connects to the Apple iTunes API to find and fill in missing Years, Genres, and Track info.
4. **Monitoring:** You can watch the real-time log console to see exactly which tracks are being processed.
 * <img width="602" height="574" alt="6th" src="https://github.com/user-attachments/assets/f5beb973-3e5f-4ebb-a237-e65b58c83c77" />


</details>

---

## 🛠 Under the Hood

*   **The Evolution of Legacy:** Originally prototyped in **Python** for speed, the legacy track is now moving to a **Native Objective-C** core (syncrosa-objc). This transition eliminates the need for an external interpreter and brings true Cocoa-level responsiveness to older OS X platforms.
*   **Modern Architecture:** The modern version leverages **pure SwiftUI**, ensuring the app is power-efficient and fits perfectly into the modern macOS aesthetic while maintaining a lightning-fast compiled binary.
*   **Protocol Bridge:** We use custom automation and AppleScript bridges to ensure that regardless of the version (iTunes or Music.app), the AI-generated playlists are injected accurately and instantly.
*   **Network Resilience:** A custom socket-level wrapper and curl subprocess fallbacks are implemented in the legacy builds to bridge the gap between vintage OpenSSL versions and the strict security requirements of modern AI APIs.

---

## ⚠️ Compatibility & Security

**Supported OS & Hardware:**
- **syncrosa-swift:** Requires **macOS 14 Sonoma or newer** and an Apple Silicon (**M1/M2/M3/M4**) processor.
- **syncrosa-objc:** Designed strictly for **OS X 10.13 High Sierra** on Intel/Apple Silicon Macs (supports modern API Keychain separation and USB export).
- **syncrosa-python:** Designed strictly for **OS X 10.9 Mavericks up to 10.13 High Sierra** on Intel Macs (original stable build).

**Security & Privacy:**
- **Local Storage Only:** Your API keys are stored only locally in `~/.syncrosa.json` (Python Legacy) or securely encrypted in the macOS Keychain (Swift & Obj-C).
- **No Data Collection:** The application does not collect or distribute your private data.

## 💬 Issues & Support

If you encounter any bugs or have suggestions, reach out via:
* **GitHub Issues:** [Issues](../../issues) section.
* **Email:** [yura.menschikov@icloud.com](mailto:yura.menschikov@icloud.com)

---
*Created with ❤️ for both the modern Apple Silicon and retro Mac communities.*
