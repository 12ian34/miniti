#!/usr/bin/env python3
"""Render a one-page contact sheet of every capture under out/ so the whole set can be
reviewed at a glance: build_gallery.py [--captures out] [--out out/gallery.png] [--thumb 360]

Writes gallery.html next to the PNG (open it in a browser for full-size images) and
renders it with headless Google Chrome."""

import argparse
import os
import struct
import subprocess
import tempfile
import time
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


def png_size(path):
    with open(path, "rb") as handle:
        header = handle.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", header[16:24])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--captures", default=os.path.join(HERE, "out"))
    parser.add_argument("--out", help="gallery PNG path (default: <captures>/gallery.png)")
    parser.add_argument("--thumb", type=int, default=360, help="thumbnail width in px")
    parser.add_argument("--devices", help="comma-separated subset of device folders")
    args = parser.parse_args()

    captures = os.path.abspath(args.captures)
    out_png = os.path.abspath(args.out or os.path.join(captures, "gallery.png"))
    out_html = os.path.splitext(out_png)[0] + ".html"
    devices = sorted(
        name for name in os.listdir(captures)
        if os.path.isdir(os.path.join(captures, name)) and name != "framed"
    )
    if args.devices:
        wanted = [d.strip() for d in args.devices.split(",")]
        devices = [d for d in devices if d in wanted]

    rows = []
    total_height = 40
    for device in devices:
        folder = os.path.join(captures, device)
        files = sorted(f for f in os.listdir(folder) if f.endswith(".png"))
        cells = []
        row_height = 0
        for name in files:
            path = os.path.join(folder, name)
            size = png_size(path)
            if not size:
                continue
            width, height = size
            thumb_h = int(args.thumb * height / width)
            row_height = max(row_height, thumb_h)
            cells.append(
                '<figure><img src="file://%s" width="%d" height="%d"><figcaption>%s<br><span>%dx%d</span></figcaption></figure>'
                % (path, args.thumb, thumb_h, name[:-4], width, height)
            )
        rows.append("<h2>%s</h2><div class='row'>%s</div>" % (device, "".join(cells)))
        total_height += row_height + 110

    columns = max((len(os.listdir(os.path.join(captures, d))) for d in devices), default=1)
    page_width = min(columns, 6) * (args.thumb + 24) + 40
    html = """<!DOCTYPE html><html><head><meta charset="utf-8"><style>
    body{margin:0;padding:20px;background:#111;color:#ddd;font:13px -apple-system,Helvetica,sans-serif}
    h2{margin:18px 0 8px;font-size:15px;color:#3FB950}
    .row{display:flex;flex-wrap:wrap;gap:24px}
    figure{margin:0;display:flex;flex-direction:column;align-items:flex-start}
    img{display:block;border:1px solid #333;border-radius:6px;background:#000}
    figcaption{margin-top:6px;color:#bbb}figcaption span{color:#666}
    </style></head><body>%s</body></html>""" % "".join(rows)
    with open(out_html, "w", encoding="utf-8") as handle:
        handle.write(html)

    rows_wrapped = 0
    for device in devices:
        count = len([f for f in os.listdir(os.path.join(captures, device)) if f.endswith(".png")])
        rows_wrapped += max(0, (count - 1) // 6)
    total_height += rows_wrapped * (int(args.thumb * 2.2) + 60)

    profile = tempfile.mkdtemp(prefix="gallery-chrome-")
    if os.path.exists(out_png):
        os.remove(out_png)
    process = subprocess.Popen(
        [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
         "--force-device-scale-factor=1", "--no-first-run", "--no-default-browser-check",
         "--disable-background-networking", "--virtual-time-budget=10000",
         "--user-data-dir=%s" % profile, "--window-size=%d,%d" % (page_width, total_height),
         "--screenshot=%s" % out_png, "file://" + out_html],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        deadline = time.time() + 120
        settled = None
        while time.time() < deadline:
            time.sleep(0.25)
            if os.path.exists(out_png):
                size = os.path.getsize(out_png)
                if size and size == settled:
                    break
                settled = size
    finally:
        process.terminate()
        shutil.rmtree(profile, ignore_errors=True)
    print(out_png, png_size(out_png))


if __name__ == "__main__":
    main()
