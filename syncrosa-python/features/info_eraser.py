# -*- coding: utf-8 -*-
from __future__ import absolute_import
import json
import os
import shutil
import struct
import time
import uuid

from core.storage_paths import tool_backup_dir

MUSIC_EXTENSIONS = set(["mp3", "m4a", "mp4", "aac", "flac", "wav", "aiff", "alac"])
MP4_EXTENSIONS = set(["m4a", "mp4", "aac", "alac"])
BACKUP_DIR_NAME = "SyncrosaInfoEraserBackup"
MANIFEST_NAME = "manifest.json"
CHUNK_SIZE = 256 * 1024


def _to_text(value):
    if value is None:
        return u""
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    return value


def find_music_files(folder):
    results = []
    for root, dirs, files in os.walk(folder):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d != BACKUP_DIR_NAME]
        for name in files:
            if name.startswith("."):
                continue
            ext = os.path.splitext(name)[1].lower().lstrip(".")
            if ext in MUSIC_EXTENSIONS:
                results.append(os.path.join(root, name))
    results.sort()
    return results


def _prune_mirrored_backups(root, keep=10):
    try:
        items = []
        for name in os.listdir(root):
            path = os.path.join(root, name)
            if os.path.isdir(path):
                items.append((os.path.getmtime(path), path))
        items.sort(reverse=True)
        for _mtime, path in items[keep:]:
            shutil.rmtree(path)
    except Exception:
        pass


def _restore_backup_dir(folder):
    local_dir = os.path.join(folder, BACKUP_DIR_NAME)
    if os.path.exists(os.path.join(local_dir, MANIFEST_NAME)):
        return local_dir
    try:
        root = tool_backup_dir("InfoEraser")
        items = []
        for name in os.listdir(root):
            path = os.path.join(root, name)
            if os.path.isdir(path) and os.path.exists(os.path.join(path, MANIFEST_NAME)):
                items.append((os.path.getmtime(path), path))
        items.sort(reverse=True)
        if items:
            return items[0][1]
    except Exception:
        pass
    return local_dir


def _relpath(path, folder):
    try:
        return os.path.relpath(path, folder)
    except Exception:
        return os.path.basename(path)


def _safe_join(folder, relative_path):
    base = os.path.abspath(folder)
    candidate = os.path.abspath(os.path.join(base, relative_path))
    if candidate == base or candidate.startswith(base + os.sep):
        return candidate
    return None


def _byte_at(data, index):
    value = data[index]
    if isinstance(value, int):
        return value
    return ord(value)


def _syncsafe_size(header):
    if len(header) < 10:
        return 0
    return ((_byte_at(header, 6) & 0x7F) << 21) | ((_byte_at(header, 7) & 0x7F) << 14) | ((_byte_at(header, 8) & 0x7F) << 7) | (_byte_at(header, 9) & 0x7F)


def _mp3_tag_ranges(path):
    size = os.path.getsize(path)
    id3v2_len = 0
    id3v1_len = 0
    with open(path, "rb") as f:
        header = f.read(10)
        if len(header) == 10 and header[:3] == b"ID3":
            id3v2_len = 10 + _syncsafe_size(header)
            if _byte_at(header, 5) & 0x10:
                id3v2_len += 10
            if id3v2_len > size:
                id3v2_len = 0
        if size >= 128:
            f.seek(size - 128)
            if f.read(3) == b"TAG":
                id3v1_len = 128
    return id3v2_len, id3v1_len, size


def _is_supported_ext(ext):
    return ext == "mp3" or ext in MP4_EXTENSIONS


def _read_u32be(data, offset):
    return struct.unpack(">I", data[offset:offset + 4])[0]


def _read_u64be(data, offset):
    return struct.unpack(">Q", data[offset:offset + 8])[0]


def _atom_header(f, offset, parent_end):
    f.seek(offset)
    header = f.read(16)
    if len(header) < 8:
        return None
    size32 = _read_u32be(header, 0)
    atom_type = header[4:8].decode("latin-1")
    header_size = 8
    atom_size = size32
    if size32 == 1:
        if len(header) < 16:
            return None
        atom_size = _read_u64be(header, 8)
        header_size = 16
    elif size32 == 0:
        atom_size = parent_end - offset
    if atom_size < header_size:
        return None
    return {
        "type": atom_type,
        "offset": offset,
        "size": atom_size,
        "headerSize": header_size
    }


