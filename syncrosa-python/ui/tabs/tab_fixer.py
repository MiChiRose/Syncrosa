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
from ui.components import HelpDialog
from features.media_fixer import get_merge_candidates, apply_merge, run_metadata_fix

class FixerTab(tk.Frame):
    def __init__(self, parent, master_app):
        tk.Frame.__init__(self, parent, bg="#ECECEC", borderwidth=0, highlightthickness=0)
        self.master_app = master_app
        self.running = False
        self.build_ui()

    def build_ui(self):
        # Header frame with title and help button
        header_frame = tk.Frame(self, bg="#ECECEC")
        header_frame.pack(pady=(15, 5))
        
        self.label = tk.Label(header_frame, text="iTunes Media Info Fixer", font=("system", 14, "bold"), bg="#ECECEC")
        self.label.pack(side=tk.LEFT)
        
        self.help_btn = tk.Button(
            header_frame, text="?", font=("system", 11, "bold"), width=2,
            command=self.show_help, highlightbackground="#ECECEC"
        )
        self.help_btn.pack(side=tk.LEFT, padx=10)

        # Checkboxes Frame
        self.chk_frame = tk.LabelFrame(self, text="Tags to Update", font=("system", 11, "bold"), bg="#ECECEC", fg="#333333")
        self.chk_frame.pack(fill=tk.X, padx=40, pady=5)
        
        self.vars = {
            "album": tk.BooleanVar(value=True),
            "title": tk.BooleanVar(value=True),
            "artist": tk.BooleanVar(value=True),
            "genre": tk.BooleanVar(value=True),
            "track_number": tk.BooleanVar(value=True),
            "lyrics": tk.BooleanVar(value=True),
        }
        
        self.select_all_var = tk.BooleanVar(value=True)
        
        self.chk_all = tk.Checkbutton(
            self.chk_frame, text="Select All", variable=self.select_all_var,
            command=self.toggle_select_all, bg="#ECECEC", activebackground="#ECECEC"
        )
        self.chk_all.grid(row=0, column=0, sticky="w", padx=10, pady=2)
        
        self.chk_album = tk.Checkbutton(
            self.chk_frame, text="Album", variable=self.vars["album"],
            command=self.update_select_all, bg="#ECECEC", activebackground="#ECECEC"
        )
        self.chk_album.grid(row=0, column=1, sticky="w", padx=10, pady=2)
        
        self.chk_title = tk.Checkbutton(
            self.chk_frame, text="Title", variable=self.vars["title"],
            command=self.update_select_all, bg="#ECECEC", activebackground="#ECECEC"
        )
        self.chk_title.grid(row=0, column=2, sticky="w", padx=10, pady=2)
        
        self.chk_artist = tk.Checkbutton(
            self.chk_frame, text="Artist", variable=self.vars["artist"],
            command=self.update_select_all, bg="#ECECEC", activebackground="#ECECEC"
        )
        self.chk_artist.grid(row=1, column=0, sticky="w", padx=10, pady=2)
        
        self.chk_genre = tk.Checkbutton(
            self.chk_frame, text="Genre", variable=self.vars["genre"],
            command=self.update_select_all, bg="#ECECEC", activebackground="#ECECEC"
        )
        self.chk_genre.grid(row=1, column=1, sticky="w", padx=10, pady=2)
        
        self.chk_track_number = tk.Checkbutton(
            self.chk_frame, text="Track Number", variable=self.vars["track_number"],
            command=self.update_select_all, bg="#ECECEC", activebackground="#ECECEC"
        )
        self.chk_track_number.grid(row=1, column=2, sticky="w", padx=10, pady=2)
        
        self.chk_lyrics = tk.Checkbutton(
            self.chk_frame, text="Lyrics", variable=self.vars["lyrics"],
            command=self.update_select_all, bg="#ECECEC", activebackground="#ECECEC"
        )
        self.chk_lyrics.grid(row=2, column=0, sticky="w", padx=10, pady=2)

        # Progressbar
        self.progress = ttk.Progressbar(self, orient="horizontal", length=400, mode="determinate")
        self.progress.pack(pady=5, padx=40)

        self.status = tk.Label(self, text="Ready to start", font=("system", 10), bg="#ECECEC", fg="#333333")
        self.status.pack(pady=2)
        
        # Console Log View
        console_frame = tk.Frame(self, bg="#ECECEC")
        console_frame.pack(padx=40, pady=5, fill=tk.BOTH, expand=True)
        
        self.console = tk.Text(console_frame, height=5, font=("system", 10), bg="#1E1E1E", fg="#00FF00", highlightthickness=0, state="disabled")
        self.console.pack(fill=tk.BOTH, expand=True)

        self.btn_frame = tk.Frame(self, bg="#ECECEC")
        self.btn_frame.pack(pady=10)

        self.start_btn = ttk.Button(self.btn_frame, text="Start Restoration", command=self.start_process, width=22)
        self.start_btn.pack(side=tk.LEFT, padx=10)

        self.stop_btn = ttk.Button(self.btn_frame, text="Stop", command=self.stop, state="disabled", width=10)
        self.stop_btn.pack(side=tk.LEFT, padx=10)

    def show_help(self):
        help_text = (
            "ITUNES MEDIA INFO FIXER INSTRUCTIONS:\n\n"
            "1. Select Tags:\n"
            "   Choose which track attributes (Album, Title, Artist, Genre, Track Number, Lyrics) you want Syncrosa to automatically scan and restore.\n\n"
            "2. Album Merge:\n"
            "   If 'Album' is checked, the tool will find tracks with minor differences in their album names (e.g., typos, extra spaces, casing) and merge them into the most common correct spelling.\n\n"
            "3. Metadata Restoration:\n"
            "   The tool will query Apple's public iTunes search engine to restore missing metadata for checked tags.\n\n"
            "4. Lyrics Fetching:\n"
            "   If 'Lyrics' is checked, it will query a public lyrics database (api.lyrics.ovh) to download and save song lyrics directly into your iTunes tracks.\n\n"
            "5. Safe Process:\n"
            "   You can stop the process at any time. Tracks are processed individually and failures on individual tracks are handled gracefully without aborting."
        )
        HelpDialog(self, "Media Info Fixer Help", help_text)

    def toggle_select_all(self):
        val = self.select_all_var.get()
        for v in self.vars.values():
            v.set(val)
            
    def update_select_all(self):
        all_checked = all(v.get() for v in self.vars.values())
        self.select_all_var.set(all_checked)

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
        checked_tags = [name for name, var in self.vars.items() if var.get()]
        if not checked_tags:
            tkMessageBox.showwarning("Warning", "Please select at least one tag to update.")
            return

        self.running = True
        self.start_btn.config(state="disabled")
        self.stop_btn.config(state="normal")
        self.progress["value"] = 0
        self.console.config(state="normal")
        self.console.delete("1.0", tk.END)
        self.console.config(state="disabled")
        
        threading.Thread(target=self.worker, args=(checked_tags,)).start()

    def worker(self, checked_tags):
        try:
            # Phase 1: Merge
            if "album" in checked_tags:
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
                        lambda: self.running,
                        checked_tags
                    )
                else:
                    self.log("No duplicate albums found.")
            else:
                self.log("Skipping Phase 1 (Album tag not checked).")
            
            if not self.running: return
            
            # Phase 2: Metadata
            self.after(0, lambda: self.label.config(text="Phase 2: Updating Metadata"))
            self.log("Starting Phase 2: Fetching missing metadata...")
            
            run_metadata_fix(
                lambda c, t: self.after(0, lambda: self.progress.config(value=float(c)/t*100)),
                self.log,
                lambda: self.running,
                checked_tags
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
