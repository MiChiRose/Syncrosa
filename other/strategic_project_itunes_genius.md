# iGeniusAI: Strategic Project (Legacy macOS AI & Media Integration)

**Context:**
This project focuses on **iGeniusAI** (iTunesGeniusAIphoenix), a native macOS application that brings modern LLM capabilities and advanced library management to legacy systems (OS X 10.9+). It integrates AI-driven playlist generation with automated media metadata restoration using Python 2.7 and Tkinter.

**Objective:**
Merge `iTunesMediaInfoFix` into `iGeniusAI` to create a unified powerhouse tool for legacy iTunes users. The goal is to provide a seamless "All-in-One" experience while maintaining 100% compatibility with OS X 10.9 (Mavericks) through 10.13 (High Sierra).

---

## 👥 The Orchestration Team (Roles)

### 1. 🏗️ Team Lead (Architect)
*   **Focus:** Strategic roadmap, modular architecture, and project merger orchestration.
*   **Mandate:** Ensure architectural integrity. Oversee the transition from a monolithic script to a modular system. Validate that all decisions respect legacy constraints and M1/M2/M3 execution bans.

### 2. 🐍 Senior Python Developer (Legacy Specialist)
*   **Focus:** Core logic, API integrations, and iTunes AppleScript bridge for both AI and Media Fixer features.
*   **Mandate:** Implement the "Media Fixer" logic (Merging & Apple Metadata Fetch) into the unified codebase. Ensure thread safety and robust error handling in Python 2.7.

### 3. 🎨 UI/UX Designer (Aqua Aesthetic)
*   **Focus:** Unified Tkinter/ttk interface with `ttk.Notebook` (Tabs), multi-language support, and "Aqua" feel.
*   **Mandate:** Merge the UI of both projects into a single tabbed interface. Ensure consistent styling, padding, and native OS X look-and-feel across all modules.

### 4. 🧪 QA & Stability Engineer (Legacy Tester)
*   **Focus:** Stability verification, SSL compatibility, and build integrity for legacy environments.
*   **Mandate:** Ensure that merging the apps doesn't break existing iGeniusAI functionality. Validate the `build_app.sh` pipeline for the new unified application.

---

## 🛠 Project Information & Scope

*   **Scope:** Massive upgrade and merger of `iGeniusAI` and `iTunesMediaInfoFix`.
*   **Key Goals:** 
    *   **Unified Experience:** Two main tabs: [AI Playlist Generator] and [Media Info Fixer].
    *   **Modular Codebase:** Refactor `app_logic.py` into `core/`, `ui/`, and `features/`.
    *   **Legacy Perfection:** Strict adherence to Python 2.7 and system libraries found in OS X 10.9-10.13.
*   **Specific Merger Targets:**
    1. **Integration of Smart Merge:** Combine duplicate albums by normalizing metadata.
    2. **Apple Metadata Fetch:** Integrated UI for downloading Year/Genre/Track info via Apple API.
    3. **Shared Localization:** Extend the 10+ language support to the Media Fixer features.
    4. **Unified SSL Layer:** Shared workaround for outdated system OpenSSL across all network features.

---

## 🎯 Directives for Execution

### 1. Refactoring & Modularization
*   Split the current 1500-line `app_logic.py` into logical modules.
*   Create a shared `NetworkManager` for both AI API calls and Apple Metadata queries.
*   Create a shared `iTunesBridge` for all AppleScript interactions.

### 2. UI Integration Strategy
*   Implement `ttk.Notebook` as the primary navigation.
*   **Tab 1 (Genius):** The current AI playlist generator UI.
*   **Tab 2 (Media Fixer):** The ported UI from iTunesMediaInfoFix, adapted for the 600x550 window size.
*   **Tab 3 (Settings):** Unified settings for AI providers, Localization, and Library Sync.

### 3. Roadmap
*   **Phase 1: Foundation.** Create modular structure and port core "Media Fixer" logic.
*   **Phase 2: UI Merger.** Implement the Tabbed interface and integrate both feature sets.
*   **Phase 3: Stabilization.** Polish localization, fix threading issues, and optimize AppleScript calls.
*   **Phase 4: Build.** Finalize `build_app.sh` to package the new multi-feature `.app`.

---

## ⚠️ Critical Constraints
*   **COMPATIBILITY IS PARAMOUNT:** Must run on OS X 10.9+ with `/usr/bin/python` (2.7).
*   **NO M1/M2/M3 ADAPTATION:** Do not attempt to run or optimize for ARM-based Macs.
*   **No Modern Dependencies:** Stick to `Tkinter`, `urllib2`, `json`, `subprocess`, and other 2.7 stdlibs.
*   **Non-Destructive Integration:** Media Fixer features must not interfere with AI Generation and vice versa.
