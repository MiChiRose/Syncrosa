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

from core.itunes_bridge import run_as

def get_app_name():
    return "Music" if os.path.exists("/System/Applications/Music.app") else "iTunes"

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
    try:
        with open(path, "w") as f:
            json.dump(manifest, f, indent=2)
    except:
        pass

def get_tracks_with_covers():
    script = u'''
    set out to ""
    tell application "{0}"
        try
            set trks to every track of library playlist 1
            repeat with t in trks
                try
                    if exists artwork 1 of t then
                        set pid to persistent ID of t
                        set nm to name of t
                        set art to artist of t
                        set out to out & pid & "|" & nm & "|" & art & "\\n"
                    end if
                end try
            end repeat
        end try
    end tell
    return out
    '''.format(get_app_name())
    
    res = run_as(script.encode('utf-8'))
    tracks = []
    for line in res.split('\n'):
        if "|" in line:
            parts = line.strip().split("|", 2)
            if len(parts) >= 3:
                tracks.append({"pid": parts[0], "title": parts[1], "artist": parts[2]})
    return tracks

def backup_cover(pid, title, artist):
    folder = get_backup_folder()
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
    
    res = run_as(script.encode('utf-8'))
    if not res or res == "NO_ARTWORK" or res.startswith("ERROR"):
        return False
        
    parts = res.split("|")
    if len(parts) >= 3:
        ext, w, h = parts[0], int(parts[1]), int(parts[2])
        
        manifest = load_manifest()
        date_str = datetime.now().isoformat()
        
        manifest["backups"][pid] = {
            "title": title,
            "artist": artist,
            "original_format": ext,
            "original_width": w,
            "original_height": h,
            "backup_date": date_str
        }
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
                delete every artwork
                set data of artwork 1 to imgData
            end tell
            return "SUCCESS"
        on error errMsg number errNum
            return "ERROR: " & errNum & " - " & errMsg
        end try
    end tell
    '''.format(get_app_name(), pid, esc_path)
    
    res = run_as(script.encode('utf-8'))
    return res == "SUCCESS"

def optimize_cover(pid, target_size):
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

def restore_cover(pid):
    manifest = load_manifest()
    info = manifest["backups"].get(pid)
    if not info:
        return False
        
    ext = info.get("original_format", "jpg")
    orig_path = os.path.join(get_backup_folder(), "{0}.{1}".format(pid, ext))
    if not os.path.exists(orig_path):
        return False
        
    return set_track_artwork(pid, orig_path)
