#!/usr/bin/env python3
"""List a desktop directory as JSON for the bog.desktop-icons plugin.

Only the top level is listed, hidden entries are skipped, directories sort
before files, and the result is capped so a pathological folder cannot make
the shell render an unbounded grid. Names and icons are display data; the QML
side renders every string as plain text.
"""

import json
import os
import sys

MAX_ENTRIES = 500
MAX_NAME = 200

IMAGE_EXT = {
    "jpg", "jpeg", "png", "gif", "webp", "bmp", "avif", "heic", "heif",
    "tif", "tiff", "jxl",
}
VIDEO_EXT = {"mp4", "mkv", "webm", "avi", "mov", "m4v", "mpg", "mpeg", "ogv"}
AUDIO_EXT = {"mp3", "flac", "wav", "ogg", "opus", "m4a", "aac", "wma", "oga"}
ARCHIVE_EXT = {
    "zip", "tar", "gz", "bz2", "xz", "7z", "rar", "zst", "lz4", "tgz",
    "txz", "tlz", "cab", "iso",
}
DOC_EXT = {"doc", "docx", "odt", "rtf", "pages"}
SHEET_EXT = {"xls", "xlsx", "ods", "csv", "tsv", "numbers"}
SLIDE_EXT = {"ppt", "pptx", "odp", "key"}
SCRIPT_EXT = {"sh", "bash", "zsh", "fish", "py", "js", "mjs", "ts", "rb", "pl", "lua", "php"}
TEXT_EXT = {
    "txt", "md", "markdown", "log", "conf", "cfg", "ini", "json", "jsonc",
    "yaml", "yml", "toml", "xml", "html", "htm", "css", "scss", "sql", "nfo",
}

ICON_BY_GROUP = {
    "image": "image-x-generic",
    "video": "video-x-generic",
    "audio": "audio-x-generic",
    "archive": "package-x-generic",
    "document": "x-office-document",
    "spreadsheet": "x-office-spreadsheet",
    "presentation": "x-office-presentation",
    "pdf": "application-pdf",
    "script": "text-x-script",
    "text": "text-x-generic",
    "executable": "application-x-executable",
    "desktop": "application-x-desktop",
    "file": "text-x-generic",
    "folder": "folder",
}


def group_for(extension, is_executable):
    if extension in IMAGE_EXT:
        return "image"
    if extension in VIDEO_EXT:
        return "video"
    if extension in AUDIO_EXT:
        return "audio"
    if extension in ARCHIVE_EXT:
        return "archive"
    if extension in DOC_EXT:
        return "document"
    if extension in SHEET_EXT:
        return "spreadsheet"
    if extension in SLIDE_EXT:
        return "presentation"
    if extension == "pdf":
        return "pdf"
    if extension == "desktop":
        return "desktop"
    if extension in SCRIPT_EXT:
        return "script"
    if extension in TEXT_EXT:
        return "text"
    if is_executable:
        return "executable"
    return "file"


def desktop_fields(path):
    """Read Name and Icon from a .desktop file without trusting its contents."""
    name = None
    icon = None
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as handle:
            in_entry = False
            for _ in range(400):
                line = handle.readline()
                if not line:
                    break
                line = line.strip()
                if line == "[Desktop Entry]":
                    in_entry = True
                    continue
                if line.startswith("[") and line.endswith("]"):
                    in_entry = False
                    continue
                if not in_entry or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                key = key.strip()
                if key == "Name" and name is None:
                    name = value.strip()
                elif key == "Icon" and icon is None:
                    icon = value.strip()
                if name is not None and icon is not None:
                    break
    except OSError:
        return None, None
    if name:
        name = name[:MAX_NAME]
    if icon:
        icon = icon[:MAX_NAME]
    return name, icon


def build_entry(directory, entry):
    name = entry.name
    if not name or name.startswith("."):
        return None
    try:
        is_dir = entry.is_dir(follow_symlinks=True)
    except OSError:
        is_dir = False
    try:
        is_executable = entry.is_file(follow_symlinks=True) and os.access(entry.path, os.X_OK)
    except OSError:
        is_executable = False

    base, extension = os.path.splitext(name)
    extension = extension.lower().lstrip(".")

    if is_dir:
        group = "folder"
        display_name = name
        icon = ICON_BY_GROUP[group]
        is_image = False
    else:
        group = group_for(extension, is_executable)
        icon = ICON_BY_GROUP[group]
        is_image = group == "image"
        display_name = name
        if extension == "desktop":
            desktop_name, desktop_icon = desktop_fields(entry.path)
            if desktop_name:
                display_name = desktop_name
            if desktop_icon:
                icon = desktop_icon

    return {
        "name": display_name[:MAX_NAME],
        "path": entry.path,
        "isDir": is_dir,
        "isImage": is_image,
        "isDesktop": extension == "desktop" and not is_dir,
        "icon": icon,
    }


def main():
    if len(sys.argv) != 2:
        json.dump([], sys.stdout)
        return 1
    directory = sys.argv[1]
    entries = []
    try:
        with os.scandir(directory) as iterator:
            for entry in iterator:
                if len(entries) >= MAX_ENTRIES:
                    break
                item = build_entry(directory, entry)
                if item is not None:
                    entries.append(item)
    except OSError:
        json.dump([], sys.stdout)
        return 1

    entries.sort(key=lambda item: (not item["isDir"], item["name"].casefold()))
    json.dump(entries, sys.stdout, ensure_ascii=False, separators=(",", ":"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
