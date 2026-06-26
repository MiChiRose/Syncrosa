# -*- coding: utf-8 -*-
from __future__ import print_function, absolute_import
try:
    import Tkinter as tk
    import ttk
    import tkMessageBox
except ImportError:
    import tkinter as tk
    from tkinter import ttk
    from tkinter import messagebox as tkMessageBox
import threading
from core.localization import _
from core.config import CONFIG_DATA, save_config
from core.itunes_bridge import get_library_for_duplicates, delete_track_by_id
from ui.components import HelpDialog, ProgressWindow

class ScrollableFrame(tk.Frame):
    def __init__(self, parent, bg="#ECECEC"):
        tk.Frame.__init__(self, parent, bg=bg)
        
        self.canvas = tk.Canvas(self, borderwidth=0, highlightthickness=0, bg=bg)
        self.scrollbar = ttk.Scrollbar(self, orient="vertical", command=self.canvas.yview)
        self.scrollable_frame = tk.Frame(self.canvas, bg=bg)
        
        self.scrollable_frame.bind(
            "<Configure>",
            lambda e: self.canvas.configure(
                scrollregion=self.canvas.bbox("all")
            )
        )
        
        self.canvas_window = self.canvas.create_window((0, 0), window=self.scrollable_frame, anchor="nw")
        self.canvas.configure(yscrollcommand=self.scrollbar.set)
        
        self.canvas.pack(side="left", fill="both", expand=True)
        self.scrollbar.pack(side="right", fill="y")
        
        self.canvas.bind('<Configure>', self._on_canvas_configure)

    def _on_canvas_configure(self, event):
        self.canvas.itemconfig(self.canvas_window, width=event.width)

