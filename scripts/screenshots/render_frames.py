#!/usr/bin/env python3
"""Render framed marketing artwork from real app captures.

Reads frames/store-frames.html, finds every fixed-size element carrying a
`data-screen-label`, swaps the capture PNGs into its <img> slots, and screenshots
each card at its declared pixel size with headless Google Chrome (no dependencies)
or Playwright when that is importable.

    render_frames.py --captures out --ios-out fastlane/screenshots/en-US --mac-out out/framed
    render_frames.py --list
    render_frames.py --captures out --ios-out ... --only "iPhone 1,iPad 2"

A card whose capture is missing fails the run and writes nothing, so a broken image
slot can never reach the store.
"""

import argparse
import http.server
import os
import re
import shutil
import struct
import subprocess
import tempfile
import threading
import time
from html.parser import HTMLParser

HERE = os.path.dirname(os.path.abspath(__file__))
FRAMES_DIR = os.path.join(HERE, "frames")
DESIGN_NAME = "store-frames.html"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# App Store Connect / fastlane deliver file names per device class.
OUTPUT_RULES = [
    (re.compile(r"^iPhone (\d+)$"), "ios", "iPhone 6.9 Display-%02d.png"),
    (re.compile(r"^iPad (\d+)$"), "ios", "iPad Pro 13 Display-%02d.png"),
    (re.compile(r"^Mac (\d+)$"), "mac", "mac-%02d.png"),
]


class Card:
    def __init__(self, label, width, height, html):
        self.label = label
        self.width = width
        self.height = height
        self.html = html


class DesignParser(HTMLParser):
    VOID = {"img", "br", "hr", "meta", "link", "input", "source"}

    def __init__(self, source):
        super().__init__(convert_charrefs=False)
        self.source = source
        self.cards = []
        self.open_card = None
        self.depth = 0

    def _offset(self):
        line, col = self.getpos()
        offset = 0
        for _ in range(line - 1):
            offset = self.source.index("\n", offset) + 1
        return offset + col

    def handle_starttag(self, tag, attrs):
        if tag in self.VOID:
            return
        attrd = dict(attrs)
        if self.open_card is not None:
            self.depth += 1
            return
        label = attrd.get("data-screen-label")
        size = self._fixed_size(attrd.get("style") or "")
        if label and size:
            self.open_card = (label, size, self._offset())
            self.depth = 0

    def handle_startendtag(self, tag, attrs):
        pass

    def handle_endtag(self, tag):
        if self.open_card is None or tag in self.VOID:
            return
        if self.depth > 0:
            self.depth -= 1
            return
        label, size, start = self.open_card
        end = self.source.index(">", self._offset()) + 1
        self.cards.append(Card(label, size[0], size[1], self.source[start:end]))
        self.open_card = None

    @staticmethod
    def _fixed_size(style):
        width = re.search(r"(?:^|[;\s])width:\s*(\d+)px", style)
        height = re.search(r"(?:^|[;\s])height:\s*(\d+)px", style)
        if width and height:
            return int(width.group(1)), int(height.group(1))
        return None


def head_styles(html):
    return re.findall(r"<style>(.*?)</style>", html, re.S)


def image_sources(card_html):
    return re.findall(r'<img[^>]+src="([^"]+)"', card_html)


def png_size(path):
    with open(path, "rb") as handle:
        header = handle.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", header[16:24])


def serve(root):
    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=root, **kwargs)

        def log_message(self, *args):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def wrapper_page(card, styles):
    parts = ["<!DOCTYPE html><html><head><meta charset='utf-8'>"]
    for style in styles:
        parts.append("<style>%s</style>" % style)
    parts.append(
        "<style>html,body{margin:0;padding:0;background:#000;overflow:hidden;}"
        "#card{position:absolute;left:0;top:0;}</style>"
    )
    parts.append("</head><body><div id='card'>%s</div></body></html>" % card.html)
    return "".join(parts)


