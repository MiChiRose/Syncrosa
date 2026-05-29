<div align="center">
  <img src="genius.jpeg" alt="iGeniusAI Logo" width="120" />
  <h1>iGeniusAI 🎵🤖</h1>
  <p><b>Bring the power of modern Artificial Intelligence to your legacy macOS and iTunes!</b></p>
</div>

<br/>

## 🌟 About The Project

**iGeniusAI** is a native macOS application designed specifically for older systems (OS X 10.9 Mavericks and newer). It bridges the gap between retro Apple hardware and cutting-edge LLMs (Large Language Models) by allowing you to generate perfectly curated iTunes playlists based on any mood, event, or genre you describe!

Forget manually picking tracks — just tell the AI what you want to hear, and it will magically construct a playlist from your existing iTunes library.

## ✨ Features

* **🍎 100% Native Feel:** Built with the classic OS X Aqua aesthetic in mind. No modern bloated frameworks, just a lightweight and fast native interface.
* **⚡️ Lightning Fast Library Caching:** Reads your iTunes library once and caches it in memory for instant subsequent generations.
* **🌍 Multi-Language Support:** Fully translated into 10 languages (English, Russian, Belarusian, Korean, Japanese, Chinese, German, Polish, Estonian, Spanish).
* **🧠 Free AI Integration:** Natively connects to Gemini, Groq, and OpenRouter APIs. Enjoy advanced models like Llama 3.3 70B, DeepSeek, and Gemini Pro for free!
* **🕵️ Transparent Processing:** A built-in terminal log shows you exactly what the AI is doing at every step, so you're never left guessing.

## 🚀 How to Use

1. **Download the App:** Go to the [Releases](../../releases) tab and download the latest version of `iGeniusAI`.
2. **Open the App:** Launch it on your Mac. You'll be greeted with the Setup window.
3. **Get an API Key:** 
   * We highly recommend using **OpenRouter** as it provides access to top-tier free models and bypasses geo-blocks. 
   * Register at [openrouter.ai](https://openrouter.ai), create a free API key, and paste it into the app.
4. **Sync Models:** Click the `🔄` button next to the model dropdown to fetch the latest free models.
5. **Generate:** Type in your desired playlist name and mood (e.g., *"Late night coding session"* or *"80s energetic pop"*), set the track count, and let the AI do the magic!

## 🧩 How It Works

1.  **Library Analysis:** The app quickly scans your iTunes library (via XML or AppleScript) to index your available music.
2.  **Contextual Prompting:** Your request (e.g., "Relaxing Jazz for a rainy day") is sent to the AI along with a structured list of your artists and tracks.
3.  **Smart Selection:** The AI processes your library and picks the tracks that best match the vibe you described.
4.  **Automated Creation:** iGeniusAI then instructs iTunes to create a new playlist and instantly populates it with the selected songs.

## 🛠 Technical Details

*   **Language:** Python (optimized for legacy environments).
*   **GUI:** Native Tkinter/ttk with a custom "Aqua-friendly" look.
*   **Core:** Built to be lightweight, with minimal dependencies to ensure it runs on systems as old as OS X 10.9 Mavericks.
*   **Connectivity:** Direct API integration with OpenRouter, Google Gemini, and Groq.

### ⚠️ Important Note on AI Models
Artificial Intelligence models are brilliant, but they are not perfect. Sometimes, an AI might misunderstand the strict JSON formatting rules required to build the playlist, which can result in a parsing error. 

**If you encounter an error:** Don't worry! Just open `Settings -> AI Settings...` and **try selecting a different model** from the dropdown list. Some models are much better at following strict formatting instructions than others.

## 🔐 Security & API Keys

Your privacy and security are paramount. Here is how your data is handled:

*   **Local Storage Only:** Your API keys are stored only within the application on your machine. They are used exclusively to authenticate requests to the AI providers (OpenRouter, Google, or Groq).
*   **No Data Collection:** I do not collect, store, or distribute your API keys. I simply have no use for them.
*   **Your Choice:** If you have concerns about the security of your digital keys, the safest approach is simply not to install or use the application. Transparency is a core value of this project.

## 💬 Issues & Support

If you encounter any bugs, have questions, or just want to suggest a cool feature, feel free to reach out! 

*   **GitHub Issues:** The preferred way to report bugs or suggest improvements is by opening a ticket in the [Issues](../../issues) section of this repository.
*   **Direct Contact:** You can also reach me via email at [yura.menschikov@icloud.com](mailto:yura.menschikov@icloud.com). Feel free to write — I'm always open to feedback!

---
*Created with ❤️ for the retro Mac community.*
