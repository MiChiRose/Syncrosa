# -*- coding: utf-8 -*-
import codecs
import re

with codecs.open('/Users/ymbrimit/Desktop/iTunesGeniusAIphoenix/app_logic.py', 'r', 'utf-8') as f:
    content = f.read()

# 1. Update font from "Helvetica Neue" to "system"
content = content.replace('"Helvetica Neue"', '"system"')

# 2. Replace clear_lib_cache
old_clear = u"""    def clear_lib_cache(self):
        self.master.cached_library = None
        tkMessageBox.showinfo("Sync", _(u"msg_lib_synced") if "msg_lib_synced" in LANGUAGES["en"] else "Library cache cleared!")"""

new_clear = u"""    def clear_lib_cache(self):
        self.btn_sync_lib.config(state="disabled")
        self.prog_win = ProgressWindow(self)
        
        def task():
            try:
                def update_progress(curr, total):
                    self.after(0, lambda: self.prog_win.progress.config(value=curr, maximum=total))
                    self.after(0, lambda: self.prog_win.lbl.config(text=_(u"prog_read", curr, total)))
                    
                lib = get_library(update_progress, lambda: self.prog_win.running)
                
                if not self.prog_win.running:
                    self.after(0, self.prog_win.destroy)
                    self.after(0, lambda: self.btn_sync_lib.config(state="normal"))
                    return
                    
                self.master.cached_library = lib
                self.after(0, self.prog_win.destroy)
                self.after(0, lambda: tkMessageBox.showinfo("Sync", _(u"msg_lib_synced") if "msg_lib_synced" in LANGUAGES["en"] else "Library cache updated!"))
                self.after(0, lambda: self.btn_sync_lib.config(state="normal"))
            except Exception as e:
                self.after(0, self.prog_win.destroy)
                self.after(0, lambda: tkMessageBox.showerror("Error", str(e)))
                self.after(0, lambda: self.btn_sync_lib.config(state="normal"))
                
        import threading
        threading.Thread(target=task).start()"""

content = content.replace(old_clear, new_clear)

# 3. Update translations for msg_lib_synced
translations = {
    "en": u'"msg_lib_synced": "Library cache updated!",',
    "ru": u'"msg_lib_synced": u"Кэш библиотеки обновлён!",',
    "be": u'"msg_lib_synced": u"Кэш бібліятэкі абноўлены!",',
    "ko": u'"msg_lib_synced": u"보관함 캐시가 업데이트되었습니다!",',
    "ja": u'"msg_lib_synced": u"ライブラリのキャッシュが更新されました！",',
    "zh": u'"msg_lib_synced": u"资料库缓存已更新！",',
    "de": u'"msg_lib_synced": u"Mediathek-Cache aktualisiert!",',
    "pl": u'"msg_lib_synced": u"Pamięć podręczna biblioteki zaktualizowana!",',
    "et": u'"msg_lib_synced": u"Raamatukogu vahemälu uuendatud!",',
    "es": u'"msg_lib_synced": u"¡Caché de biblioteca actualizado!",'
}

for lang, new_key in translations.items():
    # Find the language block and replace msg_lib_synced
    pattern = r'("' + lang + r'": \{.*?)"msg_lib_synced":.*?(,\n|})'
    content = re.sub(pattern, r'\1' + new_key + r'\2', content, flags=re.DOTALL)

with codecs.open('/Users/ymbrimit/Desktop/iTunesGeniusAIphoenix/app_logic.py', 'w', 'utf-8') as f:
    f.write(content)
print("UI script completed.")
