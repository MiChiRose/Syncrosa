# -*- coding: utf-8 -*-
import os
import json
from datetime import datetime
try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    Image = None

from core.itunes_bridge import FIELD_SEP, SAFE_FIELD_HANDLER, run_as

LAST_SCAN_TRACK_COUNT = None

def get_app_name():
    if os.path.exists("/Applications/iTunes.app") or os.path.exists("/System/Applications/iTunes.app"):
        return "iTunes"
    if os.path.exists("/System/Applications/Music.app"):
        return "Music"
    return "iTunes"

def get_last_scan_track_count():
    return LAST_SCAN_TRACK_COUNT

def get_backup_folder():
    home = os.path.expanduser("~")
    # In Python 2.7 on macOS, we need to decode path to unicode safely
    if isinstance(home, bytes):
        home = home.decode('utf-8', 'ignore')
    folder = os.path.join(home, "Documents", "AlbumCovers")
    if not os.path.exists(folder):
        os.makedirs(folder)
    return folder

def load_manifest():
    path = os.path.join(get_backup_folder(), "manifest.json")
    if os.path.exists(path):
        try:
            with open(path, "r") as f:
                return json.load(f)
        except:
            pass
    return {"manifest_version": 1, "backups": {}}

def save_manifest(manifest):
    path = os.path.join(get_backup_folder(), "manifest.json")
    tmp_path = path + ".tmp"
    try:
        with open(tmp_path, "w") as f:
            json.dump(manifest, f, indent=2)
        os.rename(tmp_path, path)
    except:
        try:
            os.remove(tmp_path)
        except:
            pass
        pass

def get_tracks_with_covers(progress_cb=None, check_run=None):
    global LAST_SCAN_TRACK_COUNT
    if check_run is None:
        check_run = lambda: True
    app_name = get_app_name()
    try:
        total = int(run_as('tell application "{0}" to count every track of library playlist 1'.format(app_name), timeout_sec=45))
    except:
        total = -1
    LAST_SCAN_TRACK_COUNT = total

    tracks = []
    if total <= 0:
        return tracks

    chunk_size = 100
    for start_idx in range(1, total + 1, chunk_size):
        if not check_run():
            break
        end_idx = min(start_idx + chunk_size - 1, total)
        script = SAFE_FIELD_HANDLER + u'''
    set out to ""
    tell application "{0}"
        try
            set trks to (tracks {1} thru {2} of library playlist 1)
            repeat with t in trks
                try
                    if exists artwork 1 of t then
                        set pid to persistent ID of t
                        set nm to name of t
                        set art to artist of t
                        set out to out & pid & tab & my syncrosaCleanField(nm) & tab & my syncrosaCleanField(art) & linefeed
                    end if
                end try
            end repeat
        end try
    end tell
    return out
    '''.format(app_name, start_idx, end_idx)

        res = run_as(script, timeout_sec=180)
        for line in res.split('\n'):
            if FIELD_SEP in line:
                parts = line.strip().split(FIELD_SEP, 2)
                if len(parts) >= 3:
                    tracks.append({"pid": parts[0], "title": parts[1], "artist": parts[2]})
        if progress_cb:
            progress_cb(end_idx, total)
    return tracks

