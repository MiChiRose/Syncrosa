# -*- coding: utf-8 -*-
from __future__ import absolute_import
import json
import os
import threading
import time
import uuid

from core.storage_paths import application_support_dir, ensure_dir


HISTORY_FILE = os.path.join(application_support_dir(), "operation-history.json")
MAX_ENTRIES = 250
HISTORY_LOCK = threading.Lock()


def _load_entries():
    if not os.path.exists(HISTORY_FILE):
        return []
    try:
        with open(HISTORY_FILE, "rb") as f:
            data = f.read()
        if not data:
            return []
        return json.loads(data.decode("utf-8"))
    except Exception:
        return []


def record_operation(tool, title, status, message, affected_count=0, backup_path=None):
    try:
        with HISTORY_LOCK:
            entry = {
                "id": str(uuid.uuid4()),
                "tool": tool,
                "title": title,
                "status": status,
                "message": message,
                "createdAt": int(time.time()),
                "affectedCount": affected_count,
                "backupPath": backup_path or ""
            }
            entries = [entry] + _load_entries()
            entries = entries[:MAX_ENTRIES]
            ensure_dir(application_support_dir())
            tmp = HISTORY_FILE + "." + str(uuid.uuid4()) + ".tmp"
            with open(tmp, "wb") as f:
                f.write(json.dumps(entries, ensure_ascii=False, indent=2).encode("utf-8"))
            os.rename(tmp, HISTORY_FILE)
        return True
    except Exception:
        return False


def read_history(tool=None):
    entries = _load_entries()
    if tool and tool != "All":
        return [e for e in entries if e.get("tool") == tool]
    return entries
