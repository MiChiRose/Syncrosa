# iTunesMediaInfoFix - Session Context

This file contains the context of the development session for the `iTunesMediaInfoFix` project. It is intended to be loaded back into the AI to resume work on the project.

## Project Goal
To create a native, zero-dependency macOS application to fix legacy iTunes libraries by merging duplicate albums and fetching missing metadata via the Apple iTunes Search API.

## Project Structure (Current State)
The project is organized in the `~/Desktop/iTunesMediaInfoFix_GitHub` directory.

### Versions
1.  **Main Version (10.7 - 10.13):**
    *   **Builder:** `build_app.sh`
    *   **Logic:** Uses Python 2.7, Tkinter for GUI, and AppleScript for iTunes integration.
    *   **Features:** Internet pre-flight check, Smart Merge (Python-based), Apple Search API metadata fetch, thick progress bar GUI, robust error logging to Desktop.
    *   **Compilation:** `osacompile` is used to create the bundle, and the Python scripts are embedded within the builder and copied to `Contents/Resources`.

2.  **Legacy Edition (10.4 - 10.6):**
    *   **Builder:** `build_legacy_app.sh`
    *   **Logic:** Uses pure AppleScript and Perl. No Python dependency to ensure compatibility with PowerPC (G4/G5) and older Intel Macs.
    *   **Features:** Offline Smart Merge only. Extracts library data, normalizes strings using Perl regex, finds the most common album name, and issues AppleScript commands to merge. Uses classic native dialogs.

### Assets
*   **Icon:** `folder-wood.icns` (Skeuomorphic design).
*   **Documentation:** `README.md` (Explaining both versions and setup).
*   **Outreach:** `Email_to_MavericksForever.txt` (Drafted email for promotion).

## Key Technical Decisions Made
*   **Avoided `osascript -e 'every track'` limits:** Bypassed the ~120 track export limit on Mavericks by iterating via index (`track i of library playlist 1`) or processing data streams directly.
*   **Monolithic App Bundle:** Chose to embed all scripts into the `.app` bundle rather than requiring them to sit alongside it. This ensures the user only deals with a single icon.
*   **Compilation Environment:** Decided that the app *must* be built on the target legacy OS (e.g., 10.9) to prevent `osacompile` from generating an incompatible binary format (like an ARM64/Intel universal binary that a 10.4 machine cannot read).
*   **Quarantine Bypass:** Included `xattr -cr` and `chmod +x` in the builders to prevent "Application is damaged" errors.

## Future Development Ideas / Next Steps
*   If we resume, we might want to test the Legacy Edition's Perl script specifically on a 10.4 emulator.
*   We could explore adding album artwork fetching for the Main version, provided the legacy `curl` can download images correctly.
*   We might need to adjust the `Tkinter` UI if it looks off on specific screen resolutions.

## How to Resume
Provide this file to the AI and say: "Please review the session context in this file and let's continue development from where we left off."