# -*- coding: utf-8 -*-
from __future__ import absolute_import
try:
    import Tkinter as tk
    import ttk
except ImportError:
    import tkinter as tk
    from tkinter import ttk
import threading

from core.itunes_bridge import run_as, get_library_track_count
from core.operation_history import record_operation


class LibraryDoctorTab(tk.Frame):
    def __init__(self, parent, master_app):
        tk.Frame.__init__(self, parent, bg="#ECECEC", borderwidth=0, highlightthickness=0)
        self.master_app = master_app
        self.running = False
        self.build_ui()

    def build_ui(self):
        tk.Label(self, text="Library Doctor", font=("system", 15, "bold"), bg="#ECECEC").pack(pady=(18, 8))
        self.tool_var = tk.StringVar(value="Cover Audit")
        self.tool = ttk.Combobox(self, textvariable=self.tool_var, values=["Cover Restore", "Cover Audit", "Library Audit"], state="readonly", width=24)
        self.tool.pack(pady=6)
        self.run_btn = ttk.Button(self, text="Run Doctor", command=self.run, width=20)
        self.run_btn.pack(pady=6)
        self.progress = ttk.Progressbar(self, mode="determinate")
        self.progress.pack(fill=tk.X, padx=30, pady=6)
        self.log_box = tk.Text(self, height=18, bg="#000000", fg="#00FF55", font=("Monaco", 10), state="disabled")
        self.log_box.pack(fill=tk.BOTH, expand=True, padx=24, pady=12)

    def clear_log(self):
        self.log_box.config(state="normal")
        self.log_box.delete("1.0", tk.END)
        self.log_box.config(state="disabled")

    def log(self, text):
        self.log_box.config(state="normal")
        self.log_box.insert(tk.END, "> " + text + "\n")
        self.log_box.see(tk.END)
        self.log_box.config(state="disabled")

    def run(self):
        if self.running:
            return
        self.running = True
        self.run_btn.config(state="disabled")
        self.progress.config(value=0, maximum=1)
        self.clear_log()
        threading.Thread(target=self.worker).start()

    def worker(self):
        tool = self.tool_var.get()
        status = "OK"
        message = ""
        affected = 0
        try:
            self.after(0, lambda: self.log("Library Doctor started: " + tool))
            if tool == "Cover Restore":
                message = "Open Covers Optimizer and use Restore Original Covers. The doctor keeps restore writes in that dedicated tool."
                self.after(0, lambda: self.log(message))
            elif tool == "Cover Audit":
                script = u'''
set coverCount to 0
set trackCount to 0
tell application "iTunes"
    try
        set trks to every track of library playlist 1
        set trackCount to count of trks
        repeat with t in trks
            try
                if (count of artworks of t) > 0 then set coverCount to coverCount + 1
            end try
        end repeat
    end try
end tell
return (trackCount as text) & tab & (coverCount as text)
'''
                raw = run_as(script, timeout_sec=240)
                message = "Cover audit raw result: " + raw
                affected = 1
                self.after(0, lambda m=message: self.log(m))
            else:
                count, err = get_library_track_count()
                if count >= 0:
                    message = "iTunes library track count: {}".format(count)
                    affected = count
                else:
                    status = "WARN"
                    message = "Could not read iTunes library. " + (err or "")
                self.after(0, lambda m=message: self.log(m))
        except Exception as e:
            status = "FAIL"
            message = str(e)
            self.after(0, lambda: self.log("ERROR: " + message))
        finally:
            record_operation("Library Doctor", tool, status, message, affected)
            self.after(0, lambda: self.progress.config(value=1, maximum=1))
            self.after(0, lambda: self.log("Library Doctor finished."))
            self.after(0, lambda: self.run_btn.config(state="normal"))
            self.running = False
