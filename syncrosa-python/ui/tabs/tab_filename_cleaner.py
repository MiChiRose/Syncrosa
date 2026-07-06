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

from core.operation_history import record_operation


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
        self.clean_btn.config(state="normal" if self.files else "disabled")

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
