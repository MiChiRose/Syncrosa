# -*- coding: utf-8 -*-
import subprocess
import sys
import time

try:
    unicode
except NameError:
    unicode = str

FIELD_SEP = "\t"

SAFE_FIELD_HANDLER = u'''
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
    set AppleScript's text item delimiters to return
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

class AppleScriptError(Exception):
    pass

class AppleScriptTimeout(AppleScriptError):
    pass

def _to_text(value):
    if value is None:
        return u""
    if isinstance(value, unicode):
        return value
    return value.decode("utf-8", "replace")

def _as_literal(value):
    text = _to_text(value)
    text = text.replace(u"\\", u"\\\\")
    text = text.replace(u"\"", u"\\\"")
    text = text.replace(u"\r", u" ")
    text = text.replace(u"\n", u" ")
    text = text.replace(u"\t", u" ")
    return u'"' + text + u'"'

def _as_list_literal(values):
    return u"{" + u", ".join([_as_literal(value) for value in values]) + u"}"

def run_as(s, timeout_sec=120):
    script = _to_text(s)
    script_arg = script.encode("utf-8") if sys.version_info[0] < 3 else script
    p = subprocess.Popen(["osascript", "-e", script_arg], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    deadline = time.time() + timeout_sec
    while p.poll() is None:
        if time.time() >= deadline:
            try:
                p.kill()
            except:
                pass
            out, err = p.communicate()
            raise AppleScriptTimeout("osascript timed out after {0}s: {1}".format(timeout_sec, _to_text(err).strip()))
        time.sleep(0.05)

    out, err = p.communicate()
    stdout = _to_text(out).strip()
    stderr = _to_text(err).strip()
    if p.returncode != 0:
        raise AppleScriptError("osascript failed ({0}): {1}".format(p.returncode, stderr or stdout))
    return stdout

def get_library_track_count():
    try:
        script = u'''
        tell application "iTunes"
            set trackCount to -1
            set fileTrackCount to -1
            set lastError to ""
            try
                set trackCount to count every track of library playlist 1
            on error errMsg number errNum
                set lastError to (errNum as text) & " " & errMsg
            end try
            try
                set fileTrackCount to count every file track of library playlist 1
            on error errMsg number errNum
                if lastError is "" then set lastError to (errNum as text) & " " & errMsg
            end try
            if trackCount < 0 and fileTrackCount < 0 then
                return "ERROR" & tab & lastError
            end if
            if fileTrackCount > trackCount then set trackCount to fileTrackCount
            return "OK" & tab & (trackCount as text)
        end tell
        '''
        result = run_as(script, timeout_sec=45)
        parts = result.split(FIELD_SEP)
        if len(parts) >= 2 and parts[0] == "OK":
            return int(parts[1]), None
        if len(parts) >= 2 and parts[0] == "ERROR":
            return -1, parts[1]
        return -1, "Could not read iTunes library count."
    except Exception as e:
        return -1, str(e)

def get_library(progress_cb, check_run):
    total, err = get_library_track_count()
    if total <= 0:
        return []
    
    library = []
    chunk_size = 200
    for i in range(1, total + 1, chunk_size):
        if not check_run(): break
        end_idx = min(i + chunk_size - 1, total)
        script = SAFE_FIELD_HANDLER + u'''
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
                    set out to out & pid & tab & my syncrosaCleanField(art) & tab & my syncrosaCleanField(nm) & tab & my syncrosaCleanField(gen) & tab & yr & linefeed
                end if
            end repeat
        end tell
        return out
        '''.format(i, end_idx)
        
        res = run_as(script, timeout_sec=180)
        for line in res.split('\n'):
            if FIELD_SEP in line:
                library.append(line.strip())
        progress_cb(end_idx, total)
    return library

def create_itunes_playlist(name, ids_list):
    clean_ids = []
    for tid in ids_list or []:
        if tid:
            clean_ids.append(_to_text(tid))

    if not clean_ids:
        return "0"

    script = u'''
    tell application "iTunes"
        set plName to {0}
        set addedCount to 0
        set idList to {1}
        set tracksToAdd to {{}}

        repeat with tid in idList
            set tidText to (contents of tid) as text
            try
                set trk to (some track of library playlist 1 whose persistent ID is tidText)
                set end of tracksToAdd to trk
            end try
        end repeat

        if (count of tracksToAdd) is 0 then return "0"

        if not (exists user playlist plName) then
            make new user playlist with properties {{name:plName}}
        end if
        set pl to user playlist plName
        delete every track of pl

        repeat with trk in tracksToAdd
            try
                duplicate (contents of trk) to pl
                set addedCount to addedCount + 1
            end try
        end repeat
        return addedCount as string
    end tell
    '''.format(_as_literal(name), _as_list_literal(clean_ids))
    return run_as(script, timeout_sec=300)

def import_files_as_playlist(name, file_paths, clear_playlist=True):
    clean_paths = []
    for path in file_paths or []:
        if path:
            clean_paths.append(_to_text(path))
    if not clean_paths:
        return 0

    clear_line = "delete every track of pl" if clear_playlist else ""
    script = u'''
    tell application "iTunes"
        set plName to {0}
        set fileList to {1}
        set addedCount to 0
        if not (exists user playlist plName) then
            make new user playlist with properties {{name:plName}}
        end if
        set pl to user playlist plName
        {2}
        repeat with filePath in fileList
            try
                set importedTrack to add (POSIX file ((contents of filePath) as text))
                try
                    duplicate importedTrack to pl
                    set addedCount to addedCount + 1
                on error
                    try
                        duplicate item 1 of importedTrack to pl
                        set addedCount to addedCount + 1
                    end try
                end try
            end try
        end repeat
        return addedCount as string
    end tell
    '''.format(_as_literal(name), _as_list_literal(clean_paths), clear_line)
    return int(run_as(script, timeout_sec=300) or "0")

def get_library_for_duplicates(progress_cb, check_run):
    total, err = get_library_track_count()
    if total <= 0:
        return []
    
    library = []
    chunk_size = 150
    for i in range(1, total + 1, chunk_size):
        if not check_run(): break
        end_idx = min(i + chunk_size - 1, total)
        script = SAFE_FIELD_HANDLER + u'''
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
                    
                    set out to out & pid & tab & my syncrosaCleanField(art) & tab & my syncrosaCleanField(nm) & tab & my syncrosaCleanField(knd) & tab & sz & tab & my syncrosaCleanField(alb) & tab & my syncrosaCleanField(gen) & tab & yr & tab & trkNum & tab & hasLyr & tab & hasArt & linefeed
                end try
            end repeat
        end tell
        return out
        '''.format(i, end_idx)
        
        res = run_as(script, timeout_sec=180)
        for line in res.split('\n'):
            if FIELD_SEP in line:
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
    return run_as(script, timeout_sec=120)

def get_library_for_offline_playlist(progress_cb, check_run):
    total, err = get_library_track_count()
    if total <= 0:
        return []
    
    library = []
    chunk_size = 150
    for i in range(1, total + 1, chunk_size):
        if not check_run(): break
        end_idx = min(i + chunk_size - 1, total)
        script = SAFE_FIELD_HANDLER + u'''
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
                    
                    set out to out & pid & tab & my syncrosaCleanField(gen) & tab & yr & tab & rt & tab & hasArt & linefeed
                end try
            end repeat
        end tell
        return out
        '''.format(i, end_idx)
        
        res = run_as(script, timeout_sec=180)
        for line in res.split('\n'):
            if FIELD_SEP in line:
                library.append(line.strip())
        progress_cb(end_idx, total)
    return library
