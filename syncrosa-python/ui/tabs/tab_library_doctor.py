# -*- coding: utf-8 -*-
from __future__ import absolute_import
try:
    import Tkinter as tk
    import ttk
except ImportError:
    import tkinter as tk
    from tkinter import ttk
import threading
import os

from core.itunes_bridge import run_as, get_library_track_count
from core.operation_history import record_operation


class LibraryDoctorTab(tk.Frame):
    def __init__(self, parent, master_app):
        tk.Frame.__init__(self, parent, bg="#ECECEC", borderwidth=0, highlightthickness=0)
        self.master_app = master_app
        self.running = False
        self.build_ui()

    def build_ui(self):
        tk.Label(self, text="Library Doctor", font=("system", 15, "bold"), bg="#ECECEC").pack(pady=(18, 8))
        self.tool_var = tk.StringVar(value="Cover Audit")
        self.tool = ttk.Combobox(self, textvariable=self.tool_var, values=["Cover Restore", "Cover Audit", "Library Audit", "iPod Report", "Broken Tracks"], state="readonly", width=24)
        self.tool.pack(pady=6)
        self.run_btn = ttk.Button(self, text="Run Doctor", command=self.run, width=20)
        self.run_btn.pack(pady=6)
        self.progress = ttk.Progressbar(self, mode="determinate")
        self.progress.pack(fill=tk.X, padx=30, pady=6)
        self.log_box = tk.Text(self, height=18, bg="#000000", fg="#00FF55", font=("Monaco", 10), state="disabled")
        self.log_box.pack(fill=tk.BOTH, expand=True, padx=24, pady=12)

    def clear_log(self):
        self.log_box.config(state="normal")
        self.log_box.delete("1.0", tk.END)
        self.log_box.config(state="disabled")

    def log(self, text):
        self.log_box.config(state="normal")
        self.log_box.insert(tk.END, "> " + text + "\n")
        self.log_box.see(tk.END)
        self.log_box.config(state="disabled")

    def run(self):
        if self.running:
            return
        self.running = True
        self.run_btn.config(state="disabled")
        self.progress.config(value=0, maximum=1)
        self.clear_log()
        threading.Thread(target=self.worker).start()

    def worker(self):
        tool = self.tool_var.get()
        status = "OK"
        message = ""
        affected = 0
        try:
            self.after(0, lambda: self.log("Library Doctor started: " + tool))
            if tool == "Cover Restore":
                message = "Open Covers Optimizer and use Restore Original Covers. The doctor keeps restore writes in that dedicated tool."
                self.after(0, lambda: self.log(message))
            elif tool == "Cover Audit":
                script = u'''
set coverCount to 0
set trackCount to 0
tell application "iTunes"
    try
        set trks to every track of library playlist 1
        set trackCount to count of trks
        repeat with t in trks
            try
                if (count of artworks of t) > 0 then set coverCount to coverCount + 1
            end try
        end repeat
    end try
end tell
return (trackCount as text) & tab & (coverCount as text)
'''
                raw = run_as(script, timeout_sec=240)
                message = "Cover audit raw result: " + raw
                affected = 1
                self.after(0, lambda m=message: self.log(m))
            else:
                if tool in ("iPod Report", "Broken Tracks"):
                    refs = self.read_file_track_refs()
                    if tool == "iPod Report":
                        supported = set(["mp3", "m4a", "mp4", "aac", "wav", "aiff", "aif"])
                        unsupported = 0
                        missing = 0
                        long_names = 0
                        huge = 0
                        total_size = 0
                        for ref in refs:
                            path = ref.get("path", "")
                            ext = path.rsplit(".", 1)[-1].lower() if "." in path else ""
                            total_size += ref.get("size", 0)
                            if self._is_broken_path(path):
                                missing += 1
                            if ext and ext not in supported:
                                unsupported += 1
                            if len(os.path.basename(path)) > 80:
                                long_names += 1
                            if ref.get("size", 0) > 100 * 1024 * 1024:
                                huge += 1
                        warnings = unsupported + missing + long_names + huge
                        message = "iPod report complete. Scanned: {}. Warnings: {}.".format(len(refs), warnings)
                        affected = warnings
                        status = "WARN" if warnings else "OK"
                        self.after(0, lambda: self.log("file tracks scanned: {}".format(len(refs))))
                        self.after(0, lambda: self.log("unsupported format warnings: {}".format(unsupported)))
                        self.after(0, lambda: self.log("missing/unreadable files: {}".format(missing)))
                        self.after(0, lambda: self.log("long filenames (>80 chars): {}".format(long_names)))
                        self.after(0, lambda: self.log("large files (>100 MB): {}".format(huge)))
                    else:
                        broken = [r for r in refs if self._is_broken_path(r.get("path"))]
                        message = "Broken tracks scan complete. Missing files: {}.".format(len(broken))
                        affected = len(broken)
                        status = "WARN" if broken else "OK"
                        self.after(0, lambda: self.log("file tracks scanned: {}".format(len(refs))))
                        for ref in broken[:80]:
                            self.after(0, lambda r=ref: self.log("missing: {} - {}".format(r.get("artist", ""), r.get("name", ""))))
                    return
                count, err = get_library_track_count()
                if count >= 0:
                    message = "iTunes library track count: {}".format(count)
                    affected = count
                else:
                    status = "WARN"
                    message = "Could not read iTunes library. " + (err or "")
                self.after(0, lambda m=message: self.log(m))
        except Exception as e:
            status = "FAIL"
            message = str(e)
            self.after(0, lambda: self.log("ERROR: " + message))
        finally:
            record_operation("Library Doctor", tool, status, message, affected)
            self.after(0, lambda: self.progress.config(value=1, maximum=1))
            self.after(0, lambda: self.log("Library Doctor finished."))
            self.after(0, lambda: self.run_btn.config(state="normal"))
            self.running = False

    def _is_broken_path(self, path):
        return not path or not os.path.exists(path) or not os.access(path, os.R_OK)

    def read_file_track_refs(self):
        count_script = u'''
tell application "iTunes"
    try
        return (count of every file track of library playlist 1) as text
    on error
        return "0"
    end try
end tell
'''
        total = 0
        try:
            total = int(run_as(count_script, timeout_sec=120) or "0")
        except:
            total = 0

        handler = u'''
on syncrosaCleanField(v)
    try
        set s to v as text
    on error
        set s to ""
    end try
    set oldDelims to AppleScript's text item delimiters
    set AppleScript's text item delimiters to tab
    set parts to text items of s
    set AppleScript's text item delimiters to " "
    set s to parts as text
    set AppleScript's text item delimiters to linefeed
    set parts to text items of s
    set AppleScript's text item delimiters to " "
    set s to parts as text
    set AppleScript's text item delimiters to oldDelims
    return s
end syncrosaCleanField
'''
        body = u'''
set output to ""
tell application "iTunes"
    try
        set trks to every file track of library playlist 1
        repeat with trackIndex from {0} to {1}
            if trackIndex is greater than (count of trks) then exit repeat
            set t to item trackIndex of trks
            set nm to ""
            set art to ""
            set pth to ""
            set sz to "0"
            try
                set nm to name of t as text
            end try
            try
                set art to artist of t as text
            end try
            try
                set sz to size of t as text
            end try
            try
                set loc to location of t
                if loc is not missing value then set pth to POSIX path of loc
            end try
            set output to output & my syncrosaCleanField(nm) & tab & my syncrosaCleanField(art) & tab & my syncrosaCleanField(pth) & tab & sz & linefeed
        end repeat
    end try
end tell
return output
'''
        refs = []
        chunk_size = 200
        for start in range(1, total + 1, chunk_size):
            end = min(start + chunk_size - 1, total)
            script = handler + body.format(start, end)
            raw = run_as(script, timeout_sec=120)
            for line in raw.split("\n"):
                parts = line.split("\t")
                if len(parts) >= 4:
                    try:
                        size = int(parts[3])
                    except:
                        size = 0
                    refs.append({"name": parts[0], "artist": parts[1], "path": parts[2], "size": size})
        return refs