def shoot_chrome(url, path, width, height, timeout):
    if not os.path.exists(CHROME):
        raise SystemExit("Google Chrome not found at %s" % CHROME)
    if os.path.exists(path):
        os.remove(path)
    profile = tempfile.mkdtemp(prefix="render-frames-chrome-")
    process = subprocess.Popen(
        [
            CHROME,
            "--headless=new",
            "--disable-gpu",
            "--hide-scrollbars",
            "--force-device-scale-factor=1",
            "--force-color-profile=srgb",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-background-networking",
            "--virtual-time-budget=10000",
            "--user-data-dir=%s" % profile,
            "--window-size=%d,%d" % (width, height),
            "--screenshot=%s" % path,
            url,
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        # Chrome re-execs itself on macOS, so wait for the PNG to appear and settle
        # rather than for the process we launched.
        deadline = time.time() + timeout
        settled = None
        while time.time() < deadline:
            time.sleep(0.25)
            if not os.path.exists(path):
                continue
            size = os.path.getsize(path)
            if size and size == settled and png_size(path) == (width, height):
                return
            settled = size
        raise SystemExit("Chrome did not produce %s within %ds" % (path, timeout))
    finally:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
        shutil.rmtree(profile, ignore_errors=True)


def shoot_playwright(pages, timeout):
    from playwright.sync_api import sync_playwright

    with sync_playwright() as play:
        browser = play.chromium.launch()
        try:
            for url, path, width, height in pages:
                page = browser.new_page(
                    viewport={"width": width, "height": height}, device_scale_factor=1
                )
                page.goto(url, wait_until="load", timeout=timeout * 1000)
                page.wait_for_function(
                    "Array.from(document.images).every(i => i.complete && i.naturalWidth > 0)",
                    timeout=timeout * 1000,
                )
                page.evaluate("document.fonts.ready")
                page.screenshot(path=path)
                page.close()
        finally:
            browser.close()


def pick_browser(requested):
    if requested == "chrome":
        return "chrome"
    try:
        import playwright  # noqa: F401
    except ImportError:
        if requested == "playwright":
            raise SystemExit("playwright is not importable; install it or run with --browser chrome")
        return "chrome"
    return "playwright"


def destination(label, args):
    for pattern, kind, template in OUTPUT_RULES:
        match = pattern.match(label)
        if not match:
            continue
        out_dir = args.ios_out if kind == "ios" else args.mac_out
        if not out_dir:
            return None
        return os.path.join(out_dir, template % int(match.group(1)))
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--captures", default=os.path.join(HERE, "out"), help="capture directory (default: scripts/screenshots/out)")
    parser.add_argument("--ios-out", help="directory for the App Store cards, e.g. fastlane/screenshots/en-US")
    parser.add_argument("--mac-out", help="directory for the macOS marketing cards")
    parser.add_argument("--only", help="comma-separated card labels, e.g. 'iPhone 1,iPad 2'")
    parser.add_argument("--browser", choices=["auto", "playwright", "chrome"], default="auto")
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--list", action="store_true", help="list the cards and exit")
    args = parser.parse_args()

    design_path = os.path.join(FRAMES_DIR, DESIGN_NAME)
    if not os.path.exists(design_path):
        raise SystemExit("frame design not found: %s" % design_path)
    source = open(design_path, encoding="utf-8").read()

    reader = DesignParser(source)
    reader.feed(source)
    cards = reader.cards
    if not cards:
        raise SystemExit("no fixed-size [data-screen-label] cards in %s" % design_path)

    if args.list:
        for card in cards:
            print("%-14s %5d x %-5d -> %s" % (
                card.label, card.width, card.height, destination(card.label, args) or "(no output)"
            ))
        return

    if args.only:
        wanted = [name.strip() for name in args.only.split(",") if name.strip()]
        known = {card.label for card in cards}
        missing = [name for name in wanted if name not in known]
        if missing:
            raise SystemExit("no card labelled %s" % ", ".join(missing))
        cards = [card for card in cards if card.label in wanted]

    targets = [(card, destination(card.label, args)) for card in cards]
    targets = [(card, path) for card, path in targets if path]
    if not targets:
        raise SystemExit("no card maps to an output; pass --ios-out and/or --mac-out")

    captures = os.path.abspath(args.captures)
    if not os.path.isdir(captures):
        raise SystemExit("captures directory not found: %s" % captures)

    styles = head_styles(source)
    stage = tempfile.mkdtemp(prefix="render-frames-")
    try:
        assets = os.path.join(FRAMES_DIR, "assets")
        if os.path.isdir(assets):
            shutil.copytree(assets, os.path.join(stage, "assets"))
        os.symlink(captures, os.path.join(stage, "captures"))

        pages = []
        for index, (card, path) in enumerate(targets):
            slots = image_sources(card.html)
            if not slots:
                raise SystemExit("card '%s' has no image slot" % card.label)
            for src in slots:
                resolved = os.path.join(stage, src)
                if not os.path.exists(resolved):
                    raise SystemExit("card '%s' wants %s, which is not under %s" % (card.label, src, captures))
                if src.endswith(".png") and png_size(resolved) is None:
                    raise SystemExit("card '%s': %s is not a readable PNG" % (card.label, src))
            page_name = "card-%02d.html" % index
            with open(os.path.join(stage, page_name), "w", encoding="utf-8") as handle:
                handle.write(wrapper_page(card, styles))
            pages.append((page_name, card, path))

        server = serve(stage)
        base = "http://127.0.0.1:%d/" % server.server_address[1]
        browser = pick_browser(args.browser)
        jobs = []
        for page_name, card, path in pages:
            os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
            jobs.append((base + page_name, os.path.abspath(path), card.width, card.height))

        if browser == "playwright":
            shoot_playwright(jobs, args.timeout)
        else:
            for url, path, width, height in jobs:
                shoot_chrome(url, path, width, height, args.timeout)
        server.shutdown()

        failures = []
        for (page_name, card, path), job in zip(pages, jobs):
            written = job[1]
            size = png_size(written) if os.path.exists(written) else None
            if size != (card.width, card.height):
                failures.append("%s: expected %dx%d, got %s" % (card.label, card.width, card.height, size or "no file"))
                continue
            print("%-14s %5d x %-5d  %s" % (card.label, card.width, card.height, written))
        if failures:
            raise SystemExit("render failed:\n  " + "\n  ".join(failures))
    finally:
        shutil.rmtree(stage, ignore_errors=True)


if __name__ == "__main__":
    main()
