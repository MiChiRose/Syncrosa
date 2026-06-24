# -*- coding: utf-8 -*-
import json
import os
import locale

CONFIG_FILE = os.path.expanduser("~/.syncrosa.json")

def get_sys_lang():
    try:
        loc = locale.getdefaultlocale()[0]
        if loc:
            if loc.startswith('ru'): return 'ru'
            if loc.startswith('be'): return 'be'
            if loc.startswith('ko'): return 'ko'
            if loc.startswith('ja'): return 'ja'
            if loc.startswith('zh'): return 'zh'
            if loc.startswith('de'): return 'de'
            if loc.startswith('pl'): return 'pl'
            if loc.startswith('et'): return 'et'
            if loc.startswith('es'): return 'es'
    except: pass
    return 'en'

def load_config():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r') as f:
                cfg = json.load(f)
                if "lang" not in cfg: cfg["lang"] = get_sys_lang()
                return cfg
        except: pass
    return {"provider": "Gemini", "api_key": "", "model": "google/gemini-2.0-flash-exp:free", "lang": get_sys_lang()}

CONFIG_DATA = load_config()

def save_config(config):
    global CONFIG_DATA
    CONFIG_DATA = config
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f)
