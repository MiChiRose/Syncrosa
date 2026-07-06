# -*- coding: utf-8 -*-
from __future__ import absolute_import
try:
    import Tkinter as tk
    import ttk
    import tkMessageBox
except ImportError:
    import tkinter as tk
    from tkinter import ttk
    from tkinter import messagebox as tkMessageBox

from core.config import CONFIG_DATA, save_config
from core.storage_paths import backups_dir, cache_dir
from core.operation_history import record_operation


class OverviewTab(tk.Frame):
    def __init__(self, parent, master_app):
        tk.Frame.__init__(self, parent, bg="#ECECEC", borderwidth=0, highlightthickness=0)
        self.master_app = master_app
        self.build_ui()

    def build_ui(self):
        tk.Label(self, text="Overview", font=("system", 15, "bold"), bg="#ECECEC").pack(pady=(25, 10))

        self.status = tk.Label(
            self,
            text=self._library_text(),
            font=("system", 12),
            bg="#ECECEC",
            fg="#444444",
            wraplength=520,
            justify=tk.CENTER
        )
        self.status.pack(pady=(0, 12))

        safety = (
            "Safeguards enabled:\n"
            "- iTunes tools are disabled when the library is confirmed empty.\n"
            "- Long scans are chunked and visible.\n"
            "- Backups live under Application Support / Syncrosa / Backups.\n"
            "- Only Local Mode skips online metadata and lyrics requests in fixers."
        )
        tk.Label(self, text=safety, font=("system", 11), bg="#ECECEC", fg="#555555", justify=tk.LEFT).pack(pady=(0, 16))

        btns = tk.Frame(self, bg="#ECECEC")
        btns.pack(pady=8)
        ttk.Button(btns, text="Refresh iTunes", command=self.refresh, width=18).pack(side=tk.LEFT, padx=6)
        ttk.Button(btns, text="First Launch Setup", command=self.show_wizard, width=20).pack(side=tk.LEFT, padx=6)
        ttk.Button(btns, text="Open Library Doctor", command=self.open_doctor, width=20).pack(side=tk.LEFT, padx=6)

        self.only_local_var = tk.BooleanVar(value=bool(CONFIG_DATA.get("only_local_mode", False)))
        tk.Checkbutton(
            self,
            text="Only Local Mode",
            variable=self.only_local_var,
            command=self.save_only_local,
            bg="#ECECEC",
            activebackground="#ECECEC",
            font=("system", 12)
        ).pack(pady=10)

        tk.Label(self, text="Backups: " + backups_dir(), font=("Monaco", 9), bg="#ECECEC", fg="#666666").pack(pady=(16, 2))
        tk.Label(self, text="Temp cache: " + cache_dir(), font=("Monaco", 9), bg="#ECECEC", fg="#666666").pack()

        if not CONFIG_DATA.get("has_seen_setup_wizard"):
            CONFIG_DATA["has_seen_setup_wizard"] = True
            save_config(CONFIG_DATA)
            self.after(500, self.show_wizard)

    def _library_text(self):
        count = getattr(self.master_app, "library_track_count", -1)
        if count == 0:
            return "iTunes library is empty. Library tools stay disabled until tracks are added."
        if count > 0:
            return "iTunes library: {} tracks.".format(count)
        return "iTunes library status is unknown. Click Refresh iTunes."

    def refresh(self):
        if hasattr(self.master_app, "refresh_library_status_async"):
            self.master_app.refresh_library_status_async()
            self.after(700, lambda: self.status.config(text=self._library_text()))

    def update_library_status(self):
        self.status.config(text=self._library_text())

    def save_only_local(self):
        CONFIG_DATA["only_local_mode"] = self.only_local_var.get()
        save_config(CONFIG_DATA)
        record_operation("Overview", "Only Local Mode", "OK", "Only Local Mode set to {}".format(CONFIG_DATA["only_local_mode"]))

    def show_wizard(self):
        tkMessageBox.showinfo(
            "Syncrosa First Launch Setup",
            "1. Allow iTunes automation if macOS asks.\n"
            "2. Refresh iTunes status before using library tools.\n"
            "3. Back up or copy folders before destructive local file operations.\n"
            "4. Enable Only Local Mode if you want to avoid online metadata lookups."
        )
        record_operation("Overview", "First Launch Setup", "OK", "First launch checklist was shown.")

    def open_doctor(self):
        if getattr(self.master_app, "library_track_count", -1) == 0:
            tkMessageBox.showwarning("Library Doctor", "iTunes library is empty. Add tracks, then refresh iTunes.")
            return
        try:
            self.master_app.notebook.select(self.master_app.tab_library_doctor)
        except Exception:
            pass