def backup_cover(pid, title, artist, manifest=None, save=True):
    folder = get_backup_folder()
    owns_manifest = manifest is None
    if manifest is None:
        manifest = load_manifest()

    existing = manifest.get("backups", {}).get(pid)
    if existing:
        existing_path = os.path.join(folder, "{0}.{1}".format(pid, existing.get("original_format", "jpg")))
        if os.path.exists(existing_path):
            return True

    path_without_ext = os.path.join(folder, pid).replace('\\', '\\\\').replace('"', '\\"')
    
    script = u'''
    tell application "{0}"
        try
            set t to (some track whose persistent ID is "{1}")
            if exists artwork 1 of t then
                tell artwork 1 of t
                    set rawData to raw data
                    if format is JPEG picture then
                        set ext to "jpg"
                      else
                        set ext to "png"
                    end if
                    set w to width
                    set h to height
                end tell
                
                set destFile to POSIX file ("{2}." & ext)
                set fileRef to open for access destFile with write permission
                set eof fileRef to 0
                write rawData to fileRef starting at 0
                close access fileRef
                return ext & "|" & w & "|" & h
            else
                return "NO_ARTWORK"
            end if
        on error errMsg number errNum
            try
                close access fileRef
            end try
            return "ERROR: " & errNum & " - " & errMsg
        end try
    end tell
    '''.format(get_app_name(), pid, path_without_ext)
    
    res = run_as(script, timeout_sec=180)
    if not res or res == "NO_ARTWORK" or res.startswith("ERROR"):
        return False
        
    parts = res.split("|")
    if len(parts) >= 3:
        ext, w, h = parts[0], int(parts[1]), int(parts[2])
        date_str = datetime.now().isoformat()
        backups = manifest.get("backups")
        if backups is None:
            backups = {}
            manifest["backups"] = backups
        
        backups[pid] = {
            "title": title,
            "artist": artist,
            "original_format": ext,
            "original_width": w,
            "original_height": h,
            "backup_date": date_str
        }
        if save or owns_manifest:
            save_manifest(manifest)
        return True
    return False

def resize_image_file(source_path, target_size):
    if not HAS_PIL:
        raise RuntimeError("Pillow library is not installed. Optimization requires Pillow.")
    try:
        img = Image.open(source_path)
        # Compatibility with older Pillow versions
        resample_filter = Image.ANTIALIAS
        if hasattr(Image, "Resampling"):
            resample_filter = Image.Resampling.LANCZOS
            
        img.thumbnail((target_size, target_size), resample_filter)
        if img.mode != "RGB":
            img = img.convert("RGB")
            
        temp_path = source_path + "_temp.jpg"
        img.save(temp_path, format="JPEG", quality=85)
        return temp_path
    except Exception as e:
        print("Resize error: {0}".format(e))
        return None

def set_track_artwork(pid, image_path):
    esc_path = image_path.replace('\\', '\\\\').replace('"', '\\"')
    script = u'''
    tell application "{0}"
        try
            set t to (some track whose persistent ID is "{1}")
            set fileAlias to (POSIX file "{2}") as alias
            set imgData to read fileAlias as picture
            
            tell t
                try
                    set data of artwork 1 to imgData
                on error
                    make new artwork at t with properties {{data:imgData}}
                end try
            end tell
            return "SUCCESS"
        on error errMsg number errNum
            return "ERROR: " & errNum & " - " & errMsg
        end try
    end tell
    '''.format(get_app_name(), pid, esc_path)
    
    res = run_as(script, timeout_sec=180)
    return res == "SUCCESS"

def optimize_cover(pid, target_size, manifest=None):
    if manifest is None:
        manifest = load_manifest()
    info = manifest["backups"].get(pid)
    if not info:
        return False
        
    ext = info.get("original_format", "jpg")
    orig_path = os.path.join(get_backup_folder(), "{0}.{1}".format(pid, ext))
    if not os.path.exists(orig_path):
        return False
        
    w = info.get("original_width", 0)
    h = info.get("original_height", 0)
    
    if w <= target_size and h <= target_size:
        return set_track_artwork(pid, orig_path)
        
    temp_path = resize_image_file(orig_path, target_size)
    if not temp_path:
        return False
        
    success = set_track_artwork(pid, temp_path)
    try:
        os.remove(temp_path)
    except:
        pass
    return success

def restore_cover(pid, manifest=None):
    if manifest is None:
        manifest = load_manifest()
    info = manifest["backups"].get(pid)
    if not info:
        return False
        
    ext = info.get("original_format", "jpg")
    orig_path = os.path.join(get_backup_folder(), "{0}.{1}".format(pid, ext))
    if not os.path.exists(orig_path):
        return False
        
    return set_track_artwork(pid, orig_path)
