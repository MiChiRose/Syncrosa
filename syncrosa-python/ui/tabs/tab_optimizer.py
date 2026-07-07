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
from core.operation_history import begin_active_operation, finish_active_operation
from features.covers_optimizer import (
    get_tracks_with_covers,
    get_last_scan_track_count,
    backup_cover,
    optimize_cover,
    restore_cover,
    load_manifest,
    save_manifest,
    HAS_PIL
)

class OptimizerTab(tk.Frame):
    def __init__(self, parent, master_app):
        tk.Frame.__init__(self, parent, bg="#ECECEC", borderwidth=0, highlightthickness=0)
        self.master_app = master_app
        self.running = False
        self.action = None
        self.active_operation_id = None
        self._ui_thread = threading.current_thread()
        self._log_lines = 0
        self.build_ui()

    def build_ui(self):
        header_frame = tk.Frame(self, bg="#ECECEC")
        header_frame.pack(pady=(15, 5))
        
        self.title_lbl = tk.Label(header_frame, text=_(u"covers_optimizer"), font=("system", 14, "bold"), bg="#ECECEC")
        self.title_lbl.pack(side=tk.LEFT)
        
        self.help_btn = tk.Button(
            header_frame, text="?", font=("system", 11, "bold"), width=2,
            command=self.show_help, highlightbackground="#ECECEC"
        )
        self.help_btn.pack(side=tk.LEFT, padx=10)

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

        self.stop_btn = ttk.Button(self.btn_frame, text="Stop", command=self.stop_process, width=10, state="disabled")
        self.stop_btn.pack(side=tk.LEFT, padx=5)
        self.set_controls_state(True)

    def _append_log(self, text):
        if not self.winfo_exists():
            return
        # Format with timestamp
        stamp = time.strftime("%H:%M:%S")
        line = "[{0}] {1}".format(stamp, text)
        
        self.console.config(state="normal")
        self.console.insert("end", line + "\n")
        self._log_lines += 1
        while self._log_lines > 500:
            self.console.delete("1.0", "2.0")
            self._log_lines -= 1
        self.console.see("end")
        self.console.config(state="disabled")

    def log(self, text):
        if threading.current_thread() is self._ui_thread:
            self._append_log(text)
        else:
            self.after(0, lambda t=text: self._append_log(t))

    def set_controls_state(self, enabled):
        state = "normal" if enabled else "disabled"
        self.device_combo.config(state="readonly" if enabled else "disabled")
        self.backup_btn.config(state=state)
        self.optimize_btn.config(state=state)
        self.restore_btn.config(state="normal" if (enabled and self.has_cover_backup()) else "disabled")
        self.stop_btn.config(state="disabled" if enabled else "normal")

    def has_cover_backup(self):
        try:
            return len(load_manifest().get("backups", {})) > 0
        except Exception:
            return False

    def clear_console(self):
        self.console.config(state="normal")
        self.console.delete("1.0", tk.END)
        self.console.config(state="disabled")
        self._log_lines = 0

    def stop_process(self):
        self.running = False
        self.stop_btn.config(state="disabled")
        self.status.config(text="Stopping after current track...")
        self.log("Stopping after current track...")

    def start_backup(self):
        self.running = True
        self.action = "backup"
        self.set_controls_state(False)
        self.progress["value"] = 0
        self.clear_console()
        
        self.log(_(u"log_backup_started"))
        self.active_operation_id = begin_active_operation(
            "Covers Optimizer",
            "Backup Original Covers",
            "Cover backup was interrupted.",
            0,
            ""
        )
        worker = threading.Thread(target=self.worker)
        worker.daemon = True
        worker.start()

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
            self.clear_console()
            
            idx = self.device_combo.current()
            target_size = 300
            if idx == 1:
                target_size = 600
            elif idx == 2:
                target_size = 1000
                
            self.log(_(u"log_optimize_started", target_size))
            self.active_operation_id = begin_active_operation(
                "Covers Optimizer",
                "Optimize Covers",
                "Cover optimization was interrupted.",
                0,
                ""
            )
            worker = threading.Thread(target=self.worker)
            worker.daemon = True
            worker.start()

    def start_restore(self):
        self.running = True
        self.action = "restore"
        self.set_controls_state(False)
        self.progress["value"] = 0
        self.clear_console()
        
        self.log(_(u"log_restore_started"))
        self.active_operation_id = begin_active_operation(
            "Covers Optimizer",
            "Restore Original Covers",
            "Cover restore was interrupted.",
            0,
            ""
        )
        worker = threading.Thread(target=self.worker)
        worker.daemon = True
        worker.start()

    def worker(self):
        clear_status_when_done = True
        try:
            self.after(0, lambda: self.status.config(text="Scanning tracks..."))
            def scan_progress(curr, total):
                self.after(0, lambda c=curr, t=total: self.status.config(text="Scanning tracks... ({}/{})".format(c, t)))

            tracks = get_tracks_with_covers(scan_progress, lambda: self.running)
            scan_count = get_last_scan_track_count()
            if hasattr(self.master_app, 'apply_library_status') and scan_count is not None:
                self.after(0, lambda c=scan_count: self.master_app.apply_library_status(c, None if c >= 0 else "Could not read iTunes library."))
            if not tracks:
                clear_status_when_done = False
                if scan_count == 0:
                    self.log("iTunes library has no tracks. There is no cover artwork to process.")
                    self.after(0, lambda: self.status.config(text="No iTunes tracks found."))
                elif scan_count is not None and scan_count < 0:
                    self.log("Could not read iTunes library tracks. Covers operation stopped.")
                    self.after(0, lambda: self.status.config(text="Could not read iTunes library."))
                else:
                    self.log(_(u"no_covers_found"))
                    self.after(0, lambda: self.status.config(text="No covers found."))
                return

            total = len(tracks)
            self.after(0, lambda: self.progress.config(value=0, maximum=total))
            
            success_count = 0
            manifest = load_manifest()
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
                    if backup_cover(t["pid"], t["title"], t["artist"], manifest=manifest, save=False):
                        success_count += 1
                        if success_count % 25 == 0:
                            save_manifest(manifest)
                elif self.action == "optimize":
                    # Backup first to protect
                    if backup_cover(t["pid"], t["title"], t["artist"], manifest=manifest, save=False) and (i + 1) % 25 == 0:
                        save_manifest(manifest)
                    if optimize_cover(t["pid"], target_size, manifest=manifest):
                        success_count += 1
                        self.log("Optimized: {0}".format(t["title"]))
                    else:
                        self.log(_(u"error_processing", t["title"]))
                elif self.action == "restore":
                    if restore_cover(t["pid"], manifest=manifest):
                        success_count += 1
                        self.log("Restored: {0}".format(t["title"]))

            save_manifest(manifest)

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
            finish_active_operation(getattr(self, "active_operation_id", None))
            self.active_operation_id = None
            self.running = False
            self.action = None
            self.after(0, lambda: self.set_controls_state(True))
            if clear_status_when_done:
                self.after(0, lambda: self.status.config(text=""))

    def show_help(self):
        from ui.components import HelpDialog
        help_text = (
            "COVERS OPTIMIZER INSTRUCTIONS:\n\n"
            "1. Select Target Resolution:\n"
            "   Choose the target device from the dropdown menu to select the optimal resolution for your album covers (e.g., iPod Classic: 300x300, iPhone: 600x600, High-Res: 1000x1000).\n\n"
            "2. Backup Original Covers:\n"
            "   It is highly recommended to click 'Backup Original Covers' first. This saves your full-resolution original covers to 'Documents/AlbumCovers' folder.\n\n"
            "3. Optimize Covers:\n"
            "   Clicking 'Optimize Covers' will automatically extract each track's artwork, resize/compress it according to the target device using PIL (Pillow), and save it back to iTunes. This significantly reduces the size of your iTunes database and speeds up synching to retro devices.\n\n"
            "4. Restore Covers:\n"
            "   If you wish to restore the original full-quality artwork later, click 'Restore Original Covers'. It will read the backups from your 'Documents/AlbumCovers' folder and write them back to iTunes."
        )
        HelpDialog(self, "Covers Optimizer Help", help_text)
