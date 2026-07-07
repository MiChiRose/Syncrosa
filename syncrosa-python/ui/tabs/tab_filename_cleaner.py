# -*- coding: utf-8 -*-
from __future__ import absolute_import
try:
    import Tkinter as tk
    import ttk
    import tkFileDialog
    import tkMessageBox
except ImportError:
    import tkinter as tk
    from tkinter import ttk
    from tkinter import filedialog as tkFileDialog
    from tkinter import messagebox as tkMessageBox
import os
import threading
import json
import time

from core.operation_history import record_operation
from core.itunes_bridge import import_files_as_playlist


MUSIC_EXTENSIONS = (".mp3", ".m4a", ".mp4", ".aac", ".alac", ".flac", ".wav", ".aiff")


class FilenameCleanerTab(tk.Frame):
    def __init__(self, parent, master_app):
        tk.Frame.__init__(self, parent, bg="#ECECEC", borderwidth=0, highlightthickness=0)
        self.master_app = master_app
        self.folder = ""
        self.files = []
        self.running = False
        self.build_ui()

    def build_ui(self):
        tk.Label(self, text="Filename Cleaner", font=("system", 15, "bold"), bg="#ECECEC").pack(pady=(18, 8))
        picker = tk.Frame(self, bg="#ECECEC")
        picker.pack(fill=tk.X, padx=24, pady=6)
        self.path_var = tk.StringVar(value="No folder selected")
        tk.Entry(picker, textvariable=self.path_var, state="readonly", readonlybackground="#FFFFFF").pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 8))
        ttk.Button(picker, text="Select Folder", command=self.select_folder, width=16).pack(side=tk.LEFT)

        btns = tk.Frame(self, bg="#ECECEC")
        btns.pack(pady=8)
        self.clean_btn = ttk.Button(btns, text="Clean Filenames", command=self.clean, state="disabled", width=20)
        self.clean_btn.pack(side=tk.LEFT, padx=6)
        self.playlist_var = tk.StringVar(value="")
        self.playlist_var.trace("w", lambda *args: self._update_buttons())
        tk.Entry(btns, textvariable=self.playlist_var, width=22).pack(side=tk.LEFT, padx=6)
        self.import_btn = ttk.Button(btns, text="Create Playlist", command=self.create_playlist, state="disabled", width=18)
        self.import_btn.pack(side=tk.LEFT, padx=6)

        ai_btns = tk.Frame(self, bg="#ECECEC")
        ai_btns.pack(pady=2)
        self.export_json_btn = ttk.Button(ai_btns, text="Export AI JSON", command=self.export_ai_json, state="disabled", width=18)
        self.export_json_btn.pack(side=tk.LEFT, padx=6)
        self.import_json_btn = ttk.Button(ai_btns, text="Import AI JSON", command=self.import_ai_json, state="disabled", width=18)
        self.import_json_btn.pack(side=tk.LEFT, padx=6)
        self.progress = ttk.Progressbar(self, mode="determinate")
        self.progress.pack(fill=tk.X, padx=24, pady=6)
        self.status = tk.Label(self, text="Select a folder with music files.", font=("system", 10), bg="#ECECEC", fg="#555555")
        self.status.pack(pady=4)
        self.log_box = tk.Text(self, height=16, bg="#000000", fg="#00FF55", font=("Monaco", 10), state="disabled")
        self.log_box.pack(fill=tk.BOTH, expand=True, padx=24, pady=12)

    def select_folder(self):
        folder = tkFileDialog.askdirectory()
        if not folder:
            return
        self.folder = folder
        self.path_var.set(folder)
        self.files = []
        for root, dirs, files in os.walk(folder):
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            for name in files:
                if name.lower().endswith(MUSIC_EXTENSIONS):
                    self.files.append(os.path.join(root, name))
        self.progress.config(value=0, maximum=max(1, len(self.files)))
        self.clear_log()
        self.log("Scanned folder recursively: {} music files.".format(len(self.files)))
        self.status.config(text="Files found: {}".format(len(self.files)))
        self._update_buttons()

    def _update_buttons(self):
        has_files = bool(self.files) and not self.running
        has_playlist_name = bool(self.playlist_var.get().strip())
        self.clean_btn.config(state="normal" if has_files else "disabled")
        self.import_btn.config(state="normal" if has_files and has_playlist_name else "disabled")
        self.export_json_btn.config(state="normal" if has_files else "disabled")
        self.import_json_btn.config(state="normal" if has_files else "disabled")

    def _track_manifest(self, path):
        rel = os.path.relpath(path, self.folder) if self.folder else os.path.basename(path)
        size = os.path.getsize(path) if os.path.exists(path) else 0
        base, ext = os.path.splitext(os.path.basename(path))
        clean = " ".join(base.replace("_", " ").split())
        artist = ""
        title = clean
        if " - " in clean:
            parts = clean.split(" - ", 1)
            artist = parts[0].strip()
            title = parts[1].strip()
        return {
            "id": rel + "#" + str(size),
            "relativePath": rel,
            "fileName": os.path.basename(path),
            "artistHint": artist,
            "titleHint": title,
            "fileExtension": ext[1:].lower(),
            "fileSize": size
        }

    def export_ai_json(self):
        if not self.files:
            return
        path = tkFileDialog.asksaveasfilename(
            defaultextension=".json",
            filetypes=[("JSON", "*.json")],
            initialfile="Syncrosa-AI-Manifest.json"
        )
        if not path:
            return
        manifest = {
            "schema": "syncrosa-folder-playlist-manifest-v1",
            "app": "Syncrosa",
            "folderName": os.path.basename(self.folder),
            "instructions": "Return JSON like {\"playlistName\":\"Name\",\"trackIDs\":[\"id-from-this-file\"]}.",
            "tracks": [self._track_manifest(p) for p in self.files]
        }
        with open(path, "w") as f:
            json.dump(manifest, f, indent=2, sort_keys=True)
        self.clear_log()
        self.log("Exported AI manifest: " + path)

    def import_ai_json(self):
        if not self.files:
            return
        path = tkFileDialog.askopenfilename(filetypes=[("JSON", "*.json")])
        if not path:
            return
        try:
            with open(path, "r") as f:
                data = json.load(f)
        except Exception as e:
            tkMessageBox.showerror("AI JSON", str(e))
            return
        if data.get("playlistName") and not self.playlist_var.get().strip():
            self.playlist_var.set(data.get("playlistName"))
            self._update_buttons()
        keys = set()
        for field in ("trackIDs", "selectedTrackIDs", "relativePaths"):
            for value in data.get(field) or []:
                keys.add(value)
        for item in data.get("tracks") or []:
            if isinstance(item, dict):
                for field in ("id", "relativePath", "fileName"):
                    if item.get(field):
                        keys.add(item.get(field))
        manifests = [(p, self._track_manifest(p)) for p in self.files]
        selected = [p for p, m in manifests if m["id"] in keys or m["relativePath"] in keys or m["fileName"] in keys]
        if not selected:
            tkMessageBox.showerror("AI JSON", "JSON did not match any files in the selected folder.")
            return
        self.create_playlist(selected)

    def create_playlist(self, selected_files=None):
        if self.running:
            return
        files = selected_files or self.files
        name = self.playlist_var.get().strip()
        if not name:
            tkMessageBox.showerror("Folder Playlist", "Enter a playlist name first.")
            return
        importable = [p for p in files if os.path.splitext(p)[1].lower() in (".mp3", ".m4a", ".mp4", ".aac", ".wav", ".aiff", ".aif", ".alac")]
        skipped = len(files) - len(importable)
        total_size = sum([os.path.getsize(p) for p in importable if os.path.exists(p)])
        estimate = max(3, int(len(importable) * 0.6 + (total_size / 1048576.0) / 25.0))
        if not importable:
            tkMessageBox.showerror("Folder Playlist", "No supported files to import into iTunes.")
            return
        confirm_message = (
            "Create playlist '{}'?\\n"
            "Files: {}\\n"
            "Skipped: {}\\n"
            "Estimated time: ~{} sec\\n\\n"
            "If a playlist with this name already exists, Syncrosa will clear it first and replace it with these tracks."
        ).format(name, len(importable), skipped, estimate)
        if not tkMessageBox.askyesno("Folder Playlist", confirm_message):
            return
        self.running = True
        self.import_btn.config(state="disabled")
        self.clean_btn.config(state="disabled")
        self.export_json_btn.config(state="disabled")
        self.import_json_btn.config(state="disabled")
        self.progress.config(value=0, maximum=max(1, len(importable)))
        self.clear_log()
        self.log("Starting playlist import: " + name)
        threading.Thread(target=lambda: self.playlist_worker(name, importable, skipped)).start()

    def playlist_worker(self, name, paths, skipped):
        imported = 0
        try:
            batch_size = 12
            for start in range(0, len(paths), batch_size):
                batch = paths[start:start + batch_size]
                imported += import_files_as_playlist(name, batch, clear_playlist=(start == 0))
                self.after(0, lambda i=min(start + batch_size, len(paths)): self.progress.config(value=i))
                self.after(0, lambda s=start: self.log("Imported batch starting at {}".format(s + 1)))
                time.sleep(0.05)
            message = "Playlist '{}' ready. Added: {}. Skipped: {}.".format(name, imported, skipped)
            record_operation("Folder Playlist Importer", "Import Folder Playlist", "OK", message, imported)
        except Exception as e:
            message = "Folder playlist import failed: " + str(e)
            record_operation("Folder Playlist Importer", "Import Folder Playlist", "FAIL", message, imported)
        self.after(0, lambda m=message: self.status.config(text=m))
        self.after(0, lambda m=message: self.log(m))
        self.running = False
        self.after(0, self._update_buttons)

    def clear_log(self):
        self.log_box.config(state="normal")
        self.log_box.delete("1.0", tk.END)
        self.log_box.config(state="disabled")

    def log(self, text):
        self.log_box.config(state="normal")
        self.log_box.insert(tk.END, "> " + text + "\n")
        self.log_box.see(tk.END)
        self.log_box.config(state="disabled")

    def clean(self):
        if self.running or not self.files:
            return
        if not tkMessageBox.askyesno(
            "Filename Cleaner",
            "Syncrosa will rename files in this folder and subfolders. Continue?"
        ):
            return
        self.running = True
        self.clean_btn.config(state="disabled")
        self.progress.config(value=0, maximum=max(1, len(self.files)))
        self.clear_log()
        self.log("Starting filename cleaner...")
        threading.Thread(target=self.worker).start()

    def _clean_name(self, path):
        folder = os.path.dirname(path)
        name = os.path.basename(path)
        base, ext = os.path.splitext(name)
        if base.count("_") < 2 and "_-_" not in base and "__" not in base:
            return path
        clean = " ".join(base.replace("_", " ").split())
        if not clean or clean == base:
            return path
        desired = os.path.join(folder, clean + ext)
        candidate = desired
        suffix = 2
        while os.path.exists(candidate) and os.path.abspath(candidate).lower() != os.path.abspath(path).lower():
            candidate = os.path.join(folder, "{} {}{}".format(clean, suffix, ext))
            suffix += 1
        os.rename(path, candidate)
        return candidate

    def worker(self):
        renamed = 0
        failed = False
        updated = []
        try:
            for idx, path in enumerate(self.files, 1):
                if failed:
                    break
                self.after(0, lambda p=path: self.log("Checking: " + os.path.basename(p)))
                try:
                    new_path = self._clean_name(path)
                    if new_path != path:
                        renamed += 1
                    updated.append(new_path)
                    self.after(0, lambda p=new_path: self.log("OK: " + os.path.basename(p)))
                except Exception as e:
                    failed = True
                    self.after(0, lambda err=e: self.log("ERROR: " + str(err)))
                self.after(0, lambda i=idx: self.progress.config(value=i))
        finally:
            if failed:
                self.files = updated + self.files[len(updated):]
            else:
                self.files = updated
            status = "FAIL" if failed else "OK"
            message = "Filename Cleaner stopped after an error." if failed else "Filename Cleaner finished. Renamed: {}.".format(renamed)
            record_operation("Filename Cleaner", "Clean Filenames", status, message, renamed)
            self.after(0, lambda m=message: self.status.config(text=m))
            self.after(0, lambda m=message: self.log(m))
            self.after(0, lambda: self.clean_btn.config(state="normal" if self.files else "disabled"))
            self.running = False
