#!/bin/bash

# --- SETTINGS ---
APP_NAME="iTunesMediaInfoFix"
APP_PATH="$HOME/Desktop/$APP_NAME.app"
CUSTOM_ICON="$HOME/Desktop/folder-wood.icns"

echo "--- Building ADVANCED PORTABLE Version of $APP_NAME.app ---"

# 0. Clean old version
rm -rf "$APP_PATH"

# 1. CREATE COMPREHENSIVE LOGIC + GUI (PYTHON 2.7 Compatible)
cat << 'EOF' > /tmp/app_logic.py
# -*- coding: utf-8 -*-
from __future__ import print_function
import subprocess, re, sys, time, json, os
import Tkinter as tk
import ttk
import threading

# Configuration for 10.9 (Python 2.7)
if sys.version_info[0] < 3:
    import urllib
    q_f = urllib.quote
    reload(sys)
    sys.setdefaultencoding('utf-8')
else:
    import urllib.parse
    q_f = urllib.parse.quote

def run_as(s):
    p = subprocess.Popen(['osascript', '-e', s], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return p.communicate()[0].decode('utf-8').strip()

class FixerApp:
    def __init__(self, root):
        self.root = root
        self.root.title("iTunes Media Info Fixer")
        self.root.geometry("500x220")
        self.root.resizable(False, False)
        
        # Center Window
        window_width = 500
        window_height = 220
        screen_width = root.winfo_screenwidth()
        screen_height = root.winfo_screenheight()
        position_top = int(screen_height/2 - window_height/2)
        position_right = int(screen_width/2 - window_width/2)
        root.geometry("{}x{}+{}+{}".format(window_width, window_height, position_right, position_top))

        # Styling
        s = ttk.Style()
        s.theme_use('aqua') # Native Mac theme
        s.configure("TProgressbar", thickness=30) # THICKER progress bar

        self.label = tk.Label(root, text="Preparing Fixer...", font=("Helvetica", 13, "bold"))
        self.label.pack(pady=20)

        self.progress = ttk.Progressbar(root, orient="horizontal", length=400, mode="determinate", style="TProgressbar")
        self.progress.pack(pady=5)

        self.status = tk.Label(root, text="Waiting...", font=("Helvetica", 10))
        self.status.pack(pady=5)

        self.stop_btn = tk.Button(root, text="Stop Process", command=self.stop, fg="red", width=15)
        self.stop_btn.pack(pady=15)

        self.running = True
        self.thread = threading.Thread(target=self.start_process)
        self.thread.start()

    def stop(self):
        self.running = False
        self.label.config(text="Stopping Safely...")
        self.stop_btn.config(state="disabled")

    def start_process(self):
        try:
            # 1. MERGE PHASE
            self.root.after(0, lambda: self.label.config(text="Phase 1: Merging Duplicate Albums"))
            self.run_merge()
            
            if not self.running: return
            
            # 2. METADATA PHASE
            self.root.after(0, lambda: self.label.config(text="Phase 2: Updating All Metadata"))
            self.run_fix()
            
            if self.running:
                self.root.after(0, lambda: self.label.config(text="Success! Library is Restored."))
                self.root.after(0, lambda: self.status.config(text="Everything is up to date."))
                self.root.after(0, lambda: self.stop_btn.config(text="Done", state="normal", command=self.root.destroy, fg="black"))
        except Exception as e:
            self.handle_error(str(e))

    def handle_error(self, error_msg):
        desktop = os.path.join(os.path.expanduser("~"), "Desktop")
        log_file = os.path.join(desktop, "iTunesFix_Crash_Log.txt")
        with open(log_file, "w") as f:
            f.write("ERROR LOG\n----------\n" + error_msg)
        
        self.root.after(0, lambda: self.label.config(text="FATAL ERROR!", fg="red"))
        self.root.after(0, lambda: self.status.config(text="Log saved to Desktop. Please report on GitHub."))
        
        # Show Applescript Alert for the Log
        error_script = 'display dialog "The application crashed. A log file has been saved to your Desktop. Please open a GitHub issue with this file to help the developer." with title "Error" buttons {"OK"} with icon stop'
        run_as(error_script)

    def run_merge(self):
        script = 'set out to ""\ntell application "iTunes"\nset trks to every track of library playlist 1\nrepeat with t in trks\nset out to out & (persistent ID of t) & "|" & (artist of t) & "|" & (album of t) & "\n"\nend repeat\nend tell\nreturn out'
        raw = run_as(script)
        from collections import Counter
        
        def norm(t):
            if not t: return u""
            if isinstance(t, str): t = t.decode('utf-8')
            return u' '.join(re.sub(r'[^a-zA-Z0-9а-яА-ЯёЁ\s]', u' ', t).lower().split())

        groups = {}
        for line in raw.split('\n'):
            if '|' in line:
                parts = line.split('|')
                if len(parts) < 3: continue
                p, art, alb = parts[0], parts[1], parts[2]
                if not alb: continue
                k = (art.lower(), norm(alb))
                if k not in groups: groups[k] = []
                groups[k].append({'pid':p, 'alb':alb})

        to_fix = []
        for k, trks in groups.items():
            variants = list(set([t['alb'] for t in trks]))
            if len(variants) > 1:
                main = Counter([t['alb'] for t in trks]).most_common(1)[0][0]
                to_fix.append({'main': main, 'targets': [t for t in trks if t['alb'] != main]})

        if to_fix:
            self.progress["maximum"] = len(to_fix)
            for i, item in enumerate(to_fix):
                if not self.running: break
                self.root.after(0, lambda v=i: self.progress.step(1))
                self.root.after(0, lambda v=item['main']: self.status.config(text=u"Merging: " + v[:45]))
                for t in item['targets']:
                    run_as('tell application "iTunes" to set album of (some track whose persistent ID is "{0}") to "{1}"'.format(t['pid'], item['main'].replace('"', '\\"')))

    def run_fix(self):
        count_script = 'tell application "iTunes" to count tracks of library playlist 1'
        try:
            total = int(run_as(count_script))
        except:
            total = 0
            
        self.progress["value"] = 0
        self.progress["maximum"] = total

        for i in range(1, total + 1):
            if not self.running: break
            self.root.after(0, lambda: self.progress.step(1))
            
            get_script = 'tell application "iTunes"\ntry\nset t to track {0} of library playlist 1\nset alb to album of t\nif alb is "" or alb is "Unknown Album" or alb is missing value then\nreturn (persistent ID of t) & "|" & (artist of t) & "|" & (name of t)\nend if\nend try\nend tell\nreturn "SKIP"'.format(i)
            track_raw = run_as(get_script)
            if track_raw == "SKIP" or "|" not in track_raw: continue
            
            parts = track_raw.split("|", 2)
            if len(parts) < 3: continue
            pid, artist, title = parts[0], parts[1], parts[2]
            
            self.root.after(0, lambda v=title: self.status.config(text=u"Updating: " + v[:45]))
            
            info = self.find_apple(artist, title)
            if info:
                updates = []
                if info.get('alb'): updates.append('set album of t to "{0}"'.format(info['alb'].replace('"', '\\"')))
                if info.get('yr'): updates.append('set year of t to {0}'.format(info['yr']))
                if info.get('gen'): updates.append('set genre of t to "{0}"'.format(info['gen'].replace('"', '\\"')))
                if updates:
                    u_s = u'tell application "iTunes"\ntry\nset t to (some track whose persistent ID is "{0}")\n{1}\nreturn "OK"\nend try\nend tell'.format(pid, "\n".join(updates))
                    run_as(u_s.encode('utf-8'))
            time.sleep(0.05)

    def find_apple(self, artist, title):
        clean_t = re.sub(r'[\(\[].*?[\)\]]', '', title).strip()
        try:
            url = "https://itunes.apple.com/search?term={0}&media=music&limit=1".format(q_f(u"{0} {1}".format(artist, clean_t).encode('utf-8')))
            cmd = ['curl', '-s', '-k', url]
            p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            data = json.loads(p.communicate()[0])
            if data.get('resultCount', 0) > 0:
                res = data['results'][0]
                return {'alb': res.get('collectionName'), 'gen': res.get('primaryGenreName'), 'yr': res.get('releaseDate', '')[:4]}
        except: pass
        return None

if __name__ == "__main__":
    if "--analyze" in sys.argv:
        s = 'tell application "iTunes" to count (every track of library playlist 1 whose album is "" or album is missing value)'
        print(run_as(s))
    else:
        root = tk.Tk()
        app = FixerApp(root)
        root.mainloop()
EOF

# 2. CREATE CONTROL APPLESCRIPT WITH INTERNET CHECK
cat << 'EOF' > /tmp/main.applescript
set appName to "iTunesMediaInfoFix"

-- 1. Pre-flight Check: Internet
try
    do shell script "curl -s -k --head https://www.google.com | head -n 1"
on error
    display dialog "No Internet Connection Found!" & return & return & "This application requires an active internet connection to fetch metadata from Apple Servers. Please connect and try again." with title appName buttons {"Quit"} default button "Quit" with icon stop
    return
end try

display notification "Analyzing library..." with title appName
set resPath to POSIX path of (path to me) & "Contents/Resources/"

try
    set emptyCount to do shell script "python " & quoted form of (resPath & "app_logic.py") & " --analyze"
    
    display dialog "iTunes Analysis Complete!" & return & return & "Found tracks with missing info: " & emptyCount & return & return & "Would you like to start the restoration process?" with title appName buttons {"Cancel", "Start Restoration"} default button "Start Restoration"
    
    if button returned of result is "Start Restoration" then
        do shell script "python " & quoted form of (resPath & "app_logic.py")
    end if
on error err
    display dialog "System Error: " & err buttons {"OK"} with icon stop
end try
EOF

# 3. COMPILE
osacompile -o "$APP_PATH" /tmp/main.applescript
mv /tmp/app_logic.py "$APP_PATH/Contents/Resources/"

# 4. ICON
if [ -f "$CUSTOM_ICON" ]; then
    cp "$CUSTOM_ICON" "$APP_PATH/Contents/Resources/applet.icns"
fi

# 5. PERMISSIONS
chmod +x "$APP_PATH/Contents/MacOS/applet"
xattr -cr "$APP_PATH"

echo "--- PRODUCTION READY APP CREATED ---"