class DuplicateFinderTab(tk.Frame):
    def __init__(self, parent, master_app):
        tk.Frame.__init__(self, parent, bg="#ECECEC", borderwidth=0, highlightthickness=0)
        self.master_app = master_app
        self.build_ui()

    def build_ui(self):
        # Header with title and Help button
        header_frame = tk.Frame(self, bg="#ECECEC")
        header_frame.pack(pady=(15, 5))
        
        self.title_lbl = tk.Label(header_frame, text="iTunes Duplicate Finder", font=("system", 14, "bold"), bg="#ECECEC")
        self.title_lbl.pack(side=tk.LEFT)
        
        self.help_btn = tk.Button(
            header_frame, text="?", font=("system", 11, "bold"), width=2,
            command=self.show_help, highlightbackground="#ECECEC"
        )
        self.help_btn.pack(side=tk.LEFT, padx=10)
        
        # Scan Button
        self.scan_btn = ttk.Button(self, text="Show Duplicates", command=self.start_scan, width=20)
        self.scan_btn.pack(pady=5)
        
        # Scrollable Frame for pairs
        self.scroll_frame = ScrollableFrame(self)
        self.scroll_frame.pack(fill=tk.BOTH, expand=True, padx=20, pady=10)
        
        # Initial status
        lbl = tk.Label(self.scroll_frame.scrollable_frame, text="Click 'Show Duplicates' to scan your library.", font=("system", 11), bg="#ECECEC", fg="#555555")
        lbl.pack(pady=40)

    def show_help(self):
        help_text = (
            "DUPLICATE FINDER TAB INSTRUCTIONS:\n\n"
            "1. Show Duplicates:\n"
            "   Click the 'Show Duplicates' button to scan your iTunes library. The tool will group tracks by artist and title to identify potential copies.\n\n"
            "2. Side-by-Side Comparison:\n"
            "   For each duplicate pair, details like file format/codec, size, and metadata completeness are displayed. Completeness is scored out of 6 tags (Album, Genre, Year, Track Number, Lyrics, Artwork).\n\n"
            "3. Delete Copy:\n"
            "   Click 'Delete Copy A' or 'Delete Copy B' to delete that track from iTunes. The file will be removed safely via iTunes scripting bridge.\n\n"
            "4. Ignore Pair:\n"
            "   Click 'Ignore Pair' to hide this combination. Syncrosa will save the ignored pair (using their unique persistent IDs) in your configuration file so you won't see them in future scans."
        )
        HelpDialog(self, "Duplicate Finder Help", help_text)

    def start_scan(self):
        self.prog_win = ProgressWindow(self)
        self.prog_win.start_timer()
        
        # Clear previous elements
        for widget in self.scroll_frame.scrollable_frame.winfo_children():
            widget.destroy()
            
        def task():
            try:
                def update_progress(curr, total):
                    self.after(0, lambda: self.prog_win.progress.config(value=curr, maximum=total))
                    self.after(0, lambda: self.prog_win.lbl.config(text="Scanning... ({}/{})".format(curr, total)))
                
                raw_library = get_library_for_duplicates(update_progress, lambda: self.prog_win.running)
                
                if not self.prog_win.running:
                    self.after(0, self.prog_win.destroy)
                    self.after(0, self.show_initial_label)
                    return
                
                self.after(0, self.prog_win.destroy)
                self.after(0, lambda: self.render_pairs(raw_library))
            except Exception as e:
                self.after(0, self.prog_win.destroy)
                self.after(0, self.show_initial_label)
                self.after(0, lambda err=e: tkMessageBox.showerror("Error", str(err)))
                
        threading.Thread(target=task).start()

    def show_initial_label(self):
        lbl = tk.Label(self.scroll_frame.scrollable_frame, text="Click 'Show Duplicates' to scan your library.", font=("system", 11), bg="#ECECEC", fg="#555555")
        lbl.pack(pady=40)

    def render_pairs(self, raw_library):
        groups = {}
        for track_line in raw_library:
            parts = track_line.split('|')
            if len(parts) < 11: continue
            pid, art, nm, knd, sz, alb, gen, yr, trkNum, hasLyr, hasArt = parts[:11]
            k = (art.lower().strip(), nm.strip().lower())
            if k not in groups:
                groups[k] = []
            groups[k].append({
                'pid': pid, 'artist': art, 'title': nm, 'kind': knd, 'size': sz,
                'alb': alb, 'gen': gen, 'yr': yr, 'trkNum': trkNum,
                'hasLyr': hasLyr, 'hasArt': hasArt
            })
            
        duplicate_pairs = []
        ignored = CONFIG_DATA.get("ignored_duplicates", [])
        for k, trks in groups.items():
            if len(trks) > 1:
                for idx1 in range(len(trks)):
                    for idx2 in range(idx1 + 1, len(trks)):
                        t1 = trks[idx1]
                        t2 = trks[idx2]
                        pair_key = "-".join(sorted([t1['pid'], t2['pid']]))
                        if pair_key not in ignored:
                            duplicate_pairs.append((t1, t2))
                            
        if not duplicate_pairs:
            lbl = tk.Label(self.scroll_frame.scrollable_frame, text="No duplicates found in your library.", font=("system", 12), bg="#ECECEC")
            lbl.pack(pady=20)
            return
            
        for t1, t2 in duplicate_pairs:
            self.create_pair_card(t1, t2)

    def create_pair_card(self, t1, t2):
        card = tk.LabelFrame(
            self.scroll_frame.scrollable_frame,
            text=u"{} - {}".format(t1['artist'], t1['title']),
            font=("system", 11, "bold"), bg="#ECECEC", fg="#333333", bd=2, relief="groove"
        )
        card.pack(fill=tk.X, padx=10, pady=5)
        
        card.columnconfigure(0, weight=1)
        card.columnconfigure(1, weight=1)
        
        # Col 0 (Left track)
        col0 = tk.Frame(card, bg="#ECECEC")
        col0.grid(row=0, column=0, padx=10, pady=5, sticky="nsew")
        
        tk.Label(col0, text="Copy A", font=("system", 10, "bold"), bg="#ECECEC").pack()
        tk.Label(col0, text=u"Format: {}".format(t1['kind']), bg="#ECECEC", font=("system", 9)).pack()
        tk.Label(col0, text=u"Size: {}".format(self.format_size(t1['size'])), bg="#ECECEC", font=("system", 9)).pack()
        comp1 = self.get_completeness(t1['alb'], t1['gen'], t1['yr'], t1['trkNum'], t1['hasLyr'], t1['hasArt'])
        tk.Label(col0, text=u"Completeness: {}".format(comp1), bg="#ECECEC", font=("system", 9)).pack()
        
        btn_del1 = ttk.Button(
            col0, text="Delete Copy A",
            command=lambda pid=t1['pid'], card_widget=card: self.delete_copy(pid, card_widget)
        )
        btn_del1.pack(pady=5)
        
        # Col 1 (Right track)
        col1 = tk.Frame(card, bg="#ECECEC")
        col1.grid(row=0, column=1, padx=10, pady=5, sticky="nsew")
        
        tk.Label(col1, text="Copy B", font=("system", 10, "bold"), bg="#ECECEC").pack()
        tk.Label(col1, text=u"Format: {}".format(t2['kind']), bg="#ECECEC", font=("system", 9)).pack()
        tk.Label(col1, text=u"Size: {}".format(self.format_size(t2['size'])), bg="#ECECEC", font=("system", 9)).pack()
        comp2 = self.get_completeness(t2['alb'], t2['gen'], t2['yr'], t2['trkNum'], t2['hasLyr'], t2['hasArt'])
        tk.Label(col1, text=u"Completeness: {}".format(comp2), bg="#ECECEC", font=("system", 9)).pack()
        
        btn_del2 = ttk.Button(
            col1, text="Delete Copy B",
            command=lambda pid=t2['pid'], card_widget=card: self.delete_copy(pid, card_widget)
        )
        btn_del2.pack(pady=5)
        
        # Row 1 (Center bottom) - Ignore Button
        btn_ignore = ttk.Button(
            card, text="Ignore Pair",
            command=lambda pid1=t1['pid'], pid2=t2['pid'], card_widget=card: self.ignore_pair(pid1, pid2, card_widget)
        )
        btn_ignore.grid(row=1, column=0, columnspan=2, pady=(0, 5))

    def format_size(self, sz_bytes):
        try:
            val = int(sz_bytes)
            if val > 1024 * 1024:
                return "{:.2f} MB".format(val / (1024.0 * 1024.0))
            elif val > 1024:
                return "{:.2f} KB".format(val / 1024.0)
            else:
                return "{} B".format(val)
        except:
            return "Unknown Size"

    def get_completeness(self, alb, gen, yr, trkNum, hasLyr, hasArt):
        score = 0
        if alb and alb != "Unknown Album": score += 1
        if gen and gen.lower() not in ["", "unknown", "unknown genre"]: score += 1
        if yr and yr != "0" and yr != "": score += 1
        if trkNum and trkNum != "0" and trkNum != "": score += 1
        if hasLyr == "1": score += 1
        if hasArt == "1": score += 1
        pct = int((score / 6.0) * 100)
        return "{0}% ({1}/6 tags)".format(pct, score)

    def ignore_pair(self, pid1, pid2, card_widget):
        ignored = CONFIG_DATA.get("ignored_duplicates", [])
        pair_key = "-".join(sorted([pid1, pid2]))
        if pair_key not in ignored:
            ignored.append(pair_key)
            CONFIG_DATA["ignored_duplicates"] = ignored
            save_config(CONFIG_DATA)
        card_widget.destroy()
        
    def delete_copy(self, pid, card_widget):
        if tkMessageBox.askyesno("Confirm Delete", "Are you sure you want to delete this track copy from your iTunes library? This action cannot be undone."):
            res = delete_track_by_id(pid)
            if res == "OK":
                tkMessageBox.showinfo("Deleted", "Track deleted successfully from iTunes.")
                card_widget.destroy()
            else:
                tkMessageBox.showerror("Error", "Failed to delete track copy: " + str(res))
