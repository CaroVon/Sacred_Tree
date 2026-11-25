#!/usr/bin/env python3
"""只下载 Godot 导出模板里的网页与 Windows 模板（整包 1.2GB，用 HTTP Range 只取需要的几个文件）。

产物：%APPDATA%/Godot/export_templates/<版本>.stable/（web_*.zip、windows_*.exe）
用法：python game/tools/release/fetch_templates.py [4.7.2]
"""
from __future__ import annotations

import io
import os
import struct
import sys
import urllib.request
import zipfile
import zlib
from pathlib import Path

VER = sys.argv[1] if len(sys.argv) > 1 else "4.7.2"
URL = (f"https://github.com/godotengine/godot/releases/download/{VER}-stable/"
       f"Godot_v{VER}-stable_export_templates.tpz")
WANT = ("web_nothreads_release.zip", "web_nothreads_debug.zip", "web_release.zip", "web_debug.zip",
        "windows_release_x86_64.exe", "windows_debug_x86_64.exe", "version.txt")


def get(url: str, start: int, end: int) -> bytes:
    req = urllib.request.Request(url, headers={"Range": f"bytes={start}-{end}"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return r.read()


def main() -> None:
    with urllib.request.urlopen(urllib.request.Request(URL, method="HEAD"), timeout=60) as r:
        url = r.geturl()
        size = int(r.headers["Content-Length"])
    tail = get(url, size - 65536 - 22, size - 1)
    i = tail.rfind(b"PK\x05\x06")
    cd_size, cd_off = struct.unpack("<II", tail[i + 12:i + 20])
    if cd_off == 0xFFFFFFFF:  # zip64
        j = tail.rfind(b"PK\x06\x06")
        cd_size, cd_off = struct.unpack("<QQ", tail[j + 40:j + 56])
    cd = get(url, cd_off, cd_off + cd_size - 1)
    dest = Path(os.environ["APPDATA"]) / "Godot" / "export_templates" / f"{VER}.stable"
    dest.mkdir(parents=True, exist_ok=True)
    p = 0
    while p < len(cd) and cd[p:p + 4] == b"PK\x01\x02":
        method, = struct.unpack("<H", cd[p + 10:p + 12])
        csize, usize = struct.unpack("<II", cd[p + 20:p + 28])
        nlen, elen, clen = struct.unpack("<HHH", cd[p + 28:p + 34])
        loff, = struct.unpack("<I", cd[p + 42:p + 46])
        name = cd[p + 46:p + 46 + nlen].decode()
        extra = cd[p + 46 + nlen:p + 46 + nlen + elen]
        p += 46 + nlen + elen + clen
        base = name.rsplit("/", 1)[-1]
        if base not in WANT:
            continue
        # zip64 extra field
        q = 0
        while q < len(extra):
            hid, hl = struct.unpack("<HH", extra[q:q + 4])
            if hid == 1:
                vals = extra[q + 4:q + 4 + hl]
                k = 0
                if usize == 0xFFFFFFFF:
                    usize, = struct.unpack("<Q", vals[k:k + 8]); k += 8
                if csize == 0xFFFFFFFF:
                    csize, = struct.unpack("<Q", vals[k:k + 8]); k += 8
                if loff == 0xFFFFFFFF:
                    loff, = struct.unpack("<Q", vals[k:k + 8]); k += 8
            q += 4 + hl
        lh = get(url, loff, loff + 29)
        ln, le = struct.unpack("<HH", lh[26:30])
        start = loff + 30 + ln + le
        raw = get(url, start, start + csize - 1)
        data = raw if method == 0 else zlib.decompress(raw, -15)
        assert len(data) == usize, (name, len(data), usize)
        (dest / base).write_bytes(data)
        print("ok", base, usize // 1024, "KB")
    print("->", dest)


if __name__ == "__main__":
    main()
