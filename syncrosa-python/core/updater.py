# -*- coding: utf-8 -*-
from __future__ import unicode_literals

import json
import os
import re
import subprocess
import sys
import webbrowser

from core.network import make_request

RELEASE_API_URL = "https://syncrosa-updates.telegraphica.workers.dev/v1/update-manifest?platform=macos&track=python&channel=stable"
RELEASE_PAGE_URL = "https://github.com/MiChiRose/Syncrosa/releases/latest"
PYTHON_ASSET_MARKER = "Syncrosa_Python_v"


def _read_plist(path):
    try:
        import plistlib
        if hasattr(plistlib, "load"):
            with open(path, "rb") as f:
                return plistlib.load(f)
        return plistlib.readPlist(path)
    except Exception:
        return {}


def current_version():
    env_version = os.environ.get("SYNCROSA_VERSION", "").strip()
    if env_version:
        return env_version

    here = os.path.abspath(__file__)
    resources_dir = os.path.dirname(os.path.dirname(here))
    contents_dir = os.path.dirname(resources_dir)
    info_path = os.path.join(contents_dir, "Info.plist")
    if os.path.exists(info_path):
        plist = _read_plist(info_path)
        version = plist.get("CFBundleShortVersionString") or plist.get("CFBundleVersion")
        if version:
            return str(version)

    repo_version = os.path.abspath(os.path.join(resources_dir, "..", "VERSION"))
    if os.path.exists(repo_version):
        try:
            with open(repo_version, "r") as f:
                version = f.read().strip()
                if version:
                    return version
        except Exception:
            pass

    return "Development"


def _version_parts(version):
    return [int(part) for part in re.findall(r"\d+", version or "")[:4]]


def compare_versions(left, right):
    left_parts = _version_parts(left)
    right_parts = _version_parts(right)
    max_len = max(len(left_parts), len(right_parts))
    for index in range(max_len):
        lv = left_parts[index] if index < len(left_parts) else 0
        rv = right_parts[index] if index < len(right_parts) else 0
        if lv > rv:
            return 1
        if lv < rv:
            return -1
    return 0


def _find_python_asset(release):
    download_url = release.get("download_url") or release.get("downloadURL")
    if download_url:
        return download_url
    for asset in release.get("assets", []):
        name = asset.get("name", "")
        if PYTHON_ASSET_MARKER in name and name.endswith(".zip"):
            return asset.get("browser_download_url") or asset.get("download_url")
    return None


def check_for_updates():
    ok, result = make_request(
        RELEASE_API_URL,
        {"Accept": "application/json"},
        timeout_sec=30
    )
    if not ok:
        return {
            "ok": False,
            "available": False,
            "message": "Could not check Syncrosa updates.",
            "url": RELEASE_PAGE_URL
        }

    try:
        release = json.loads(result)
    except Exception as exc:
        return {
            "ok": False,
            "available": False,
            "message": "Could not parse the Syncrosa update response.",
            "url": RELEASE_PAGE_URL
        }

    latest = (release.get("tag_name") or release.get("version") or release.get("name") or "").lstrip("v")
    release_title = release.get("name") or "Syncrosa " + latest
    release_notes = release.get("body") or ""
    html_url = release.get("html_url") or release.get("release_url") or RELEASE_PAGE_URL
    asset_url = _find_python_asset(release) or html_url
    current = current_version()

    if not latest:
        return {
            "ok": False,
            "available": False,
            "message": "Could not read the latest Syncrosa version.",
            "url": html_url,
            "release_title": release_title,
            "release_notes": release_notes
        }

    if current == "Development":
        return {
            "ok": True,
            "available": False,
            "message": "Latest release: Syncrosa {0}. This is a development build.".format(latest),
            "url": asset_url,
            "release_title": release_title,
            "release_notes": release_notes
        }

    if compare_versions(latest, current) > 0:
        return {
            "ok": True,
            "available": True,
            "message": "Syncrosa {0} is available. Click Update App.".format(latest),
            "url": asset_url,
            "release_title": release_title,
            "release_notes": release_notes
        }

    return {
        "ok": True,
        "available": False,
        "message": "You are up to date on Syncrosa {0}.".format(current),
        "url": html_url,
        "release_title": release_title,
        "release_notes": release_notes
    }


def open_update_url(url=None):
    target = url or RELEASE_PAGE_URL
    try:
        if sys.platform == "darwin":
            subprocess.Popen(["open", target])
        else:
            webbrowser.open(target)
        return True
    except Exception:
        try:
            webbrowser.open(target)
            return True
        except Exception:
            return False
