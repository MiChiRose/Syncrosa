# -*- coding: utf-8 -*-
import os
import sys

# --- EMERGENCY PATH FIX FOR LEGACY MAC BUNDLES ---
res_path = os.path.dirname(os.path.abspath(__file__))
if res_path not in sys.path:
    sys.path.insert(0, res_path)

import Tkinter as tk
import ttk
import tkMessageBox
import ssl

# Absolute imports from the Resources root
from core.config import CONFIG_DATA, save_config
from core.localization import _
from core.itunes_bridge import run_as
from ui.settings import SetupWindow
from ui.tabs.tab_genius import GeniusTab
from ui.tabs.tab_fixer import FixerTab

if sys.version_info[0] < 3:
    reload(sys)
    sys.setdefaultencoding('utf-8')

class App(tk.Tk):
    def __init__(self):
        tk.Tk.__init__(self)
        self.title(_(u"main_title"))
        self.geometry("600x550")
        self.resizable(False, False)
        self.configure(bg="#ECECEC")
        
        # We handle the icon via Info.plist for stability on old macOS
        
        w, h = 600, 550
        sw = self.winfo_screenwidth()
        sh = self.winfo_screenheight()
        self.geometry("{}x{}+{}+{}".format(w, h, int(sw/2 - w/2), int(sh/2 - h/2)))
        
        try:
            is_running = run_as('tell application "System Events" to (name of processes) contains "iTunes"')
            if is_running.lower() == "true":
                self.total_tracks = int(run_as('tell application "iTunes" to count every track'))
            else:
                self.total_tracks = "?"
        except:
            self.total_tracks = "?"

        self.build_menu()

        self.style = ttk.Style()
        self.style.theme_use('aqua')

        self.notebook = ttk.Notebook(self)
        self.notebook.pack(fill=tk.BOTH, expand=True, padx=2, pady=2)

        self.tab_genius = GeniusTab(self.notebook, self)
        self.tab_fixer = FixerTab(self.notebook, self)

        self.notebook.add(self.tab_genius, text="Genius")
        self.notebook.add(self.tab_fixer, text="Media Fixer")
        
        self.cached_library = None
        self.protocol("WM_DELETE_WINDOW", self.on_closing)
        
        # GLOBAL SHORTCUTS
        self.bind_all("<Command-v>", lambda e: self.focus_get().event_generate("<<Paste>>"))
        self.bind_all("<Command-c>", lambda e: self.focus_get().event_generate("<<Copy>>"))
        self.bind_all("<Command-x>", lambda e: self.focus_get().event_generate("<<Cut>>"))
        self.bind_all("<Command-a>", lambda e: self.focus_get().event_generate("<<SelectAll>>"))
        
        self.withdraw()
        
        if "0.9.8" in getattr(ssl, 'OPENSSL_VERSION', '') and not CONFIG_DATA.get("ssl_prompted"):
            CONFIG_DATA["ssl_prompted"] = True
            save_config(CONFIG_DATA)
            msg = _(u"ssl_update_msg")
            if tkMessageBox.askyesno("Security Update", msg):
                import webbrowser
                webbrowser.open("https://www.python.org/ftp/python/2.7.18/python-2.7.18-macosx10.9.pkg")
                
        if not CONFIG_DATA.get("api_key"):
            SetupWindow(self, self.deiconify)
        else:
            self.deiconify()
            
    def build_menu(self):
        self.menubar = tk.Menu(self)
        self.config(menu=self.menubar)
        
        self.app_menu = tk.Menu(self.menubar, tearoff=0)
        self.app_menu.add_command(label=_(u"menu_ai_settings"), command=self.open_settings)
        self.menubar.add_cascade(label=_(u"menu_settings"), menu=self.app_menu)
        
        self.edit_menu = tk.Menu(self.menubar, tearoff=0)
        self.edit_menu.add_command(label="Cut", accelerator="Cmd+X", command=lambda: self.focus_get().event_generate("<<Cut>>"))
        self.edit_menu.add_command(label="Copy", accelerator="Cmd+C", command=lambda: self.focus_get().event_generate("<<Copy>>"))
        self.edit_menu.add_command(label="Paste", accelerator="Cmd+V", command=lambda: self.focus_get().event_generate("<<Paste>>"))
        self.edit_menu.add_command(label="Select All", accelerator="Cmd+A", command=lambda: self.focus_get().event_generate("<<SelectAll>>"))
        self.menubar.add_cascade(label="Edit", menu=self.edit_menu)

        self.lang_menu = tk.Menu(self.menubar, tearoff=0)
        def change_lang(lc):
            CONFIG_DATA["lang"] = lc
            save_config(CONFIG_DATA)
            tkMessageBox.showinfo("Language", _(u"restart_required"))
            self.on_closing()

        self.lang_menu.add_command(label="English", command=lambda: change_lang("en"))
        self.lang_menu.add_command(label=u"Русский", command=lambda: change_lang("ru"))
        self.lang_menu.add_command(label=u"Беларуская", command=lambda: change_lang("be"))
        self.lang_menu.add_command(label=u"한국어", command=lambda: change_lang("ko"))
        self.lang_menu.add_command(label=u"日本語", command=lambda: change_lang("ja"))
        self.lang_menu.add_command(label=u"中文", command=lambda: change_lang("zh"))
        self.lang_menu.add_command(label="Deutsch", command=lambda: change_lang("de"))
        self.lang_menu.add_command(label="Polski", command=lambda: change_lang("pl"))
        self.lang_menu.add_command(label="Eesti", command=lambda: change_lang("et"))
        self.lang_menu.add_command(label="Español", command=lambda: change_lang("es"))
        self.menubar.add_cascade(label=_(u"menu_language"), menu=self.lang_menu)

    def open_settings(self):
        SetupWindow(self, lambda: None)

    def on_closing(self):
        self.quit()
        self.destroy()
        sys.exit(0)

if __name__ == "__main__":
    app = App()
    app.mainloop()
