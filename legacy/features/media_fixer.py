# -*- coding: utf-8 -*-
from __future__ import print_function, absolute_import
import re
import json
import time
from collections import Counter
from core.itunes_bridge import run_as
from core.network import make_request
try:
    import urllib
    q_f = urllib.quote
except ImportError:
    import urllib.parse
    q_f = urllib.parse.quote

def norm_text(t):
    if not t: return u""
    if isinstance(t, str): t = t.decode('utf-8')
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

def apply_merge(to_fix, progress_cb, status_cb, check_run):
    for i, item in enumerate(to_fix):
        if not check_run(): break
        status_cb(u"Merging: " + item['main'][:45])
        for t in item['targets']:
            if not check_run(): break
            run_as('tell application "iTunes" to set album of (some track whose persistent ID is "{0}") to "{1}"'.format(t['pid'], item['main'].replace('"', '\\"')))
        progress_cb(i + 1, len(to_fix))

def run_metadata_fix(progress_cb, status_cb, check_run):
    count_script = 'tell application "iTunes" to count tracks of library playlist 1'
    try:
        total = int(run_as(count_script))
    except:
        total = 0
            
    for i in range(1, total + 1):
        if not check_run(): break
        
        get_script = 'tell application "iTunes"\ntry\nset t to track {0} of library playlist 1\nset alb to album of t\nif alb is "" or alb is "Unknown Album" or alb is missing value then\nreturn (persistent ID of t) & "|" & (artist of t) & "|" & (name of t)\nend if\nend try\nend tell\nreturn "SKIP"'.format(i)
        track_raw = run_as(get_script)
        if track_raw == "SKIP" or "|" not in track_raw: 
            progress_cb(i, total)
            continue
        
        parts = track_raw.split("|", 2)
        if len(parts) < 3: 
            progress_cb(i, total)
            continue
            
        pid, artist, title = parts[0], parts[1], parts[2]
        status_cb(u"Updating: " + title[:45])
        
        info = find_apple_metadata(artist, title)
        if info:
            updates = []
            if info.get('alb'): updates.append('set album of t to "{0}"'.format(info['alb'].replace('"', '\\"')))
            if info.get('yr'): updates.append('set year of t to {0}'.format(info['yr']))
            if info.get('gen'): updates.append('set genre of t to "{0}"'.format(info['gen'].replace('"', '\\"')))
            if updates:
                u_s = u'tell application "iTunes"\ntry\nset t to (some track whose persistent ID is "{0}")\n{1}\nreturn "OK"\nend try\nend tell'.format(pid, u"\n".join(updates))
                run_as(u_s.encode('utf-8'))
        
        progress_cb(i, total)
        time.sleep(0.05)
