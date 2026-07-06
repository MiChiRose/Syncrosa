# -*- coding: utf-8 -*-
import json
import os
import locale
import tempfile

try:
    unicode
except NameError:
    unicode = str

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

def _flag_value_enabled(value):
    if not value:
        return False
    return str(value).strip().lower() in ("1", "yes", "true", "on", "debug")

def desktop_debug_logs_enabled():
    return (
        _flag_value_enabled(os.environ.get("SYNCROSA_DESKTOP_DEBUG")) or
        _flag_value_enabled(os.environ.get("SYNCROSA_DEV_LOGS")) or
        bool(CONFIG_DATA.get("developer_desktop_logs", False))
    )

def save_config(config):
    global CONFIG_DATA
    CONFIG_DATA = config
    directory = os.path.dirname(CONFIG_FILE) or "."
    fd, tmp_path = tempfile.mkstemp(prefix=".syncrosa.", suffix=".tmp", dir=directory)
    try:
        try:
            os.chmod(tmp_path, 0o600)
        except:
            pass
        data = json.dumps(config, ensure_ascii=False, indent=2)
        if isinstance(data, unicode):
            data = data.encode("utf-8")
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.rename(tmp_path, CONFIG_FILE)
        try:
            os.chmod(CONFIG_FILE, 0o600)
        except:
            pass
    except:
        try:
            os.close(fd)
        except:
            pass
        try:
            os.remove(tmp_path)
        except:
            pass
        raise
