# -*- coding: utf-8 -*-
import codecs
import re

with codecs.open('/Users/ymbrimit/Desktop/iTunesGeniusAIphoenix/app_logic.py', 'r', 'utf-8') as f:
    content = f.read()

# 1. Update ProgressWindow Style
prog_old = u"""class ProgressWindow(tk.Toplevel):
    def __init__(self, parent):
        tk.Toplevel.__init__(self, parent)
        self.title(_(u"prog_title"))
        self.geometry("440x220")
        self.resizable(False, False)
        self.transient(parent)
        self.grab_set()
        
        s = ttk.Style()
        # Значительно увеличиваем толщину прогресс-бара по просьбе пользователя
        s.configure("TProgressbar", thickness=30)
        
        self.lbl = tk.Label(self, text=_(u"prog_start"), font=("Helvetica Neue", 13))
        self.lbl.pack(pady=(25, 15))
        
        self.progress = ttk.Progressbar(self, orient="horizontal", length=380, mode="determinate", style="TProgressbar")
        self.progress.pack(pady=5)
        
        self.btn_cancel = tk.Button(self, text=_(u"prog_stop"), command=self.cancel, fg="red", font=("Helvetica Neue", 12))
        self.btn_cancel.pack(pady=20)"""

prog_new = u"""class ProgressWindow(tk.Toplevel):
    def __init__(self, parent):
        tk.Toplevel.__init__(self, parent)
        self.title(_(u"prog_title"))
        self.geometry("440x220")
        self.resizable(False, False)
        self.transient(parent)
        self.grab_set()
        self.configure(bg="#ECECEC")
        
        s = ttk.Style()
        # Значительно увеличиваем толщину прогресс-бара по просьбе пользователя
        s.configure("TProgressbar", thickness=30)
        
        self.lbl = tk.Label(self, text=_(u"prog_start"), font=("Helvetica Neue", 13), bg="#ECECEC")
        self.lbl.pack(pady=(25, 15))
        
        self.progress = ttk.Progressbar(self, orient="horizontal", length=380, mode="determinate", style="TProgressbar")
        self.progress.pack(pady=5)
        
        self.btn_cancel = tk.Button(self, text=_(u"prog_stop"), command=self.cancel, fg="red", font=("Helvetica Neue", 12), highlightbackground="#ECECEC")
        self.btn_cancel.pack(pady=20)"""

content = content.replace(prog_old, prog_new)

# 2. Add Translations
new_keys = {
    "en": u'"setup_grp_lib": "iTunes Library",\\n        "btn_sync_lib": "SYNC LIBRARY",\\n        "msg_lib_synced": "Library cache cleared! It will be re-synced on the next generation.",',
    "ru": u'"setup_grp_lib": u"Медиатека iTunes",\\n        "btn_sync_lib": u"СИНХРОНИЗИРОВАТЬ",\\n        "msg_lib_synced": u"Кэш очищен! Медиатека будет заново прочитана при следующей генерации.",',
    "be": u'"setup_grp_lib": u"Медыятэка iTunes",\\n        "btn_sync_lib": u"СІНХРАНІЗАВАЦЬ",\\n        "msg_lib_synced": u"Кэш ачышчаны! Медыятэка будзе зноў прачытана пры наступнай генерацыі.",',
    "ko": u'"setup_grp_lib": u"iTunes 보관함",\\n        "btn_sync_lib": u"보관함 동기화",\\n        "msg_lib_synced": u"보관함 캐시가 삭제되었습니다! 다음 생성 시 다시 동기화됩니다.",',
    "ja": u'"setup_grp_lib": u"iTunesライブラリ",\\n        "btn_sync_lib": u"ライブラリを同期",\\n        "msg_lib_synced": u"ライブラリのキャッシュがクリアされました！次回の生成時に再同期されます。",',
    "zh": u'"setup_grp_lib": u"iTunes 资料库",\\n        "btn_sync_lib": u"同步资料库",\\n        "msg_lib_synced": u"资料库缓存已清除！它将在下次生成时重新同步。",',
    "de": u'"setup_grp_lib": u"iTunes-Mediathek",\\n        "btn_sync_lib": u"MEDIATHEK SYNC",\\n        "msg_lib_synced": u"Mediathek-Cache geleert! Wird bei der nächsten Generierung neu synchronisiert.",',
    "pl": u'"setup_grp_lib": u"Biblioteka iTunes",\\n        "btn_sync_lib": u"SYNCHRONIZUJ",\\n        "msg_lib_synced": u"Pamięć podręczna wyczyszczona! Zostanie ponownie odczytana przy następnym generowaniu.",',
    "et": u'"setup_grp_lib": u"iTunesi Raamatukogu",\\n        "btn_sync_lib": u"SÜNKROONI",\\n        "msg_lib_synced": u"Vahemälu tühjendatud! Raamatukogu sünkroonitakse uuesti järgmisel genereerimisel.",',
    "es": u'"setup_grp_lib": u"Biblioteca de iTunes",\\n        "btn_sync_lib": u"SINCRONIZAR",\\n        "msg_lib_synced": u"¡Caché borrada! Se volverá a leer en la próxima generación.",'
}

