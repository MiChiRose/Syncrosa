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
import time
from core.localization import _
from features.covers_optimizer import (
    get_tracks_with_covers,
    backup_cover,
    optimize_cover,
    restore_cover,
    HAS_PIL
)

class OptimizerTab(tk.Frame):
    def __init__(self, parent, master_app):
        tk.Frame.__init__(self, parent, bg="#ECECEC", borderwidth=0, highlightthickness=0)
        self.master_app = master_app
        self.running = False
        self.action = None
        self.build_ui()

    def build_ui(self):
        self.title_lbl = tk.Label(self, text=_(u"covers_optimizer"), font=("system", 14, "bold"), bg="#ECECEC")
        self.title_lbl.pack(pady=(15, 10))

        # Select Device Frame
        self.sel_frame = tk.Frame(self, bg="#ECECEC")
        self.sel_frame.pack(pady=5)
        
        self.select_lbl = tk.Label(self.sel_frame, text=_(u"select_device"), font=("system", 10), bg="#ECECEC")
        self.select_lbl.pack(side=tk.LEFT, padx=5)

        self.device_combo = ttk.Combobox(self.sel_frame, state="readonly", width=38)
        self.device_combo["values"] = (
            "iPod Classic / Vintage (300x300)",
            "iPhone 4s / 6 / iOS 5-6 (600x600)",
            "Modern iOS / High-Res (1000x1000)"
        )
        self.device_combo.current(0)
        self.device_combo.pack(side=tk.LEFT, padx=5)

        # Progressbar
        self.progress = ttk.Progressbar(self, orient="horizontal", length=450, mode="determinate")
        self.progress.pack(pady=10, padx=40)

        self.status = tk.Label(self, text="", font=("system", 10), bg="#ECECEC", fg="#333333")
        self.status.pack(pady=2)

        # Monospace Console Log View
        console_frame = tk.Frame(self, bg="#ECECEC")
        console_frame.pack(padx=40, pady=10, fill=tk.BOTH, expand=True)

        self.console = tk.Text(console_frame, height=8, font=("Courier", 10), bg="#1E1E1E", fg="#00FF00", highlightthickness=0, state="disabled")
        self.console.pack(fill=tk.BOTH, expand=True)

        if not HAS_PIL:
            self.log("WARNING: Pillow (PIL) library is not installed.")
            self.log("Cover optimization will not be functional.")
            self.log("Please install Pillow on your system to use it:")
            self.log("  pip3 install Pillow")
            self.log("------------------------------------------")

        # Action Buttons
        self.btn_frame = tk.Frame(self, bg="#ECECEC")
        self.btn_frame.pack(pady=15)

        self.backup_btn = ttk.Button(self.btn_frame, text=_(u"btn_backup_covers"), command=self.start_backup, width=18)
        self.backup_btn.pack(side=tk.LEFT, padx=5)

        self.optimize_btn = ttk.Button(self.btn_frame, text=_(u"btn_optimize_covers"), command=self.confirm_optimize, width=18)
        self.optimize_btn.pack(side=tk.LEFT, padx=5)

        self.restore_btn = ttk.Button(self.btn_frame, text=_(u"btn_restore_covers"), command=self.start_restore, width=18)
        self.restore_btn.pack(side=tk.LEFT, padx=5)

    def log(self, text):
        # Format with timestamp
        stamp = time.strftime("%H:%M:%S")
        line = "[{0}] {1}".format(stamp, text)
        
        self.console.config(state="normal")
        self.console.insert("end", line + "\n")
        self.console.see("end")
        self.console.config(state="disabled")
        self.update_idletasks()

    def set_controls_state(self, enabled):
        state = "normal" if enabled else "disabled"
        self.device_combo.config(state="readonly" if enabled else "disabled")
        self.backup_btn.config(state=state)
        self.optimize_btn.config(state=state)
        self.restore_btn.config(state=state)

    def start_backup(self):
        self.running = True
        self.action = "backup"
        self.set_controls_state(False)
        self.progress["value"] = 0
        self.console.config(state="normal")
        self.console.delete("1.0", tk.END)
        self.console.config(state="disabled")
        
        self.log(_(u"log_backup_started"))
        threading.Thread(target=self.worker).start()

    def confirm_optimize(self):
        if not HAS_PIL:
            tkMessageBox.showerror("Dependency Error", "Pillow (PIL) library is not installed.\n\nCover optimization is disabled. Please run:\npip3 install Pillow\n\nin Terminal to install it.")
            return
        title = _(u"confirm_backup_title")
        msg = _(u"confirm_backup_msg")
        if tkMessageBox.askyesno(title, msg):
            self.running = True
            self.action = "optimize"
            self.set_controls_state(False)
            self.progress["value"] = 0
            self.console.config(state="normal")
            self.console.delete("1.0", tk.END)
            self.console.config(state="disabled")
            
            idx = self.device_combo.current()
            target_size = 300
            if idx == 1:
                target_size = 600
            elif idx == 2:
                target_size = 1000
                
            self.log(_(u"log_optimize_started", target_size))
            threading.Thread(target=self.worker).start()

    def start_restore(self):
        self.running = True
        self.action = "restore"
        self.set_controls_state(False)
        self.progress["value"] = 0
        self.console.config(state="normal")
        self.console.delete("1.0", tk.END)
        self.console.config(state="disabled")
        
        self.log(_(u"log_restore_started"))
        threading.Thread(target=self.worker).start()

    def worker(self):
        try:
            self.after(0, lambda: self.status.config(text="Scanning tracks..."))
            tracks = get_tracks_with_covers()
            if not tracks:
                self.log(_(u"no_covers_found"))
                self.after(0, lambda: self.status.config(text="No covers found."))
                return

            total = len(tracks)
            self.after(0, lambda: self.progress.config(value=0, maximum=total))
            
            success_count = 0
            idx = self.device_combo.current()
            target_size = 300
            if idx == 1:
                target_size = 600
            elif idx == 2:
                target_size = 1000

            for i, t in enumerate(tracks):
                if not self.running:
                    break
                
                track_status = u"{0} - {1}".format(t["artist"], t["title"])
                self.after(0, lambda s=track_status: self.status.config(text=s[:50]))
                self.after(0, lambda val=i+1: self.progress.config(value=val))
                
                if self.action == "backup":
                    if backup_cover(t["pid"], t["title"], t["artist"]):
                        success_count += 1
                elif self.action == "optimize":
                    # Backup first to protect
                    backup_cover(t["pid"], t["title"], t["artist"])
                    if optimize_cover(t["pid"], target_size):
                        success_count += 1
                        self.log("Optimized: {0}".format(t["title"]))
                    else:
                        self.log(_(u"error_processing", t["title"]))
                elif self.action == "restore":
                    if restore_cover(t["pid"]):
                        success_count += 1
                        self.log("Restored: {0}".format(t["title"]))

            if self.running:
                if self.action == "backup":
                    self.log(_(u"log_backup_finished", success_count))
                elif self.action == "optimize":
                    self.log(_(u"log_optimize_finished", success_count))
                elif self.action == "restore":
                    self.log(_(u"log_restore_finished", success_count))
            else:
                self.log("Operation canceled.")
                
        except Exception as e:
            self.log("ERROR: " + str(e))
            self.after(0, lambda err=e: tkMessageBox.showerror("Optimizer Error", str(err)))
        finally:
            self.running = False
            self.action = None
            self.after(0, lambda: self.set_controls_state(True))
            self.after(0, lambda: self.status.config(text=""))