def _find_atom(f, start, end, path, index=0):
    cursor = start
    while cursor + 8 <= end:
        atom = _atom_header(f, cursor, end)
        if not atom:
            break
        if atom["offset"] + atom["size"] > end:
            break
        if atom["type"] == path[index]:
            if index == len(path) - 1:
                return atom
            extra_header = 4 if atom["type"] == "meta" else 0
            child_start = atom["offset"] + atom["headerSize"] + extra_header
            if child_start < atom["offset"] + atom["size"]:
                found = _find_atom(f, child_start, atom["offset"] + atom["size"], path, index + 1)
                if found:
                    return found
        cursor += atom["size"]
    return None


def _mp4_metadata_atom(path):
    size = os.path.getsize(path)
    if size <= 8:
        return None
    with open(path, "rb") as f:
        return _find_atom(f, 0, size, ["moov", "udta", "meta", "ilst"])


def _read_range(path, offset, length):
    with open(path, "rb") as f:
        f.seek(offset)
        return f.read(length)


def _write_range(path, offset, data):
    with open(path, "r+b") as f:
        f.seek(offset)
        f.write(data)


def _free_atom_data(size, header_size):
    data = bytearray(b"\x00" * size)
    if header_size == 16:
        data[0:4] = struct.pack(">I", 1)
        data[4:8] = b"free"
        data[8:16] = struct.pack(">Q", size)
    else:
        data[0:4] = struct.pack(">I", size)
        data[4:8] = b"free"
    return bytes(data)


def _copy_range(src_path, dst_path, start, end):
    remaining = max(0, end - start)
    with open(src_path, "rb") as src:
        with open(dst_path, "wb") as dst:
            src.seek(start)
            while remaining > 0:
                chunk = src.read(min(CHUNK_SIZE, remaining))
                if not chunk:
                    break
                dst.write(chunk)
                remaining -= len(chunk)
    if remaining != 0:
        try:
            os.remove(dst_path)
        except OSError:
            pass
        raise IOError("Could not copy the full audio payload")


def _replace_file(original_path, temp_path):
    backup_path = original_path + ".syncrosa-tmp-" + uuid.uuid4().hex
    os.rename(original_path, backup_path)
    try:
        os.rename(temp_path, original_path)
        os.remove(backup_path)
    except Exception:
        if os.path.exists(original_path):
            os.remove(original_path)
        os.rename(backup_path, original_path)
        raise


