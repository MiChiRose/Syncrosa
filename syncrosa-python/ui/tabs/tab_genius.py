# -*- coding: utf-8 -*-
import os
import sys

# --- EMERGENCY PATH FIX ---
res_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if res_path not in sys.path:
    sys.path.insert(0, res_path)

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
import re

from core.localization import _
from core.config import CONFIG_DATA
from core.itunes_bridge import get_library, create_itunes_playlist
from features.ai_playlist import generate_playlist_ids
from ui.components import ProgressWindow

class GeniusTab(tk.Frame):
    def __init__(self, parent, master_app):
        tk.Frame.__init__(self, parent, bg="#ECECEC", borderwidth=0, highlightthickness=0)
        self.master_app = master_app
        self.build_ui()

    def build_ui(self):
        form_frame = tk.Frame(self, bg="#ECECEC")
        form_frame.pack(pady=10, fill=tk.BOTH, expand=True)

        tk.Label(form_frame, text=_(u"pl_name"), font=("system", 13), bg="#ECECEC").pack(anchor="w", padx=40, pady=(5, 2))
        self.pl_name = tk.Entry(form_frame, state="normal", font=("system", 14), highlightbackground="#ECECEC")
        self.pl_name.insert(0, _(u"def_name"))
        self.pl_name.pack(fill=tk.X, padx=40, pady=(0, 15))
        
        tk.Label(form_frame, text=_(u"pl_mood"), font=("system", 13), bg="#ECECEC").pack(anchor="w", padx=40, pady=(5, 2))
        self.pl_mood = tk.Entry(form_frame, state="normal", font=("system", 14), highlightbackground="#ECECEC")
        self.pl_mood.pack(fill=tk.X, padx=40, pady=(0, 15))
        
        self.lbl_max = tk.Label(form_frame, text=_(u"max_available", str(self.master_app.total_tracks)), font=("system", 12), bg="#ECECEC")
        self.lbl_max.pack(anchor="w", padx=40, pady=(5, 2))
        
        self.count_var = tk.StringVar(value="25")
        
        count_frame = tk.Frame(form_frame, bg="#ECECEC")
        count_frame.pack(anchor="center", pady=(0, 15))
        
        def dec_count():
            try:
                val = int(self.count_var.get())
                if val > 1: self.count_var.set(str(val - 1))
            except: self.count_var.set("1")
            
        def inc_count():
            try:
                val = int(self.count_var.get())
                max_val = int(self.master_app.total_tracks) if str(self.master_app.total_tracks).isdigit() else 500
                if val < max_val: self.count_var.set(str(val + 1))
            except: self.count_var.set("25")

        ttk.Button(count_frame, text="-", command=dec_count, width=3).pack(side=tk.LEFT)
        self.pl_count = tk.Entry(count_frame, textvariable=self.count_var, font=("system", 14), width=6, justify=tk.CENTER, highlightbackground="#ECECEC")
        self.pl_count.pack(side=tk.LEFT, padx=10)
        ttk.Button(count_frame, text="+", command=inc_count, width=3).pack(side=tk.LEFT)
        
        self.btn_gen = ttk.Button(self, text=_(u"btn_gen"), command=self.start_generation)
        self.btn_gen.pack(pady=20, fill=tk.X, padx=40)
        
        self.lbl_lib = tk.Label(self, text=_(u"genius_lib_info").format(self.master_app.total_tracks), font=("system", 11), bg="#ECECEC", fg="#333333")
        self.lbl_lib.pack(pady=5)
        
        tk.Label(self, text=_(u"footer"), font=("system", 10), fg="#666666", bg="#ECECEC", justify=tk.CENTER).pack(side=tk.BOTTOM, pady=15)

    def _update_library_info(self):
        # Thread-safe update from main app
        def apply():
            lib_info = _(u"genius_lib_info").format(self.master_app.total_tracks)
            self.lbl_lib.config(text=lib_info)
            
            # Also update the "Max available" label
            self.lbl_max.config(text=_(u"max_available", str(self.master_app.total_tracks)))
        self.after(0, apply)

    def start_generation(self):
        mood = self.pl_mood.get().strip()
        name = self.pl_name.get().strip()
        count = self.pl_count.get()
        
        if not mood or not name:
            tkMessageBox.showerror("Error", _(u"err_fill_all"))
            return
            
        self.prog_win = ProgressWindow(self)
        threading.Thread(target=self.process_task, args=(mood, name, count)).start()

    def process_task(self, mood, name, count):
        try:
            def update_progress(curr, total):
                self.after(0, lambda: self.prog_win.progress.config(value=curr, maximum=total))
                self.after(0, lambda: self.prog_win.lbl.config(text=_(u"prog_read", curr, total)))
            
            def slog(txt):
                self.after(0, lambda: self.prog_win.log(txt))
                
            slog("Initializing generation process...")
                
            if not self.master_app.cached_library:
                slog("Scanning iTunes Library (may take a moment)...")
                lib = get_library(update_progress, lambda: self.prog_win.running)
                
                if not self.prog_win.running:
                    self.after(0, self.prog_win.destroy)
                    return
                    
                if not lib:
                    raise Exception(_(u"err_empty_lib"))
                    
                slog("Successfully cached %d tracks." % len(lib))
                self.master_app.cached_library = lib
            else:
                lib = self.master_app.cached_library
                slog("Using cached iTunes library (%d tracks)." % len(lib))
                update_progress(len(lib), len(lib))
                
            self.after(0, lambda: self.prog_win.lbl.config(text=_(u"prog_ask")))
            self.after(0, lambda: self.prog_win.progress.config(mode="indeterminate"))
            self.after(0, self.prog_win.progress.start)
            self.after(0, lambda: self.prog_win.start_fun_messages(CONFIG_DATA.get("lang", "en")))
            
            slog("Connecting to %s..." % CONFIG_DATA["provider"])
            slog("Sending playlist request (%d tracks)..." % len(lib))
            
            self.after(0, self.prog_win.start_timer)
            slog("Awaiting AI response (this may take 1-2 minutes)...")
            
            ok, res = generate_playlist_ids(
                CONFIG_DATA["provider"], 
                CONFIG_DATA["api_key"], 
                CONFIG_DATA["model"], 
                mood, 
                count, 
                lib
            )
            
            self.after(0, self.prog_win.stop_timer)
            
            if not self.prog_win.running:
                self.after(0, self.prog_win.destroy)
                return
                
            self.after(0, self.prog_win.progress.stop)
            self.after(0, lambda: self.prog_win.progress.config(mode="determinate", value=100))
            
            if not ok:
                slog("API Error or Timeout received.")
                raise Exception(res)
                
            slog("Response received! Parsing results...")
            final_ids = res
            
            slog("Found %d valid tracks. Injecting to iTunes..." % len(final_ids))
                
            self.after(0, lambda: self.prog_win.lbl.config(text=_(u"prog_create")))
            added_count = create_itunes_playlist(name, final_ids)
            slog("Playlist successfully created!")
            
            self.after(0, self.prog_win.destroy)
            
            def show_success():
                msg = _(u"msg_success", name, added_count)
                if CONFIG_DATA.get("prompt_logs", True):
                    save_log = tkMessageBox.askyesno("Success", msg + "\n\n" + _(u"ask_success_log"))
                    if save_log:
                        desktop = os.path.join(os.path.expanduser("~"), "Desktop")
                        log_file = os.path.join(desktop, "iTunesGenius_Success_Log.txt")
                        try:
                            with open(log_file, "w") as f:
                                f.write("GENERATION SUCCESS LOG\n")
                                f.write("Model: " + CONFIG_DATA["model"] + "\n")
                                f.write("Mood: " + mood.encode('utf-8') + "\n")
                                f.write("Requested Count: " + str(count) + "\n")
                                f.write("Added to iTunes: " + str(added_count) + "\n")
                                f.write("-" * 30 + "\n")
                                f.write("AI IDs returned: " + str(final_ids) + "\n")
                            tkMessageBox.showinfo(_(u"log_saved_title"), _(u"log_saved_msg").format("iTunesGenius_Success_Log.txt"))
                        except: pass
                else:
                    tkMessageBox.showinfo("Success", msg)
                    
            self.after(0, show_success)
            
        except Exception as e:
            err_str = str(e)
            short_msg = _(u"err_unexp")
            if "429" in err_str: short_msg = _(u"err_429")
            elif "Parsing Error" in err_str: short_msg = _(u"err_parse")
            
            self.after(0, self.prog_win.destroy)
            
            def show_error_and_ask_log():
                # Truncate for UI display but keep full for log file
                ui_err_str = (err_str[:250] + "...") if len(err_str) > 250 else err_str
                
                if CONFIG_DATA.get("prompt_logs", True):
                    save_log = tkMessageBox.askyesno("Generation Error", short_msg + "\n\n" + ui_err_str + "\n\n" + _(u"ask_save_log"))
                    if save_log:
                        desktop = os.path.join(os.path.expanduser("~"), "Desktop")
                        log_file = os.path.join(desktop, "iTunesGenius_Generation_Error.txt")
                        try:
                            with open(log_file, "w") as f:
                                f.write("GENERATION ERROR LOG\n")
                                f.write("Model: " + CONFIG_DATA["model"] + "\n")
                                f.write("User Input - Mood: " + mood.encode('utf-8') + "\n")
                                f.write("User Input - Name: " + name.encode('utf-8') + "\n")
                                f.write("User Input - Count: " + str(count) + "\n")
                                f.write("Provider: " + CONFIG_DATA["provider"] + "\n")
                                f.write("-" * 30 + "\n")
                                f.write(err_str + "\n") # Full error here
                            tkMessageBox.showinfo(_(u"log_saved_title"), _(u"log_saved_msg").format("iTunesGenius_Generation_Error.txt"))
                        except: pass
                else:
                    tkMessageBox.showerror("Generation Error", short_msg + "\n\n" + ui_err_str)
                    
            self.after(0, show_error_and_ask_log)
