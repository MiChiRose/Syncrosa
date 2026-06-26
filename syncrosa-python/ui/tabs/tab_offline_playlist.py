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
import datetime
import threading
from core.localization import _
from core.itunes_bridge import get_library_for_offline_playlist, create_itunes_playlist
from ui.components import HelpDialog, ProgressWindow

class OfflinePlaylistTab(tk.Frame):
    def __init__(self, parent, master_app):
        tk.Frame.__init__(self, parent, bg="#ECECEC", borderwidth=0, highlightthickness=0)
        self.master_app = master_app
        self.local_library = []
        self.build_ui()

    def build_ui(self):
        # Header with Title and Help "?" button
        header_frame = tk.Frame(self, bg="#ECECEC")
        header_frame.pack(pady=(15, 5))
        
        self.title_lbl = tk.Label(header_frame, text="Offline Playlist Generator", font=("system", 14, "bold"), bg="#ECECEC")
        self.title_lbl.pack(side=tk.LEFT)
        
        self.help_btn = tk.Button(
            header_frame, text="?", font=("system", 11, "bold"), width=2,
            command=self.show_help, highlightbackground="#ECECEC"
        )
        self.help_btn.pack(side=tk.LEFT, padx=10)
        
        # Scan / Sync button
        self.scan_btn = ttk.Button(self, text="Scan Library", command=self.start_scan, width=20)
        self.scan_btn.pack(pady=5)
        
        self.status_lbl = tk.Label(self, text="Please scan library to populate filters.", font=("system", 10), bg="#ECECEC", fg="#666666")
        self.status_lbl.pack(pady=2)

        # General Filters Frame
        self.filters_frame = tk.LabelFrame(self, text="General Filters", font=("system", 11, "bold"), bg="#ECECEC", fg="#333333")
        self.filters_frame.pack(fill=tk.X, padx=40, pady=5)
        
        # Row 0: Genre, From Year, To Year
        tk.Label(self.filters_frame, text="Genre:", bg="#ECECEC", font=("system", 10)).grid(row=0, column=0, sticky="w", padx=10, pady=5)
        self.genre_combo = ttk.Combobox(self.filters_frame, state="readonly", width=12)
        self.genre_combo["values"] = ("Any",)
        self.genre_combo.current(0)
        self.genre_combo.grid(row=0, column=1, sticky="w", padx=5, pady=5)
        
        # Populate Year List
        current_year = datetime.datetime.now().year
        self.years = ["Any"] + [str(y) for y in range(1950, current_year + 1)]
        
        tk.Label(self.filters_frame, text="From:", bg="#ECECEC", font=("system", 10)).grid(row=0, column=2, sticky="w", padx=10, pady=5)
        self.from_year_combo = ttk.Combobox(self.filters_frame, state="readonly", width=8)
        self.from_year_combo["values"] = self.years
        self.from_year_combo.current(0)
        self.from_year_combo.grid(row=0, column=3, sticky="w", padx=5, pady=5)
        self.from_year_combo.bind("<<ComboboxSelected>>", self.on_from_year_changed)
        
        tk.Label(self.filters_frame, text="To:", bg="#ECECEC", font=("system", 10)).grid(row=0, column=4, sticky="w", padx=10, pady=5)
        self.to_year_combo = ttk.Combobox(self.filters_frame, state="readonly", width=8)
        self.to_year_combo["values"] = self.years
        self.to_year_combo.current(0)
        self.to_year_combo.grid(row=0, column=5, sticky="w", padx=5, pady=5)
        self.to_year_combo.bind("<<ComboboxSelected>>", self.on_to_year_changed)
        
        # Row 1: Rating and Cover Art Checkboxes
        self.req_cover_var = tk.BooleanVar(value=False)
        self.chk_cover = tk.Checkbutton(
            self.filters_frame, text="Require cover art (optional)", variable=self.req_cover_var,
            bg="#ECECEC", activebackground="#ECECEC", font=("system", 10)
        )
        self.chk_cover.grid(row=1, column=0, columnspan=3, sticky="w", padx=10, pady=5)
        
        self.req_rating_var = tk.BooleanVar(value=False)
        self.chk_rating = tk.Checkbutton(
            self.filters_frame, text="Filter by rating (optional, 3+ stars)", variable=self.req_rating_var,
            bg="#ECECEC", activebackground="#ECECEC", font=("system", 10)
        )
        self.chk_rating.grid(row=1, column=3, columnspan=3, sticky="w", padx=10, pady=5)

        # Decades Section Frame
        self.decades_frame = tk.LabelFrame(self, text="Playlists by Epochs", font=("system", 11, "bold"), bg="#ECECEC", fg="#333333")
        self.decades_frame.pack(fill=tk.X, padx=40, pady=5)
        
        self.decades = {
            "60s": tk.BooleanVar(value=False),
            "70s": tk.BooleanVar(value=False),
            "80s": tk.BooleanVar(value=False),
            "90s": tk.BooleanVar(value=False),
            "2000s": tk.BooleanVar(value=False),
            "2010s": tk.BooleanVar(value=False),
            "2020+": tk.BooleanVar(value=False),
        }
        
        # Layout Decades Checkboxes in a grid
        self.chk_60s = tk.Checkbutton(self.decades_frame, text="60s", variable=self.decades["60s"], bg="#ECECEC", activebackground="#ECECEC")
        self.chk_60s.grid(row=0, column=0, sticky="w", padx=15, pady=5)
        
        self.chk_70s = tk.Checkbutton(self.decades_frame, text="70s", variable=self.decades["70s"], bg="#ECECEC", activebackground="#ECECEC")
        self.chk_70s.grid(row=0, column=1, sticky="w", padx=15, pady=5)
        
        self.chk_80s = tk.Checkbutton(self.decades_frame, text="80s", variable=self.decades["80s"], bg="#ECECEC", activebackground="#ECECEC")
        self.chk_80s.grid(row=0, column=2, sticky="w", padx=15, pady=5)
        
        self.chk_90s = tk.Checkbutton(self.decades_frame, text="90s", variable=self.decades["90s"], bg="#ECECEC", activebackground="#ECECEC")
        self.chk_90s.grid(row=0, column=3, sticky="w", padx=15, pady=5)
        
        self.chk_2000s = tk.Checkbutton(self.decades_frame, text="2000s", variable=self.decades["2000s"], bg="#ECECEC", activebackground="#ECECEC")
        self.chk_2000s.grid(row=1, column=0, sticky="w", padx=15, pady=5)
        
        self.chk_2010s = tk.Checkbutton(self.decades_frame, text="2010s", variable=self.decades["2010s"], bg="#ECECEC", activebackground="#ECECEC")
        self.chk_2010s.grid(row=1, column=1, sticky="w", padx=15, pady=5)
        
        self.chk_2020s = tk.Checkbutton(self.decades_frame, text="2020+", variable=self.decades["2020+"], bg="#ECECEC", activebackground="#ECECEC")
        self.chk_2020s.grid(row=1, column=2, sticky="w", padx=15, pady=5)

        # Generate Button
        self.gen_btn = ttk.Button(self, text="Generate Playlists by Epochs", command=self.generate_playlists, width=30)
        self.gen_btn.pack(pady=15)

    def show_help(self):
        help_text = (
            "OFFLINE PLAYLIST GENERATOR INSTRUCTIONS:\n\n"
            "1. Scan Library:\n"
            "   Click 'Scan Library' to analyze your tracks. This loads genres, years, ratings, and artwork info required for filtering.\n\n"
            "2. General Filters:\n"
            "   - Genre: Select a specific genre or 'Any' for all.\n"
            "   - Year range (From/To): Filter tracks released within a specific period. Year ranges are validated dynamically (To >= From).\n"
            "   - Require cover art (optional): Excludes tracks that lack cover art.\n"
            "   - Filter by rating (optional): Excludes tracks with less than 3 stars rating.\n\n"
            "3. Playlists by Epochs:\n"
            "   Check one or more decades (60s, 70s, 80s, 90s, 2000s, 2010s, 2020+).\n\n"
            "4. Generation:\n"
            "   Click 'Generate Playlists by Epochs'. The tool will scan matching tracks for each checked decade. If 0 tracks match a decade, it skips creating that playlist and logs a warning. If no tracks match the general filters overall, a dialog asks if you want to ignore filters or cancel."
        )
        HelpDialog(self, "Offline Playlist Help", help_text)

    def on_from_year_changed(self, event):
        from_val = self.from_year_combo.get()
        to_val = self.to_year_combo.get()
        if from_val != "Any" and to_val != "Any":
            if int(from_val) > int(to_val):
                self.to_year_combo.set(from_val)

    def on_to_year_changed(self, event):
        from_val = self.from_year_combo.get()
        to_val = self.to_year_combo.get()
        if from_val != "Any" and to_val != "Any":
            if int(from_val) > int(to_val):
                self.from_year_combo.set(to_val)

    def start_scan(self):
        self.prog_win = ProgressWindow(self)
        self.prog_win.start_timer()
        
        def task():
            try:
                def update_progress(curr, total):
                    self.after(0, lambda: self.prog_win.progress.config(value=curr, maximum=total))
                    self.after(0, lambda: self.prog_win.lbl.config(text="Scanning Library... ({}/{})".format(curr, total)))
                
                lib = get_library_for_offline_playlist(update_progress, lambda: self.prog_win.running)
                if not self.prog_win.running:
                    self.after(0, self.prog_win.destroy)
                    return
                    
                self.after(0, self.prog_win.destroy)
                self.after(0, lambda: self.update_genres_and_library(lib))
            except Exception as e:
                self.after(0, self.prog_win.destroy)
                self.after(0, lambda err=e: tkMessageBox.showerror("Error", str(err)))
                
        threading.Thread(target=task).start()

    def update_genres_and_library(self, lib):
        self.local_library = lib
        genres = set()
        for line in lib:
            parts = line.split('|')
            if len(parts) >= 2:
                gen = parts[1].strip()
                if gen:
                    genres.add(gen)
        sorted_genres = ["Any"] + sorted(list(genres))
        self.genre_combo["values"] = sorted_genres
        self.genre_combo.current(0)
        
        self.status_lbl.config(text="Library scanned: {} tracks loaded.".format(len(lib)))
        tkMessageBox.showinfo("Scan Completed", "iTunes Library successfully scanned!")

    def generate_playlists(self):
        if not self.local_library:
            tkMessageBox.showwarning("Scan Required", "Please click 'Scan Library' first to load your iTunes tracks and genres.")
            return

        checked_decades = [dec for dec, var in self.decades.items() if var.get()]
        if not checked_decades:
            tkMessageBox.showwarning("Warning", "Please select at least one decade to generate playlists.")
            return

        # Get filters
        sel_genre = self.genre_combo.get()
        from_year = self.from_year_combo.get()
        to_year = self.to_year_combo.get()
        req_cover = self.req_cover_var.get()
        req_rating = self.req_rating_var.get()

        filtered_tracks = []
        for track_line in self.local_library:
            parts = track_line.split('|')
            if len(parts) < 5: continue
            pid, gen, yr, rt, hasArt = parts[:5]
            
            # Filter genre
            if sel_genre != "Any" and gen.lower() != sel_genre.lower():
                continue
                
            # Filter year range
            if yr:
                try:
                    y = int(yr)
                    if from_year != "Any" and y < int(from_year): continue
                    if to_year != "Any" and y > int(to_year): continue
                except:
                    if from_year != "Any" or to_year != "Any": continue
            else:
                if from_year != "Any" or to_year != "Any": continue
                
            # Filter cover art
            if req_cover and hasArt != "1":
                continue
                
            # Filter rating
            if req_rating:
                try:
                    rating_val = int(rt)
                    if rating_val < 60: # 3 stars rating
                        continue
                except:
                    continue
                    
            filtered_tracks.append({
                'pid': pid, 'genre': gen, 'year': yr, 'rating': rt, 'hasArt': hasArt
            })

        if not filtered_tracks:
            # Alert dialog offering to ignore filters or cancel
            res = tkMessageBox.askyesno(
                "No Tracks Found",
                "No tracks matched your selected filters.\n\n"
                "Would you like to ignore the filters (genre, year range, cover art, rating) and use all tracks from your library instead?"
            )
            if res:
                # Reset filtered list to all tracks
                filtered_tracks = []
                for track_line in self.local_library:
                    parts = track_line.split('|')
                    if len(parts) < 5: continue
                    pid, gen, yr, rt, hasArt = parts[:5]
                    filtered_tracks.append({
                        'pid': pid, 'genre': gen, 'year': yr, 'rating': rt, 'hasArt': hasArt
                    })
            else:
                # Cancel generation
                return

        def matches_decade(year, decade):
            if not year: return False
            try:
                y = int(year)
                if decade == "60s": return 1960 <= y <= 1969
                if decade == "70s": return 1970 <= y <= 1979
                if decade == "80s": return 1980 <= y <= 1989
                if decade == "90s": return 1990 <= y <= 1999
                if decade == "2000s": return 2000 <= y <= 2009
                if decade == "2010s": return 2010 <= y <= 2019
                if decade == "2020+": return y >= 2020
            except:
                pass
            return False

        skipped_decades = []
        created_playlists = []

        for dec in checked_decades:
            dec_tracks = [t for t in filtered_tracks if matches_decade(t['year'], dec)]
            if not dec_tracks:
                print("WARNING: Skipping decade playlist '{}' - 0 tracks match".format(dec))
                skipped_decades.append(dec)
                continue
            
            p_name = "Epochs - {}".format(dec)
            ids = [t['pid'] for t in dec_tracks]
            create_itunes_playlist(p_name, ids)
            created_playlists.append((p_name, len(ids)))

        # Summary message
        msg = ""
        if created_playlists:
            msg += "Successfully created playlists:\n"
            for name, count in created_playlists:
                msg += "- {} ({} tracks)\n".format(name, count)
        if skipped_decades:
            if msg: msg += "\n"
            msg += "Skipped decades (0 tracks match):\n"
            for dec in skipped_decades:
                msg += "- {}\n".format(dec)

        if not msg:
            msg = "No playlists were created."
            
        tkMessageBox.showinfo("Playlist Generation Summary", msg)