for lang, new_key in new_keys.items():
    pattern = r'("' + lang + r'": \{)'
    replacement = r'\1\n        ' + new_key
    content = re.sub(pattern, replacement, content, count=1)

# 3. Soften Separators
content = content.replace('ttk.Separator(main_frame, orient=tk.HORIZONTAL).pack(fill=tk.X, pady=15)', 'tk.Frame(main_frame, bg="#D4D4D4", height=1).pack(fill=tk.X, pady=15)')

# 4. Modify SetupWindow to increase height and inject new Library Sync button
content = content.replace('window_height = 460', 'window_height = 540')

setup_lib_injection = u"""
        # --- LIBRARY SECTION ---
        tk.Label(main_frame, text=_(u"setup_grp_lib") if "setup_grp_lib" in LANGUAGES["en"] else "iTunes Library", font=("Helvetica Neue", 13), bg="#ECECEC").pack(anchor="w", pady=(0, 10))
        
        lib_frame = tk.Frame(main_frame, bg="#ECECEC")
        lib_frame.pack(fill=tk.X, padx=10)
        lib_frame.columnconfigure(1, weight=1)
        
        tk.Label(lib_frame, text="", font=("Helvetica Neue", 12), bg="#ECECEC").grid(row=0, column=0, sticky="e", pady=10, padx=(0, 10))
        tk.Label(lib_frame, text="", font=("Helvetica Neue", 12), fg="green", bg="#ECECEC").grid(row=0, column=1, sticky="w", pady=10)
        
        self.btn_sync_lib = tk.Button(lib_frame, text=_(u"btn_sync_lib") if "btn_sync_lib" in LANGUAGES["en"] else "SYNC LIBRARY", command=self.clear_lib_cache, highlightbackground="#ECECEC", font=("Helvetica Neue", 12), width=22)
        self.btn_sync_lib.grid(row=0, column=2, sticky="we", padx=(15, 0), pady=10)

        tk.Frame(main_frame, bg="#D4D4D4", height=1).pack(fill=tk.X, pady=15)
        
        # --- PREFERENCES SECTION ---"""

content = content.replace('# --- PREFERENCES SECTION ---', setup_lib_injection)

# Add clear_lib_cache method
clear_method = u"""
    def save_log_pref(self):
        CONFIG_DATA["prompt_logs"] = self.log_pref_var.get()
        save_config(CONFIG_DATA)
        
    def clear_lib_cache(self):
        self.master.cached_library = None
        tkMessageBox.showinfo("Sync", _(u"msg_lib_synced") if "msg_lib_synced" in LANGUAGES["en"] else "Library cache cleared!")
"""

content = content.replace(u"""
    def save_log_pref(self):
        CONFIG_DATA["prompt_logs"] = self.log_pref_var.get()
        save_config(CONFIG_DATA)""", clear_method)

with codecs.open('/Users/ymbrimit/Desktop/iTunesGeniusAIphoenix/app_logic.py', 'w', 'utf-8') as f:
    f.write(content)
