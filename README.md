# iGeniusAI 🎵🤖 (AI + Media Fixer)

<div align="center">
  <img src="genius.jpeg" alt="iGeniusAI Logo" width="120" />
  <p><b>The ultimate power-tool for legacy iTunes libraries on OS X 10.9 – 10.13.</b></p>
</div>

iGeniusAI is a unified native application that brings modern LLM capabilities and advanced library restoration tools to vintage Macs. It combines the AI playlist generation power of **iGeniusAI** with the library organization excellence of **iTunesMediaInfoFix**.

---

## 🌟 Key Features

### 1. 🧠 AI Genius (Tab 1)
- **AI-Powered Playlists:** Generate perfect playlists based on moods, themes, or events (e.g., *"90s Underground Techno"* or *"Relaxing evening by the fireplace"*).
- **Multi-Provider Support:** Integration with Google Gemini, Groq, and OpenRouter (perfect for bypassing geo-blocks).
- **Native Integration:** Direct injection of generated tracks into your iTunes library via AppleScript.

### 2. 🛠 Media Fixer (Tab 2)
- **Smart Album Merge:** Automatically unifies split albums (e.g., *"Artist - Hits"* and *"Artist: Hits"*) into a single clean entity by normalizing metadata.
- **Apple Metadata Restoration:** Automatically fetches missing Year, Genre, and official Album info via the Apple iTunes Search API.
- **Library Analysis:** Pre-flight check to identify tracks with missing information.
- **Legacy Integration:** This feature is powered by the logic from the [iTunesMediaInfoFix](https://github.com/MiChiRose/iTunesMediaInfoFix) project, now fully integrated and improved for iGeniusAI.

### 3. 🌍 General Features
- **🍎 100% Native Feel:** Built with the classic OS X Aqua aesthetic. No modern bloated frameworks, just a lightweight and fast interface.
- **⚡️ Lightning Fast Library Caching:** Reads your iTunes library once and caches it for instant subsequent generations.
- **🛡️ Resilient SSL:** Integrated workaround for outdated system OpenSSL 0.9.8, ensuring stable cloud connections on Mavericks/Yosemite.
- **🌐 10+ Languages:** Fully localized for English, Russian, Belarusian, Korean, Japanese, Chinese, German, Polish, Estonian, and Spanish.

---

## 📖 User Guide

Below is a detailed guide on how to set up and use iGeniusAI. 

<details>
<summary><b>1. Initial Setup & AI Configuration (First Launch)</b></summary>

When you open the application for the first time, you will be greeted by the **AI Provider Setup** window. Follow these steps:

1.  **Choose your AI Provider:**
    *   **OpenRouter (Recommended):** Best for users in regions where direct access to AI models might be restricted. It provides a stable gateway to many free models.
    *   **Google Gemini / Groq:** Select these if you already have a direct subscription or API access to these services.
    *   <img width="748" height="562" alt="1st" src="https://github.com/user-attachments/assets/135f907b-ed5b-4d17-b12b-c598c816d19b" />


2.  **Select an AI Model:**
    *   **Author's Recommendation:** I personally suggest finding and selecting **`z-ai/glm-4.5-air:free`** (or its newer versions) in the list.
    *   **Can't find the model?** Click the **Sync (🔄)** button to update the list from the server.
    *   **Note:** Different models provide different results. Some might be more "creative," while others are more strictly focused on data. If one doesn't work, don't hesitate to try another!
    *   <img width="750" height="560" alt="2nd" src="https://github.com/user-attachments/assets/67f51df9-f4e7-41e4-9e3f-0944ddec0226" />


3.  **Get your API Key:**
    *   Click the **Question Mark (?)** icon in the bottom corner of the setup window. This will open a helpful guide explaining exactly how to obtain your own free API key for each provider.
    *   


4.  **Validate & Save:**
    *   Paste your key into the input field and click **"Validate & Save Key"**.
    *   **Success:** You will see a *"Success! Welcome"* message, and the window will close.
    *   **Error:** If validation fails, double-check your key, ensure the selected model is currently available, and check your internet connection. If issues persist, see the [Issues & Support](#-issues--support) section below.

5.  **Error Logging:**
    *   There is a checkbox labeled **"Prompt to save text logs..."**. I recommend keeping this enabled. If the app crashes or behaves unexpectedly, these logs help me (the developer) understand exactly what went wrong. You can send these logs to me for a quick fix!
    *   <img width="751" height="564" alt="4th" src="https://github.com/user-attachments/assets/8de2b188-5ad0-4584-a5c1-b4b3064401a7" />


</details>

<details>
<summary><b>2. Generating Playlists (AI Genius Tab)</b></summary>

Using the application is designed to be simple and intuitive:

1.  **Playlist Name:** Enter what you want your new iTunes playlist to be called (e.g., *"My Ultimate Drive"*).
2.  **Mood / Vibe:** Describe what kind of music you want to hear. Be as specific as you like (e.g., *"Upbeat energetic 80s synth-pop for a workout"*).
3.  **Track Count:** Choose how many songs should be in the playlist (default is 25). 
    *   *Note: The AI will try to find as many matches as possible from your local library, but it might return fewer than requested if your library is small or the vibe is very niche.*
4.  **Generate:** Click **"GENERATE PLAYLIST"** and wait a moment.
    *   <img width="601" height="572" alt="5th" src="https://github.com/user-attachments/assets/fbd8ba59-c213-4c24-8bf4-2645d600193f" />

5.  **Troubleshooting:** If the AI finds zero songs, try slightly changing your mood description or switching to a different AI model in the settings.

</details>

<details>
<summary><b>3. Cleaning your Library (Media Fixer Tab)</b></summary>

The **Media Fixer** tab helps keep your library organized:

1.  **Start Restoration:** Click this button to begin a two-phase process.
2.  **Phase 1 (Smart Merge):** The app looks for albums that were split apart (e.g., *"Artist - Hits"* vs *"Artist: Hits"*) and merges them into one.
3.  **Phase 2 (Metadata Fetch):** The app connects to the Apple iTunes API to find and fill in missing Years, Genres, and Track info.
4.  **Monitoring:** You can watch the real-time log console to see exactly which tracks are being processed.
    *   <img width="602" height="574" alt="6th" src="https://github.com/user-attachments/assets/f5beb973-3e5f-4ebb-a237-e65b58c83c77" />


</details>

---

## 🛠 Technical Details

*   **Language:** Python 2.7 (optimized for legacy environments).
*   **GUI:** Native Tkinter/ttk with a modular architecture.
*   **Connectivity:** Shared SSL/TLS workaround layer for `urllib2` and `curl`.
*   **Automation:** Extensive use of AppleScript (osascript) for deep iTunes integration.

---

## ⚠️ Compatibility & Security

- **Supported OS:** OS X 10.9 Mavericks up to 10.13 High Sierra.
- **Hardware:** Intel Macs (2008-2013 era). 
- **BANNED:** Do not run or adapt this for M-series Apple Silicon Macs. This project is dedicated to legacy hardware.
- **Privacy:** Your API keys are stored only locally in `~/.itunes_genius_ai.json` and are used exclusively to authenticate requests to your chosen AI provider.

## 🔐 Security & API Keys

Your privacy and security are paramount. Here is how your data is handled:

*   **Local Storage Only:** Your API keys are stored only within the application on your machine (`~/.itunes_genius_ai.json`). 
*   **No Data Collection:** The application does not collect, store, or distribute your API keys to any third-party server except the official AI provider.

## 💬 Issues & Support

If you encounter any bugs, have questions, or just want to suggest a cool feature, feel free to reach out! 

*   **GitHub Issues:** The preferred way to report bugs or suggest improvements is by opening a ticket in the [Issues](../../issues) section of this repository.
*   **Direct Contact:** You can also reach me via email at [yura.menschikov@icloud.com](mailto:yura.menschikov@icloud.com). Feel free to write — I'm always open to feedback!

---
*Created with ❤️ for the retro Mac community.*
