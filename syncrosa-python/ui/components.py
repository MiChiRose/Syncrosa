# -*- coding: utf-8 -*-
from __future__ import absolute_import
import sys
try:
    import Tkinter as tk
    import ttk
except ImportError:
    import tkinter as tk
    from tkinter import ttk
from core.localization import _

class ProgressWindow(tk.Toplevel):
    def __init__(self, parent):
        tk.Toplevel.__init__(self, parent)
        self.title(_(u"prog_title"))
        self.geometry("440x290")
        self.resizable(False, False)
        self.transient(parent)
        self.grab_set()
        self.configure(bg="#ECECEC")
        
        s = ttk.Style()
        s.configure("TProgressbar", thickness=30)
        
        self.lbl = tk.Label(self, text=_(u"prog_start"), font=("system", 13, "bold"), bg="#ECECEC")
        self.lbl.pack(pady=(20, 10))
        
        self.progress = ttk.Progressbar(self, orient="horizontal", length=400, mode="determinate", style="TProgressbar")
        self.progress.pack(pady=5, padx=20)
        
        console_frame = tk.Frame(self, bg="#ECECEC")
        console_frame.pack(padx=20, pady=(10, 5), fill=tk.BOTH, expand=True)
        
        self.console_scroll = ttk.Scrollbar(console_frame)
        self.console_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        
        self.console = tk.Text(console_frame, height=5, font=("system", 10), bg="#1E1E1E", fg="#00FF00", highlightthickness=0, state="disabled", yscrollcommand=self.console_scroll.set)
        self.console.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.console_scroll.config(command=self.console.yview)
        
        cancel_frame = tk.Frame(self, bg="#ECECEC")
        cancel_frame.pack(pady=(5, 10))
        
        self.lbl_cancel = tk.Label(cancel_frame, text=_(u"prog_stop"), font=("system", 11), bg="#ECECEC", fg="#555555")
        self.lbl_cancel.pack(side=tk.LEFT, padx=(0, 10))
        
        self.btn_cancel = tk.Button(cancel_frame, text="X", command=self.cancel, fg="#555555", font=("system", 11, "bold"), highlightbackground="#ECECEC", width=2)
        self.btn_cancel.pack(side=tk.LEFT)
        
        self.timer_val = 0
        self.timer_active = False
        self.lbl_timer = tk.Label(self, text="00:00", font=("system", 11), bg="#ECECEC", fg="#333333")
        self.lbl_timer.place(x=380, y=20)

        self.running = True
        self.fun_active = False
        self.fun_idx = 0
        
        # Center the window
        self.update_idletasks()
        sw = self.winfo_screenwidth()
        sh = self.winfo_screenheight()
        self.geometry("+{}+{}".format((sw - 440)//2, (sh - 290)//2))

    def start_timer(self):
        self.timer_active = True
        self.timer_val = 0
        self._update_timer_ui()
        
    def _update_timer_ui(self):
        if not self.running or not self.timer_active or not self.winfo_exists():
            return
        
        m, s = divmod(self.timer_val, 60)
        self.lbl_timer.config(text="{:02d}:{:02d}".format(m, s))
        
        # Periodic Heartbeat every 60 seconds
        if self.timer_val > 0 and self.timer_val % 60 == 0:
            self.log(_(u"prog_heartbeat", m, s))
            
        self.timer_val += 1
        self.after(1000, self._update_timer_ui)
        
    def stop_timer(self):
        self.timer_active = False

    def log(self, text):
        self.console.config(state="normal")
        self.console.insert("end", "> " + text + "\n")
        self.console.see("end")
        self.console.config(state="disabled")
        self.update_idletasks()
        
    def start_fun_messages(self, lang):
        self.fun_active = True
        self.fun_idx = 0
        self._next_fun_msg(lang)
        
    def _next_fun_msg(self, lang):
        if not self.running or not self.fun_active or not self.winfo_exists():
            return
            
        msgs_dict = {
            "en": ["Analyzing your musical taste...", "Asking the neighbor for advice...", "The AI went to microwave some food...", "Sit back and relax...", "Still thinking... AI needs coffee."],
            "ru": [u"Анализируем ваш музыкальный вкус...", u"Даём послушать треки соседу...", u"ИИ пошёл греть еду в микроволновке...", u"Откиньтесь на спинку кресла и отдохните...", u"Всё ещё думаем... ИИ нужен кофе."],
            "be": [u"Аналізуем ваш музычны густ...", u"Даём паслухаць трэкі суседу...", u"ШІ пайшоў грэць ежу ў мікрахвалеўцы...", u"Адкіньцеся на спінку крэсла і адпачніце...", u"Усё яшчэ думаем... ШІ патрэбна кава."]
        }
        msgs = msgs_dict.get(lang, msgs_dict["en"])
        
        if msgs:
            self.lbl.config(text=msgs[self.fun_idx])
            self.fun_idx = (self.fun_idx + 1) % len(msgs)
            
        self.after(10000, lambda: self._next_fun_msg(lang))
        
    def cancel(self):
        self.running = False
        self.fun_active = False
        self.lbl.config(text=_(u"prog_canceling"))
        self.btn_cancel.config(state="disabled")

class HelpDialog(tk.Toplevel):
    def __init__(self, parent, title, text):
        tk.Toplevel.__init__(self, parent)
        self.title(title)
        self.geometry("480x380")
        self.resizable(True, True)
        self.transient(parent)
        self.grab_set()
        self.configure(bg="#ECECEC")
        
        try:
            parent_x = parent.winfo_rootx()
            parent_y = parent.winfo_rooty()
            parent_w = parent.winfo_width()
            parent_h = parent.winfo_height()
            x = parent_x + (parent_w - 480) // 2
            y = parent_y + (parent_h - 380) // 2
            self.geometry("+{}+{}".format(max(0, x), max(0, y)))
        except:
            pass
        
        main_frame = tk.Frame(self, bg="#ECECEC")
        main_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
        
        txt_frame = tk.Frame(main_frame, bg="#ECECEC")
        txt_frame.pack(fill=tk.BOTH, expand=True)
        
        scrollbar = ttk.Scrollbar(txt_frame)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        
        self.text_widget = tk.Text(txt_frame, wrap=tk.WORD, yscrollcommand=scrollbar.set, font=("system", 12), bg="white", fg="black")
        self.text_widget.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.config(command=self.text_widget.yview)
        
        if sys.version_info[0] < 3:
            if isinstance(text, str):
                text = text.decode('utf-8', 'ignore')
        else:
            if isinstance(text, bytes):
                text = text.decode('utf-8', 'ignore')
                
        self.text_widget.insert(tk.END, text)
        self.text_widget.config(state="disabled")
        
        btn = ttk.Button(main_frame, text="Close", command=self.destroy)
        btn.pack(pady=(10, 0))

