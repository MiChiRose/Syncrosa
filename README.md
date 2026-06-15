# iGeniusAI 🎵🤖 (AI + Media Fixer)

<div align="center">
  <img src="genius.jpeg" alt="iGeniusAI Logo" width="120" />
  <p><b>The ultimate power-tool for managing and creating Apple Music & iTunes playlists using AI.</b></p>
  <p align="center">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-orange" alt="Swift / SwiftUI" />
  <img src="https://img.shields.io/badge/Python-legacy%20build-blue" alt="Python" />
  <img src="https://img.shields.io/badge/macOS-Sonoma%20to%20Mavericks-black" alt="macOS" />
  <img src="https://img.shields.io/badge/AI-Gemini%20%7C%20Groq%20%7C%20OpenRouter-brightgreen" alt="AI providers" />
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="license" />
</p>
</div>

Welcome to the central hub for the **iGeniusAI** ecosystem. This repository serves as the landing page and documentation hub for the project. 

The application is available in **two distinct versions**, tailored for different eras of Apple hardware.

---

## 🚀 The Applications

### 1. iGenius_ARM (Modern Apple Silicon)
A completely rewritten, native **SwiftUI** application designed exclusively for modern macOS (macOS 14 Sonoma and newer) running on Apple Silicon (M1/M2/M3/M4) chips.

- **Deep Music.app Integration:** Seamlessly interacts with the modern macOS Music application.
- **Native SwiftUI:** Fast, fluid, and beautiful interface with an iOS-style HUD notification system.
- **Advanced Security:** Uses macOS Keychain to securely store your API keys and employs Hardened Runtime for process safety. No plain-text secrets.
- **Multi-Provider AI:** Supports generating playlists via Gemini, Groq, and OpenRouter (bypassing geo-blocks).
- **iTunes Media Fixer:** Automatically corrects split albums and fetches missing metadata directly within your Music.app library.
- **Folder Fixer:** A powerful new tool to fix ID3 metadata for music files directly on your disk (MP3, FLAC, etc.) before importing them.
- **10+ Languages:** Fully localized out of the box (English, Russian, Belarusian, Korean, Japanese, Chinese, German, Polish, Estonian, Spanish).

### 2. iGeniusAI (Legacy Intel / OS X)
The legendary original Python-based application, meticulously designed for vintage Macs running OS X 10.9 Mavericks through 10.13 High Sierra.

- **Classic iTunes Support:** Interacts directly with the legacy iTunes application.
- **Retro Aesthetic:** Uses Tkinter to perfectly match the classic Aqua / El Capitan UI style.
- **Resilient Network Layer:** Features a custom network wrapper to bypass outdated OpenSSL 0.9.8 limitations on old Macs, connecting seamlessly to modern AI APIs.
- **Media Fixer:** Restores metadata for your classic MP3 libraries using the Apple iTunes Search API.

---

## ⚙️ Engineering Highlights
- **Resilient network layer** that bypasses outdated OpenSSL 0.9.8 on vintage macOS to reach modern AI APIs.
- **Secure by design** - API keys in macOS Keychain + Hardened Runtime (ARM build); no plain-text secrets.
- **Multi-provider AI** (Gemini / Groq / OpenRouter) with geo-block bypass.
- **Two native codebases, one product** - SwiftUI for Apple Silicon, Python/Tkinter for legacy Intel.
- **Lightweight** - native app, no Electron.

---

## 📥 How to Download & Run

You can find the compiled release versions in the [Releases](https://github.com/MiChiRose/iGeniusAI/releases) section of this repository.

### Running the Application (Important)
Because the application is distributed directly without an expensive Apple Developer Enterprise certificate (it uses ad-hoc signing), macOS Gatekeeper will block the first launch.

**To open the app for the first time:**
1. Download and extract the release archive.
2. **Right-click** (or Control-click) the application icon and select **"Open"**.
3. macOS will warn you about an unidentified developer. Click **"Open"** again in the warning dialog.
4. From then on, you can launch the app normally with a double-click!

---

## 🌟 Legacy App Features Guide

Below is a detailed guide on how to set up and use the legacy iGeniusAI application. 

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
 * **Error:** If validation fails, double-check your key, ensure the selected model is currently available, and check your internet connection. If issues persist, see the [Issues & Support](#-issues--support) section below.

5. **Error Logging:**
 * There is a checkbox labeled **"Prompt to save text logs..."**. I recommend keeping this enabled. If the app crashes or behaves unexpectedly, these logs help me (the developer) understand exactly what went wrong. You can send these logs to me for a quick fix!
 * <img width="751" height="564" alt="4th" src="https://github.com/user-attachments/assets/8de2b188-5ad0-4584-a5c1-b4b3064401a7" />


</details>

<details>
<summary><b>2. Generating Playlists (AI Genius Tab)</b></summary>

Using the application is designed to be simple and intuitive:

1. **Playlist Name:** Enter what you want your new iTunes playlist to be called (e.g., *"My Ultimate Drive"*).
2. **Mood / Vibe:** Describe what kind of music you want to hear. Be as specific as you like (e.g., *"Upbeat energetic 80s synth-pop for a workout"*).
3. **Track Count:** Choose how many songs should be in the playlist (default is 25). 
 * *Note: The AI will try to find as many matches as possible from your local library, but it might return fewer than requested if your library is small or the vibe is very niche.*
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

* **Modern Native Architecture (ARM Version):** The modern version is written entirely in native Swift and SwiftUI, providing a lightning-fast, compiled macOS application that integrates securely with the system.
* **Deep System Integration:** Both versions utilize advanced automation to seamlessly read your library and inject generated playlists directly into your Music or iTunes app.
* **Legacy Connectivity (Legacy Version):** The legacy Python version features a custom, highly resilient network layer designed to bypass expired SSL certificates on older systems, ensuring uninterrupted connections to modern AI APIs.
* **Lightweight Footprint:** Carefully optimized to run smoothly without draining system resources or relying on bloated modern web frameworks like Electron.

---

## ⚠️ Compatibility & Security

**Supported OS & Hardware:**
- **iGenius_ARM:** Requires **macOS 14 Sonoma or newer** and an Apple Silicon (**M1/M2/M3/M4**) processor.
- **iGeniusAI (Legacy):** Designed strictly for **OS X 10.9 Mavericks up to 10.13 High Sierra** on Intel Macs (2008-2013 era). Do not run or adapt this version for M-series Apple Silicon Macs.

**Security & Privacy:**
- **Local Storage Only:** Your API keys are stored only locally in `~/.itunes_genius_ai.json` (Legacy) or securely encrypted in the macOS Keychain (ARM).
- **No Data Collection:** The application does not collect, store, or distribute your API keys to any third-party server except the official AI provider.

## 💬 Issues & Support

If you encounter any bugs, have questions, or just want to suggest a cool feature, feel free to reach out! 

* **GitHub Issues:** The preferred way to report bugs or suggest improvements is by opening a ticket in the [Issues](../../issues) section of this repository.
* **Direct Contact:** You can also reach me via email at [yura.menschikov@icloud.com](mailto:yura.menschikov@icloud.com). Feel free to write — I'm always open to feedback!

---
*Created with ❤️ for both the modern Apple Silicon and retro Mac communities.*
