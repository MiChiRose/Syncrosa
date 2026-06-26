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
import threading
import os
from core.localization import _
from features.media_fixer import get_merge_candidates, apply_merge, run_metadata_fix

class FixerTab(tk.Frame):
    def __init__(self, parent, master_app):
        tk.Frame.__init__(self, parent, bg="#ECECEC", borderwidth=0, highlightthickness=0)
        self.master_app = master_app
        self.running = False
        self.build_ui()

    def build_ui(self):
        self.label = tk.Label(self, text="iTunes Media Info Fixer", font=("system", 14, "bold"), bg="#ECECEC")
        self.label.pack(pady=(20, 10))

        self.progress = ttk.Progressbar(self, orient="horizontal", length=400, mode="determinate")
        self.progress.pack(pady=5, padx=40)

        self.status = tk.Label(self, text="Ready to start", font=("system", 10), bg="#ECECEC", fg="#333333")
        self.status.pack(pady=5)
        
        console_frame = tk.Frame(self, bg="#ECECEC")
        console_frame.pack(padx=40, pady=10, fill=tk.BOTH, expand=True)
        
        self.console = tk.Text(console_frame, height=8, font=("system", 10), bg="#1E1E1E", fg="#00FF00", highlightthickness=0, state="disabled")
        self.console.pack(fill=tk.BOTH, expand=True)

        self.btn_frame = tk.Frame(self, bg="#ECECEC")
        self.btn_frame.pack(pady=15)

        self.start_btn = ttk.Button(self.btn_frame, text="Start Restoration", command=self.start_process, width=22)
        self.start_btn.pack(side=tk.LEFT, padx=10)

        self.stop_btn = ttk.Button(self.btn_frame, text="Stop", command=self.stop, state="disabled", width=10)
        self.stop_btn.pack(side=tk.LEFT, padx=10)

    def log(self, text):
        self.console.config(state="normal")
        self.console.insert("end", "> " + text + "\n")
        self.console.see("end")
        self.console.config(state="disabled")
        self.update_idletasks()

    def stop(self):
        self.running = False
        self.log("Stopping process safely...")
        self.stop_btn.config(state="disabled")

    def start_process(self):
        self.running = True
        self.start_btn.config(state="disabled")
        self.stop_btn.config(state="normal")
        self.progress["value"] = 0
        self.console.config(state="normal")
        self.console.delete("1.0", tk.END)
        self.console.config(state="disabled")
        
        threading.Thread(target=self.worker).start()

    def worker(self):
        try:
            # Phase 1: Merge
            self.after(0, lambda: self.label.config(text="Phase 1: Merging Duplicate Albums"))
            self.log("Starting Phase 1: Merge candidates search...")
            
            candidates = get_merge_candidates(None, lambda: self.running)
            if not self.running: return
            
            if candidates:
                self.log("Found %d album groups to merge." % len(candidates))
                apply_merge(
                    candidates, 
                    lambda c, t: self.after(0, lambda: self.progress.config(value=float(c)/t*100)),
                    self.log,
                    lambda: self.running
                )
            else:
                self.log("No duplicate albums found.")
            
            if not self.running: return
            
            # Phase 2: Metadata
            self.after(0, lambda: self.label.config(text="Phase 2: Updating Metadata"))
            self.log("Starting Phase 2: Fetching missing metadata from Apple...")
            
            run_metadata_fix(
                lambda c, t: self.after(0, lambda: self.progress.config(value=float(c)/t*100)),
                self.log,
                lambda: self.running
            )
            
            if self.running:
                self.log("Restoration complete!")
                self.after(0, lambda: self.label.config(text="Success! Library is Restored."))
                self.after(0, lambda: self.status.config(text="Everything is up to date."))
            else:
                self.log("Process stopped by user.")
                
        except Exception as e:
            self.log("ERROR: " + str(e))
            self.after(0, lambda: tkMessageBox.showerror("Fixer Error", str(e)))
        finally:
            self.running = False
            self.after(0, lambda: self.start_btn.config(state="normal"))
            self.after(0, lambda: self.stop_btn.config(state="disabled"))