def backup_original_info(folder, files, progress_cb=None):
    backup_dir = os.path.join(folder, BACKUP_DIR_NAME)
    tags_dir = os.path.join(backup_dir, "tags")
    if not os.path.isdir(tags_dir):
        os.makedirs(tags_dir)

    manifest = {
        "version": 1,
        "createdAt": int(time.time()),
        "format": "syncrosa-info-eraser-sidecar-v2",
        "items": []
    }

    total = len(files)
    for index, path in enumerate(files):
        ext = os.path.splitext(path)[1].lower().lstrip(".")
        item = {
            "id": uuid.uuid4().hex,
            "relativePath": _relpath(path, folder),
            "extension": ext,
            "supported": ext == "mp3",
            "id3v2File": "",
            "id3v1File": "",
            "id3v2Bytes": 0,
            "id3v1Bytes": 0,
            "mp4AtomFile": "",
            "mp4AtomOffset": 0,
            "mp4AtomBytes": 0,
            "mp4AtomType": ""
        }
        item["supported"] = _is_supported_ext(ext)

        if ext == "mp3":
            id3v2_len, id3v1_len, size = _mp3_tag_ranges(path)
            with open(path, "rb") as f:
                if id3v2_len > 0:
                    tag_name = item["id"] + ".id3v2"
                    with open(os.path.join(tags_dir, tag_name), "wb") as out:
                        out.write(f.read(id3v2_len))
                    item["id3v2File"] = "tags/" + tag_name
                    item["id3v2Bytes"] = id3v2_len
                if id3v1_len > 0:
                    f.seek(size - 128)
                    tag_name = item["id"] + ".id3v1"
                    with open(os.path.join(tags_dir, tag_name), "wb") as out:
                        out.write(f.read(128))
                    item["id3v1File"] = "tags/" + tag_name
                    item["id3v1Bytes"] = 128
        elif ext in MP4_EXTENSIONS:
            atom = _mp4_metadata_atom(path)
            if atom:
                tag_name = item["id"] + "." + atom["type"]
                with open(os.path.join(tags_dir, tag_name), "wb") as out:
                    out.write(_read_range(path, atom["offset"], atom["size"]))
                item["mp4AtomFile"] = "tags/" + tag_name
                item["mp4AtomOffset"] = atom["offset"]
                item["mp4AtomBytes"] = atom["size"]
                item["mp4AtomType"] = atom["type"]

        manifest["items"].append(item)
        if progress_cb:
            progress_cb(index + 1, total)

    manifest_path = os.path.join(backup_dir, MANIFEST_NAME)
    tmp_path = manifest_path + ".tmp"
    with open(tmp_path, "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
    os.rename(tmp_path, manifest_path)
    try:
        mirror_root = tool_backup_dir("InfoEraser")
        mirror_dir = os.path.join(mirror_root, "backup-{}-{}".format(int(time.time()), uuid.uuid4().hex[:8]))
        if os.path.exists(mirror_dir):
            shutil.rmtree(mirror_dir)
        shutil.copytree(backup_dir, mirror_dir)
        _prune_mirrored_backups(mirror_root, 10)
    except Exception:
        pass
    return manifest_path, len([i for i in manifest["items"] if i.get("supported")])


def erase_info(files, progress_cb=None):
    erased = 0
    unsupported = 0
    total = len(files)
    for index, path in enumerate(files):
        ext = os.path.splitext(path)[1].lower().lstrip(".")
        if ext == "mp3":
            id3v2_len, id3v1_len, size = _mp3_tag_ranges(path)
            if id3v2_len > 0 or id3v1_len > 0:
                end = size - id3v1_len
                tmp_path = path + ".syncrosa-strip-" + uuid.uuid4().hex
                _copy_range(path, tmp_path, id3v2_len, end)
                _replace_file(path, tmp_path)
                erased += 1
        elif ext in MP4_EXTENSIONS:
            atom = _mp4_metadata_atom(path)
            if atom:
                _write_range(path, atom["offset"], _free_atom_data(atom["size"], atom["headerSize"]))
                erased += 1
        else:
            unsupported += 1
        if progress_cb:
            progress_cb(index + 1, total)
    return erased, unsupported


def restore_info(folder, progress_cb=None):
    backup_dir = _restore_backup_dir(folder)
    manifest_path = os.path.join(backup_dir, MANIFEST_NAME)
    with open(manifest_path, "r") as f:
        manifest = json.load(f)

    restored = 0
    missing = 0
    items = manifest.get("items", [])
    total = len(items)
    for index, item in enumerate(items):
        if not item.get("supported"):
            if progress_cb:
                progress_cb(index + 1, total)
            continue
        path = _safe_join(folder, item.get("relativePath", ""))
        if not path or not os.path.exists(path):
            missing += 1
            if progress_cb:
                progress_cb(index + 1, total)
            continue

        ext = item.get("extension", "")
        if ext == "mp3":
            id3v2_data = b""
            id3v1_data = b""
            if item.get("id3v2File"):
                tag_path = _safe_join(backup_dir, item.get("id3v2File"))
                if tag_path and os.path.exists(tag_path):
                    id3v2_data = open(tag_path, "rb").read()
            if item.get("id3v1File"):
                tag_path = _safe_join(backup_dir, item.get("id3v1File"))
                if tag_path and os.path.exists(tag_path):
                    id3v1_data = open(tag_path, "rb").read()

            id3v2_len, id3v1_len, size = _mp3_tag_ranges(path)
            body_tmp = path + ".syncrosa-body-" + uuid.uuid4().hex
            final_tmp = path + ".syncrosa-restore-" + uuid.uuid4().hex
            _copy_range(path, body_tmp, id3v2_len, size - id3v1_len)
            try:
                with open(final_tmp, "wb") as out:
                    if id3v2_data:
                        out.write(id3v2_data)
                    with open(body_tmp, "rb") as body:
                        shutil.copyfileobj(body, out, CHUNK_SIZE)
                    if id3v1_data:
                        out.write(id3v1_data)
                _replace_file(path, final_tmp)
                restored += 1
            finally:
                if os.path.exists(body_tmp):
                    os.remove(body_tmp)
                if os.path.exists(final_tmp):
                    os.remove(final_tmp)
        elif ext in MP4_EXTENSIONS and item.get("mp4AtomFile"):
            tag_path = _safe_join(backup_dir, item.get("mp4AtomFile"))
            if tag_path and os.path.exists(tag_path):
                atom_data = open(tag_path, "rb").read()
                if len(atom_data) == int(item.get("mp4AtomBytes") or 0):
                    _write_range(path, int(item.get("mp4AtomOffset") or 0), atom_data)
                    restored += 1

        if progress_cb:
            progress_cb(index + 1, total)
    return restored, missing
