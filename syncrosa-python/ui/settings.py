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
import json

from core.localization import _, LANGUAGES
from core.config import CONFIG_DATA, save_config
from core.network import test_api_key, make_request
from ui.components import ProgressWindow

class SetupWindow(tk.Toplevel):
    def __init__(self, parent, on_success):
        tk.Toplevel.__init__(self, parent)
        self.title(_(u"menu_ai_settings").replace("...", ""))
        
        window_width = 750
        window_height = 540
        self.geometry("{}x{}".format(window_width, window_height))
        self.resizable(False, False)
        self.transient(parent)
        self.grab_set()
        
        self.on_success = on_success
        self.configure(bg="#ECECEC")
        
        self.update_idletasks()
        sw = self.winfo_screenwidth()
        sh = self.winfo_screenheight()
        self.geometry("+{}+{}".format((sw - window_width)//2, (sh - window_height)//2))
        
        main_frame = tk.Frame(self, bg="#ECECEC")
        main_frame.pack(fill=tk.BOTH, expand=True, padx=20, pady=(20, 10))
        
        # --- PROVIDER SECTION ---
        tk.Label(main_frame, text=_(u"setup_grp_provider"), font=("system", 13), bg="#ECECEC").pack(anchor="w", pady=(0, 5))
        
        self.provider_var = tk.StringVar(value=CONFIG_DATA.get("provider", "Gemini"))
        frame_prov = tk.Frame(main_frame, bg="#ECECEC")
        frame_prov.pack(anchor="w", padx=10, pady=5)
        tk.Radiobutton(frame_prov, text="Google Gemini", variable=self.provider_var, value="Gemini", command=self.update_models, font=("system", 13), bg="#ECECEC").pack(side=tk.LEFT, padx=(0, 15))
        tk.Radiobutton(frame_prov, text="Groq", variable=self.provider_var, value="Groq", command=self.update_models, font=("system", 13), bg="#ECECEC").pack(side=tk.LEFT, padx=15)
        tk.Radiobutton(frame_prov, text="OpenRouter", variable=self.provider_var, value="OpenRouter", command=self.update_models, font=("system", 13), bg="#ECECEC").pack(side=tk.LEFT, padx=15)
        
        tk.Frame(main_frame, bg="#D4D4D4", height=1).pack(fill=tk.X, pady=15)
        
        # --- CONNECTION SECTION ---
        tk.Label(main_frame, text=_(u"setup_grp_conn"), font=("system", 13), bg="#ECECEC").pack(anchor="w", pady=(0, 10))
        
        conn_frame = tk.Frame(main_frame, bg="#ECECEC")
        conn_frame.pack(fill=tk.X, padx=10)
        conn_frame.columnconfigure(1, weight=1)
        
        # Row 0: Model
        tk.Label(conn_frame, text=_(u"setup_model"), font=("system", 12), bg="#ECECEC").grid(row=0, column=0, sticky="w", pady=10, padx=(0, 10))
        self.model_var = tk.StringVar()
        self.model_dropdown = ttk.Combobox(conn_frame, textvariable=self.model_var, font=("system", 13))
        self.model_dropdown.grid(row=0, column=1, sticky="we", pady=10)
        
        self.btn_sync = ttk.Button(conn_frame, text=_(u"btn_sync"), command=lambda: self.update_models(force_sync=True), width=22)
        self.btn_sync.grid(row=0, column=2, sticky="we", padx=(15, 0), pady=10)
        
        self.apply_local_models()
        if CONFIG_DATA.get("model"):
            self.model_var.set(CONFIG_DATA.get("model"))
            
        # Row 1: Key
        tk.Label(conn_frame, text=_(u"setup_key"), font=("system", 12), bg="#ECECEC").grid(row=1, column=0, sticky="w", pady=(10, 0), padx=(0, 10))
        self.api_key_entry = tk.Entry(conn_frame, show="*", font=("system", 14), highlightbackground="#ECECEC")
        self.api_key_entry.insert(0, CONFIG_DATA.get("api_key", ""))
        self.api_key_entry.grid(row=1, column=1, sticky="we", pady=(10, 0))
        
        # Row 2: Key Actions (Moved underneath)
        key_actions_frame = tk.Frame(conn_frame, bg="#ECECEC")
        key_actions_frame.grid(row=2, column=1, sticky="w", pady=(5, 10))
        
        self.show_key_state = False
        def toggle_key():
            self.show_key_state = not self.show_key_state
            if self.show_key_state:
                self.api_key_entry.config(show="")
                self.btn_show.config(text="HIDE KEY")
            else:
                self.api_key_entry.config(show="*")
                self.btn_show.config(text="SHOW KEY")
            
        self.btn_show = ttk.Button(key_actions_frame, text="SHOW KEY", command=toggle_key, width=12)
        self.btn_show.pack(side=tk.LEFT, padx=(0, 10))
        
        def quick_paste():
            try:
                text = self.clipboard_get()
                if text:
                    self.api_key_entry.delete(0, tk.END)
                    self.api_key_entry.insert(0, text)
            except: pass
            
        self.btn_paste = ttk.Button(key_actions_frame, text="PASTE FROM CLIPBOARD", command=quick_paste, width=22)
        self.btn_paste.pack(side=tk.LEFT)
        
        self.btn_save = ttk.Button(conn_frame, text=_(u"setup_btn"), command=self.validate, width=22)
        self.btn_save.grid(row=1, column=2, sticky="we", padx=(15, 0), pady=(10, 0))
        
        tk.Frame(main_frame, bg="#D4D4D4", height=1).pack(fill=tk.X, pady=15)
        
        # --- LIBRARY SECTION ---
        tk.Label(main_frame, text=_(u"setup_grp_lib"), font=("system", 13), bg="#ECECEC").pack(anchor="w", pady=(0, 10))
        
        lib_frame = tk.Frame(main_frame, bg="#ECECEC")
        lib_frame.pack(fill=tk.X, padx=10)
        
        self.btn_sync_lib = ttk.Button(lib_frame, text=_(u"btn_sync_lib"), command=self.clear_lib_cache, width=22)
        self.btn_sync_lib.pack(side=tk.LEFT, pady=10)

        tk.Frame(main_frame, bg="#D4D4D4", height=1).pack(fill=tk.X, pady=15)
        
        # --- PREFERENCES SECTION ---
        pref_frame = tk.Frame(main_frame, bg="#ECECEC")
        pref_frame.pack(fill=tk.X)
        
        self.log_pref_var = tk.BooleanVar(value=CONFIG_DATA.get("prompt_logs", True))
        tk.Checkbutton(pref_frame, text=_(u"setup_log_pref"), variable=self.log_pref_var, bg="#ECECEC", font=("system", 12), command=self.save_log_pref).pack(side=tk.LEFT, anchor="w", padx=10, pady=0)
        
        # --- FOOTER SECTION ---
        bottom_frame = tk.Frame(main_frame, bg="#ECECEC")
        bottom_frame.pack(side=tk.BOTTOM, fill=tk.X, pady=(20, 0))
        
        tk.Label(bottom_frame, text=_(u"footer"), font=("system", 10), fg="#666666", bg="#ECECEC", justify=tk.CENTER).pack(side=tk.LEFT, expand=True)
        
        self.help_canvas = tk.Canvas(bottom_frame, width=28, height=28, bg="#ECECEC", highlightthickness=0)
        self.help_canvas.pack(side=tk.RIGHT, anchor="se")
        self.help_bg = self.help_canvas.create_oval(2, 2, 26, 26, outline="#999999", fill="#EAEAEA", width=1)
        self.help_text = self.help_canvas.create_text(14, 14, text="?", font=("system", 14, "bold"), fill="#555555")
        
        self.help_canvas.bind("<Button-1>", lambda e: self.show_help())
        self.help_canvas.bind("<Enter>", lambda e: self.on_help_hover(True))
        self.help_canvas.bind("<Leave>", lambda e: self.on_help_hover(False))
        
        self.protocol("WM_DELETE_WINDOW", self.on_closing)

    def on_help_hover(self, is_hover):
        if is_hover:
            self.help_canvas.itemconfig(self.help_bg, fill="#D0D0D0", outline="#666666")
            self.help_canvas.itemconfig(self.help_text, fill="#222222")
            self.help_canvas.config(cursor="pointinghand")
        else:
            self.help_canvas.itemconfig(self.help_bg, fill="#EAEAEA", outline="#999999")
            self.help_canvas.itemconfig(self.help_text, fill="#555555")
            self.help_canvas.config(cursor="")

    def save_log_pref(self):
        CONFIG_DATA["prompt_logs"] = self.log_pref_var.get()
        save_config(CONFIG_DATA)
        
    def clear_lib_cache(self):
        self.btn_sync_lib.config(state="disabled")
        self.prog_win = ProgressWindow(self)
        self.after(0, self.prog_win.start_timer)
        
        def task():
            from core.itunes_bridge import get_library
            try:
                def update_progress(curr, total):
                    self.after(0, lambda: self.prog_win.progress.config(value=curr, maximum=total))
                    self.after(0, lambda: self.prog_win.lbl.config(text=_(u"prog_read", curr, total)))
                    
                lib = get_library(update_progress, lambda: self.prog_win.running)
                
                if not self.prog_win.running:
                    self.after(0, self.prog_win.stop_timer)
                    self.after(0, self.prog_win.destroy)
                    self.after(0, lambda: self.btn_sync_lib.config(state="normal"))
                    return
                    
                self.master.cached_library = lib
                self.master.total_tracks = len(lib)
                
                # Update main UI
                if hasattr(self.master, 'tab_genius'):
                    self.after(0, self.master.tab_genius._update_library_info)
                
                self.after(0, self.prog_win.stop_timer)
                self.after(0, self.prog_win.destroy)
                self.after(0, lambda: tkMessageBox.showinfo("Sync", _(u"msg_lib_synced")))
                self.after(0, lambda: self.btn_sync_lib.config(state="normal"))
            except Exception as e:
                self.after(0, self.prog_win.stop_timer)
                self.after(0, self.prog_win.destroy)
                self.after(0, lambda: tkMessageBox.showerror("Error", str(e)))
                self.after(0, lambda: self.btn_sync_lib.config(state="normal"))
                
        threading.Thread(target=task).start()

    def on_closing(self):
        self.grab_release()
        if not CONFIG_DATA.get("api_key"):
            self.master.quit()
            self.master.destroy()
            sys.exit(0)
        else:
            self.destroy()

    def show_help(self):
        tkMessageBox.showinfo(_(u"help_title"), _(u"help_text"))

    def apply_local_models(self):
        models_dict = {
            "Gemini": ["gemini-1.5-flash-latest", "gemini-pro", "gemini-1.5-flash", "gemini-1.5-pro", "gemini-2.0-flash-exp"],
            "Groq": ["llama3-70b-8192", "mixtral-8x7b-32768", "llama3-8b-8192", "llama-3.1-70b-versatile"],
            "OpenRouter": ["z-ai/glm-4.5-air:free", "meta-llama/llama-3.3-70b-instruct:free", "deepseek/deepseek-r1-distill-llama-70b:free", "google/gemma-4-26b-a4b-it:free", "qwen/qwen2.5-72b-instruct:free"]
        }
        prov = self.provider_var.get()
        models = models_dict.get(prov, [])
        self.model_dropdown['values'] = models
        current = self.model_var.get()
        if current not in models and models:
            self.model_var.set(models[0])

    def update_models(self, force_sync=False):
        if force_sync:
            prov = self.provider_var.get()
            if prov != "OpenRouter":
                tkMessageBox.showinfo("Sync", "Auto-sync is only available for OpenRouter.")
                return
                
            self.btn_sync.config(state="disabled")
            self.update_idletasks()
            
            def fetch():
                try:
                    url = "https://openrouter.ai/api/v1/models"
                    ok, out = make_request(url, {}, timeout_sec=15)
                    if ok and out:
                        data = json.loads(out)
                        free_models = [m['id'] for m in data.get('data', []) if ':free' in m['id']]
                        if free_models:
                            free_models.sort()
                            self.after(0, self.apply_synced_models, free_models, prov)
                            return
                        else:
                            self.after(0, self.fail_sync, "No free models found.")
                            return
                    else:
                        self.after(0, self.fail_sync, "Error: " + str(out)[:100])
                        return
                except Exception as e:
                    self.after(0, self.fail_sync, "Exception: " + str(e)[:100])
                    return
                
            threading.Thread(target=fetch).start()
        else:
            self.apply_local_models()
            
    def apply_synced_models(self, models, requested_prov):
        if self.provider_var.get() != requested_prov:
            self.btn_sync.config(state="normal")
            return
            
        self.model_dropdown['values'] = models
        current = self.model_var.get()
        if current not in models and models:
            self.model_var.set(models[0])
        self.btn_sync.config(state="normal")
        tkMessageBox.showinfo("Sync", _(u"sync_success"))
        
    def fail_sync(self, err_msg="Failed to sync models"):
        self.btn_sync.config(state="normal")
        tkMessageBox.showerror("Sync", err_msg)

    def validate(self):
        prov = self.provider_var.get()
        mod = self.model_var.get()
        key = self.api_key_entry.get().strip()
        
        if not key:
            tkMessageBox.showerror("Error", _(u"err_no_key"))
            return
            
        self.btn_save.config(state='disabled')
        self.update()
        
        def check():
            try:
                ok, msg = test_api_key(prov, key, mod)
            except Exception as e:
                ok, msg = False, "Internal error: " + str(e)
            self.after(0, self.finish_validate, ok, msg, prov, mod, key)
            
        threading.Thread(target=check).start()

    def finish_validate(self, ok, msg, prov, mod, key):
        self.btn_save.config(state='normal')
        if ok:
            CONFIG_DATA["provider"] = prov
            CONFIG_DATA["model"] = mod
            CONFIG_DATA["api_key"] = key
            save_config(CONFIG_DATA)
            tkMessageBox.showinfo("Success", _(u"status_success"))
            self.on_success()
            self.grab_release()
            self.destroy()
        else:
            user_msg = _(u"err_conn")
            if "401" in msg or "Authentication" in msg or "User not found" in msg:
                user_msg = _(u"err_invalid_key")
            elif "404" in msg or "endpoints found" in msg.lower() or "not a valid model id" in msg.lower():
                user_msg = _(u"err_invalid_model")
            elif "429" in msg or "overloaded" in msg.lower() or "Provider returned error" in msg:
                user_msg = _(u"err_429")
            
            if CONFIG_DATA.get("prompt_logs", True):
                save_log = tkMessageBox.askyesno("Connection Error", user_msg + "\n\n" + _(u"ask_save_log"))
                if save_log:
                    desktop = os.path.join(os.path.expanduser("~"), "Desktop")
                    log_file = os.path.join(desktop, "iTunesGenius_Validation_Error.txt")
                    try:
                        with open(log_file, "w") as f:
                            f.write("API VALIDATION ERROR LOG\n")
                            f.write("Provider: " + prov + "\n")
                            f.write("Model: " + mod + "\n")
                            f.write("-" * 30 + "\n")
                            f.write(msg + "\n")
                        tkMessageBox.showinfo(_(u"log_saved_title"), _(u"log_saved_msg").format("iTunesGenius_Validation_Error.txt"))
                    except: pass
            else:
                tkMessageBox.showerror("Connection Error", user_msg)
