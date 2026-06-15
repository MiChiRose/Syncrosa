# iGeniusAI M-Series

This is a modern SwiftUI port of iGeniusAI, specifically designed for Apple Silicon (M1, M2, M3, etc.) and modern macOS versions using the **Music** app.

## Features
- **AI Playlist Generator**: Create playlists using natural language prompts via Google Gemini.
- **Media Fixer**: (In Progress) Normalize metadata and fix split albums using the iTunes Search API.
- **Native SwiftUI**: Fast, efficient, and fits perfectly into the modern macOS aesthetic.

## How to Run
1. Open the `Package.swift` file in Xcode.
2. Set your Google Gemini API Key in the **Settings** tab.
3. Start generating playlists!

## Architecture
- `Services/`: Core logic for API calls and Music app integration.
- `Views/`: SwiftUI components for the user interface.
- `Models/`: Data structures.

---
*Tailored for Apple Silicon.*
