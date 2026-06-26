# -*- coding: utf-8 -*-
import subprocess

def run_as(s):
    if isinstance(s, bytes):
        s = s.decode('utf-8')
    p = subprocess.Popen(['osascript', '-e', s], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return p.communicate()[0].decode('utf-8').strip()

def get_library(progress_cb, check_run):
    try:
        total = int(run_as('tell application "iTunes" to count every track'))
    except:
        return []
    
    library = []
    chunk_size = 200
    for i in range(1, total + 1, chunk_size):
        if not check_run(): break
        end_idx = min(i + chunk_size - 1, total)
        script = u'''
        set out to ""
        tell application "iTunes"
            set trks to (tracks {0} thru {1} of library playlist 1)
            repeat with t in trks
                set pid to ""
                set art to ""
                set nm to ""
                set gen to ""
                set yr to ""
                try
                    set pid to persistent ID of t
                    set art to artist of t
                    set nm to name of t
                end try
                try
                    set gen to genre of t
                end try
                try
                    set yr to year of t
                end try
                if pid is not "" and art is not "" and nm is not "" then
                    set out to out & pid & "|" & art & "|" & nm & "|" & gen & "|" & yr & "\\n"
                end if
            end repeat
        end tell
        return out
        '''.format(i, end_idx)
        
        res = run_as(script)
        for line in res.split('\n'):
            if "|" in line:
                library.append(line.strip())
        progress_cb(end_idx, total)
    return library

def create_itunes_playlist(name, ids_list):
    script = u'''
    tell application "iTunes"
        set plName to "{0}"
        if not (exists user playlist plName) then
            make new user playlist with properties {{name:plName}}
        end if
        set pl to user playlist plName
        delete every track of pl
        
        set addedCount to 0
        set idList to {1}
        
        repeat with tid in idList
            try
                set trk to (some track of library playlist 1 whose persistent ID is tid)
                duplicate trk to pl
                set addedCount to addedCount + 1
            end try
        end repeat
        return addedCount as string
    end tell
    '''.format(name.replace('"', '\\"'), '{"' + '", "'.join(ids_list) + '"}')
    return run_as(script.encode('utf-8'))

def get_library_for_duplicates(progress_cb, check_run):
    try:
        total = int(run_as('tell application "iTunes" to count every track'))
    except:
        return []
    
    library = []
    chunk_size = 150
    for i in range(1, total + 1, chunk_size):
        if not check_run(): break
        end_idx = min(i + chunk_size - 1, total)
        script = u'''
        set out to ""
        tell application "iTunes"
            set trks to (tracks {0} thru {1} of library playlist 1)
            repeat with t in trks
                try
                    set pid to persistent ID of t
                    set art to artist of t
                    set nm to name of t
                    set knd to kind of t
                    set sz to size of t as string
                    
                    set alb to ""
                    try
                        set alb to album of t
                    end try
                    
                    set gen to ""
                    try
                        set gen to genre of t
                    end try
                    
                    set yr to ""
                    try
                        set yr to year of t as string
                    end try
                    
                    set trkNum to "0"
                    try
                        set trkNum to track number of t as string
                    end try
                    
                    set hasLyr to "0"
                    try
                        set lyr to lyrics of t
                        if lyr is not missing value and lyr is not "" then
                            set hasLyr to "1"
                        end if
                    end try
                    
                    set hasArt to "0"
                    try
                        if (count of artworks of t) > 0 then
                            set hasArt to "1"
                        end if
                    end try
                    
                    set out to out & pid & "|" & art & "|" & nm & "|" & knd & "|" & sz & "|" & alb & "|" & gen & "|" & yr & "|" & trkNum & "|" & hasLyr & "|" & hasArt & "\\n"
                end try
            end repeat
        end tell
        return out
        '''.format(i, end_idx)
        
        res = run_as(script.encode('utf-8'))
        for line in res.split('\n'):
            if "|" in line:
                library.append(line.strip())
        progress_cb(end_idx, total)
    return library

def delete_track_by_id(pid):
    script = u'''
    tell application "iTunes"
        try
            set trk to (some track of library playlist 1 whose persistent ID is "{0}")
            delete trk
            return "OK"
        on error e
            return e
        end try
    end tell
    '''.format(pid)
    return run_as(script.encode('utf-8'))

def get_library_for_offline_playlist(progress_cb, check_run):
    try:
        total = int(run_as('tell application "iTunes" to count every track'))
    except:
        return []
    
    library = []
    chunk_size = 150
    for i in range(1, total + 1, chunk_size):
        if not check_run(): break
        end_idx = min(i + chunk_size - 1, total)
        script = u'''
        set out to ""
        tell application "iTunes"
            set trks to (tracks {0} thru {1} of library playlist 1)
            repeat with t in trks
                try
                    set pid to persistent ID of t
                    
                    set gen to ""
                    try
                        set gen to genre of t
                    end try
                    
                    set yr to ""
                    try
                        set yr to year of t as string
                    end try
                    
                    set rt to "0"
                    try
                        set rt to rating of t as string
                    end try
                    
                    set hasArt to "0"
                    try
                        if (count of artworks of t) > 0 then
                            set hasArt to "1"
                        end if
                    end try
                    
                    set out to out & pid & "|" & gen & "|" & yr & "|" & rt & "|" & hasArt & "\\n"
                end try
            end repeat
        end tell
        return out
        '''.format(i, end_idx)
        
        res = run_as(script.encode('utf-8'))
        for line in res.split('\n'):
            if "|" in line:
                library.append(line.strip())
        progress_cb(end_idx, total)
    return library


