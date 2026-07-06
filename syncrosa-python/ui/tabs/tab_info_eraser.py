# -*- coding: utf-8 -*-
from __future__ import absolute_import
try:
    import Tkinter as tk
    import ttk
    import tkMessageBox
    import tkFileDialog
except ImportError:
    import tkinter as tk
    from tkinter import ttk
    from tkinter import messagebox as tkMessageBox
    from tkinter import filedialog as tkFileDialog
import threading

from features.info_eraser import backup_original_info, erase_info, find_music_files, restore_info

SUPPORTED_INFO_EXTENSIONS = (".mp3", ".m4a", ".mp4", ".aac", ".alac")


class InfoEraserTab(tk.Frame):
    def __init__(self, parent, master_app):
        tk.Frame.__init__(self, parent, bg="#ECECEC", borderwidth=0, highlightthickness=0)
        self.master_app = master_app
        self.folder_path = ""
        self.files = []
        self.running = False
        self.build_ui()

    def build_ui(self):
        header = tk.Frame(self, bg="#ECECEC")
        header.pack(pady=(14, 5))
        tk.Label(header, text="Info Eraser", font=("system", 14, "bold"), bg="#ECECEC").pack(side=tk.LEFT)
        ttk.Button(header, text="?", width=3, command=self.show_help).pack(side=tk.LEFT, padx=(8, 0))

        warning = tk.Frame(self, bg="#FDE7E7", highlightbackground="#B00020", highlightthickness=1)
        warning.pack(fill=tk.X, padx=24, pady=(8, 12))
        tk.Label(
            warning,
            text="WARNING: this tab permanently removes embedded song information and artwork from local files. Use only on a copied folder or after creating a backup.",
            font=("system", 11, "bold"),
            bg="#FDE7E7",
            fg="#8A0016",
            wraplength=520,
            justify=tk.CENTER
        ).pack(padx=12, pady=10)

        picker = tk.Frame(self, bg="#ECECEC")
        picker.pack(fill=tk.X, padx=24)
        self.path_var = tk.StringVar(value="No folder selected")
        self.path_entry = tk.Entry(picker, textvariable=self.path_var, state="readonly", font=("system", 12), readonlybackground="#FFFFFF")
        self.path_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 8))
        self.select_btn = ttk.Button(picker, text="Select Folder", command=self.select_folder, width=16)
        self.select_btn.pack(side=tk.LEFT)

        controls = tk.Frame(self, bg="#ECECEC")
        controls.pack(fill=tk.X, padx=24, pady=12)
        self.backup_btn = ttk.Button(controls, text="Backup Original Info", command=self.start_backup, state="disabled")
        self.backup_btn.pack(side=tk.LEFT, padx=(0, 8))
        self.erase_btn = ttk.Button(controls, text="Erase Info", command=self.confirm_erase, state="disabled")
        self.erase_btn.pack(side=tk.LEFT, padx=(0, 8))
        self.restore_btn = ttk.Button(controls, text="Restore Info", command=self.start_restore, state="disabled")
        self.restore_btn.pack(side=tk.LEFT)

        self.progress = ttk.Progressbar(self, mode="determinate")
        self.progress.pack(fill=tk.X, padx=24, pady=(2, 8))

        self.status = tk.Label(self, text="Select a folder to scan local music files.", font=("system", 10), bg="#ECECEC", fg="#555555")
        self.status.pack(pady=(0, 6))

        self.log_box = tk.Text(self, height=12, bg="#000000", fg="#00FF55", font=("Monaco", 10), state="disabled")
        self.log_box.pack(fill=tk.BOTH, expand=True, padx=24, pady=(0, 14))

    def set_busy(self, busy):
        self.running = busy
        state = "disabled" if busy else "normal"
        self.select_btn.config(state=state)
        enabled = (not busy and len(self.files) > 0)
        self.backup_btn.config(state="normal" if enabled else "disabled")
        self.erase_btn.config(state="normal" if enabled else "disabled")
        self.restore_btn.config(state="normal" if (not busy and self.folder_path) else "disabled")

    def log(self, text):
        self.log_box.config(state="normal")
        self.log_box.insert(tk.END, "> " + text + "\n")
        self.log_box.see(tk.END)
        self.log_box.config(state="disabled")

    def clear_log(self):
        self.log_box.config(state="normal")
        self.log_box.delete("1.0", tk.END)
        self.log_box.config(state="disabled")

    def show_help(self):
        tkMessageBox.showinfo(
            "Info Eraser",
            "Info Eraser works only with the selected local folder and its subfolders.\n\n"
            "Backup Original Info creates SyncrosaInfoEraserBackup with manifest.json and sidecar tag files.\n\n"
            "Erase Info removes MP3 ID3 tags and M4A/MP4/AAC/ALAC MP4 metadata atoms without transcoding audio.\n\n"
            "Restore Info can restore metadata only from a backup created before erasing."
        )

    def select_folder(self):
        folder = tkFileDialog.askdirectory()
        if not folder:
            return
        self.folder_path = folder
        self.path_var.set(folder)
        self.files = find_music_files(folder)
        supported_count = len([p for p in self.files if p.lower().endswith(SUPPORTED_INFO_EXTENSIONS)])
        self.progress.config(value=0, maximum=max(1, len(self.files)))
        self.clear_log()
        self.status.config(text="Found {} music files. Supported for erasing: {}.".format(len(self.files), supported_count))
        self.log("Scanned folder recursively: {} files, {} supported for erasing.".format(len(self.files), supported_count))
        self.set_busy(False)

    def _run_operation(self, title, worker):
        if not self.folder_path:
            tkMessageBox.showwarning("Info Eraser", "Please select a folder first.")
            return
        self.set_busy(True)
        self.progress.config(value=0, maximum=max(1, len(self.files)))
        self.status.config(text=title)
        self.clear_log()
        self.log(title)

        def progress(curr, total):
            self.after(0, lambda c=curr, t=total: self.progress.config(value=c, maximum=max(1, t)))

        def task():
            try:
                message = worker(progress)
                self.after(0, lambda m=message: self.log(m))
                self.after(0, lambda m=message: self.status.config(text=m))
            except Exception as e:
                self.after(0, lambda err=e: self.log("ERROR: " + str(err)))
                self.after(0, lambda err=e: tkMessageBox.showerror("Info Eraser", str(err)))
            finally:
                self.after(0, lambda: self.set_busy(False))

        threading.Thread(target=task).start()

    def start_backup(self):
        def worker(progress):
            manifest_path, supported = backup_original_info(self.folder_path, self.files, progress)
            return "Backup saved: {} ({} supported files).".format(manifest_path, supported)
        self._run_operation("Backing up original info...", worker)

    def confirm_erase(self):
        if not tkMessageBox.askyesno("Info Eraser", "Are you sure you want to permanently remove embedded info from supported files?"):
            return
        if not tkMessageBox.askyesno("Info Eraser", "Last warning: continue only if you have created a backup or are working on copies. Continue?"):
            return
        self.start_erase()

    def start_erase(self):
        def worker(progress):
            erased, unsupported = erase_info(self.files, progress)
            return "Erase finished. Stripped {} files. Unsupported/skipped: {}.".format(erased, unsupported)
        self._run_operation("Erasing embedded info...", worker)

    def start_restore(self):
        def worker(progress):
            restored, missing = restore_info(self.folder_path, progress)
            return "Restore finished. Restored {} files. Missing files: {}.".format(restored, missing)
        self._run_operation("Restoring original info...", worker)
