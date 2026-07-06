# -*- coding: utf-8 -*-
from __future__ import absolute_import
import os
import tempfile


def application_support_dir():
    return os.path.expanduser("~/Library/Application Support/Syncrosa")


def backups_dir():
    return os.path.join(application_support_dir(), "Backups")


def cache_dir():
    return os.path.join(os.path.expanduser("~/Library/Caches"), "Syncrosa")


def ensure_dir(path):
    if not os.path.isdir(path):
        os.makedirs(path)
    return path


def tool_backup_dir(tool_name):
    safe = tool_name.replace("/", "-").replace(":", "-")
    return ensure_dir(os.path.join(backups_dir(), safe))


def operation_cache_dir(tool_name):
    safe = tool_name.replace("/", "-").replace(":", "-")
    return ensure_dir(os.path.join(cache_dir(), safe))


def temp_file(prefix, suffix):
    ensure_dir(cache_dir())
    fd, path = tempfile.mkstemp(prefix=prefix, suffix=suffix, dir=cache_dir())
    os.close(fd)
    return path
