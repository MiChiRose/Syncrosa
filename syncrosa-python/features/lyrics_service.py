# -*- coding: utf-8 -*-
from __future__ import absolute_import
import json
import sys
from core.network import make_request
try:
    from urllib import quote as q_f
except ImportError:
    from urllib.parse import quote as q_f

def fetch_lyrics(artist, title):
    if not artist or not title:
        return None
    try:
        if sys.version_info[0] < 3:
            if isinstance(artist, unicode):
                artist = artist.encode('utf-8')
            if isinstance(title, unicode):
                title = title.encode('utf-8')
        else:
            if isinstance(artist, bytes):
                artist = artist.decode('utf-8')
            if isinstance(title, bytes):
                title = title.decode('utf-8')
                
        # Clean artist and title for safety
        url = "https://api.lyrics.ovh/v1/{0}/{1}".format(q_f(artist), q_f(title))
        ok, res = make_request(url, {}, timeout_sec=5)
        if ok:
            data = json.loads(res)
            lyrics = data.get("lyrics")
            if lyrics:
                if isinstance(lyrics, bytes):
                    lyrics = lyrics.decode('utf-8', 'ignore')
                return lyrics.strip()
    except Exception:
        pass
    return None
