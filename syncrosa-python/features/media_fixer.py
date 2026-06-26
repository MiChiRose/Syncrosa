# -*- coding: utf-8 -*-
from __future__ import print_function, absolute_import
import re
import json
import time
from collections import Counter
from core.itunes_bridge import run_as
from core.network import make_request
import sys
try:
    from urllib import quote as q_f
except ImportError:
    from urllib.parse import quote as q_f

def norm_text(t):
    if not t: return u""
    if isinstance(t, bytes):
        t = t.decode('utf-8', 'ignore')
    # Normalize text by removing special characters and lowercasing
    return u' '.join(re.sub(r'[^a-zA-Z0-9а-яА-ЯёЁ\s]', u' ', t).lower().split())

def find_apple_metadata(artist, title):
    clean_t = re.sub(r'[\(\[].*?[\)\]]', '', title).strip()
    try:
        search_term = u"{0} {1}".format(artist, clean_t).encode('utf-8')
        url = "https://itunes.apple.com/search?term={0}&media=music&limit=1".format(q_f(search_term))
        ok, result = make_request(url, {})
        if ok:
            data = json.loads(result)
            if data.get('resultCount', 0) > 0:
                res = data['results'][0]
                return {
                    'alb': res.get('collectionName'),
                    'gen': res.get('primaryGenreName'),
                    'yr': res.get('releaseDate', '')[:4]
                }
    except Exception as e:
        print("Apple Search Error:", e)
    return None

def get_merge_candidates(progress_cb, check_run):
    script = 'set out to ""\ntell application "iTunes"\nset trks to every track of library playlist 1\nrepeat with t in trks\ntry\nset out to out & (persistent ID of t) & "|" & (artist of t) & "|" & (album of t) & "\n"\nend try\nend repeat\nend tell\nreturn out'
    raw = run_as(script)
    
    groups = {}
    lines = raw.split('\n')
    for line in lines:
        if not check_run(): return []
        if '|' in line:
            parts = line.split('|')
            if len(parts) < 3: continue
            p, art, alb = parts[0], parts[1], parts[2]
            if not alb: continue
            k = (art.lower(), norm_text(alb))
            if k not in groups: groups[k] = []
            groups[k].append({'pid':p, 'alb':alb})

    to_fix = []
    for k, trks in groups.items():
        if not check_run(): return []
        variants = list(set([t['alb'] for t in trks]))
        if len(variants) > 1:
            main = Counter([t['alb'] for t in trks]).most_common(1)[0][0]
            to_fix.append({'main': main, 'targets': [t for t in trks if t['alb'] != main]})
            
    return to_fix

def apply_merge(to_fix, progress_cb, status_cb, check_run, checked_tags):
    if "album" not in checked_tags:
        progress_cb(len(to_fix), len(to_fix))
        return
    for i, item in enumerate(to_fix):
        if not check_run(): break
        status_cb(u"Merging: " + item['main'][:45])
        for t in item['targets']:
            if not check_run(): break
            try:
                run_as(u'tell application "iTunes" to set album of (some track whose persistent ID is "{0}") to "{1}"'.format(t['pid'], item['main'].replace('"', '\\"')).encode('utf-8'))
            except Exception as e:
                print("Error merging track:", t['pid'], e)
        progress_cb(i + 1, len(to_fix))

def run_metadata_fix(progress_cb, status_cb, check_run, checked_tags):
    count_script = 'tell application "iTunes" to count tracks of library playlist 1'
    try:
        total = int(run_as(count_script))
    except:
        total = 0
            
    for i in range(1, total + 1):
        if not check_run(): break
        
        try:
            get_script = u'''tell application "iTunes"
                try
                    set t to track {0} of library playlist 1
                    set pid to persistent ID of t
                    set art to artist of t
                    set nm to name of t
                    
                    set alb to ""
                    try
                        set alb to album of t
                    end try
                    
                    set gen to ""
                    try
                        set gen to genre of t
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
                    
                    return pid & "|" & art & "|" & nm & "|" & alb & "|" & gen & "|" & trkNum & "|" & hasLyr
                end try
            end tell
            return "SKIP"'''.format(i)
            
            track_raw = run_as(get_script.encode('utf-8'))
            if track_raw == "SKIP" or "|" not in track_raw: 
                progress_cb(i, total)
                continue
            
            parts = track_raw.split("|")
            if len(parts) < 7:
                progress_cb(i, total)
                continue
                
            pid, artist, title, alb, gen, trk_num, has_lyr = parts[0], parts[1], parts[2], parts[3], parts[4], parts[5], parts[6]
            
            should_fix = False
            if "album" in checked_tags and (not alb or alb == "Unknown Album"):
                should_fix = True
            if "genre" in checked_tags and (not gen or gen.lower() in ["unknown", "unknown genre"]):
                should_fix = True
            if "track_number" in checked_tags and (not trk_num or trk_num == "0"):
                should_fix = True
            if "lyrics" in checked_tags and has_lyr == "0":
                should_fix = True
            if "title" in checked_tags and (not title or title.lower().startswith("track") or title.lower().startswith("unknown")):
                should_fix = True
            if "artist" in checked_tags and (not artist or artist.lower() in ["unknown artist", "unknown"]):
                should_fix = True
                
            if not should_fix:
                progress_cb(i, total)
                continue
                
            status_cb(u"Updating: " + title[:45])
            
            info = None
            if any(t in checked_tags for t in ["album", "genre", "track_number", "title", "artist"]):
                info = find_apple_metadata(artist, title)
                
            updates = []
            if info:
                if "album" in checked_tags and info.get('alb') and (not alb or alb == "Unknown Album"):
                    updates.append(u'set album of t to "{0}"'.format(info['alb'].replace('"', '\\"')))
                if "genre" in checked_tags and info.get('gen') and (not gen or gen.lower() in ["unknown", "unknown genre"]):
                    updates.append(u'set genre of t to "{0}"'.format(info['gen'].replace('"', '\\"')))
                if "track_number" in checked_tags and info.get('track_number') and (not trk_num or trk_num == "0"):
                    updates.append(u'set track number of t to {0}'.format(info['track_number']))
                if "title" in checked_tags and info.get('title') and (not title or title.lower().startswith("track") or title.lower().startswith("unknown")):
                    updates.append(u'set name of t to "{0}"'.format(info['title'].replace('"', '\\"')))
                if "artist" in checked_tags and info.get('artist') and (not artist or artist.lower() in ["unknown artist", "unknown"]):
                    updates.append(u'set artist of t to "{0}"'.format(info['artist'].replace('"', '\\"')))
                    
            if "lyrics" in checked_tags and has_lyr == "0":
                from features.lyrics_service import fetch_lyrics
                lyrics_text = fetch_lyrics(artist, title)
                if lyrics_text:
                    escaped_lyr = lyrics_text.replace('\\', '\\\\').replace('"', '\\"').replace('\r', '\\r').replace('\n', '\\r')
                    updates.append(u'set lyrics of t to "{0}"'.format(escaped_lyr))
                    
            if updates:
                u_s = u'tell application "iTunes"\ntry\nset t to (some track whose persistent ID is "{0}")\n{1}\nreturn "OK"\nend try\nend tell'.format(pid, u"\n".join(updates))
                run_as(u_s.encode('utf-8'))
                
        except Exception as e:
            print("Error fixing track metadata for index {}: {}".format(i, e))
            
        progress_cb(i, total)
        time.sleep(0.05)

