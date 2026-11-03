#!/usr/bin/env python3
"""Check local release-file consistency without querying or changing published state."""
from pathlib import Path
import plistlib
import re
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
if (root / 'Miniti.xcodeproj').exists():
    project = (root / 'Miniti.xcodeproj/project.pbxproj').read_text()
    versions = set(re.findall(r'MARKETING_VERSION = ([^;]+);', project))
    builds = set(re.findall(r'CURRENT_PROJECT_VERSION = ([^;]+);', project))
    if len(versions) != 1 or len(builds) != 1:
        raise SystemExit('App, extensions and test configurations disagree on version/build')
    for name in ['Miniti/Info.plist', 'MinitiMobile/Info.plist']:
        with (root / name).open('rb') as file:
            info = plistlib.load(file)
        for key, expected in [('CFBundleShortVersionString', versions), ('CFBundleVersion', builds)]:
            value = info.get(key)
            if value is not None and not str(value).startswith('$(') and str(value) not in expected:
                raise SystemExit(f'{name}: {key} disagrees with the Xcode project')
else:
    metadata = (root / 'lib/releaseMetadata.ts').read_text()
    values = dict(re.findall(r"export const (\w+_VERSION) = '(\d+\.\d+\.\d+)'", metadata))
    for platform in ['IOS', 'MACOS']:
        minimum, latest = (values[f'{platform}_{kind}_VERSION'] for kind in ['MIN', 'LATEST'])
        if tuple(map(int, minimum.split('.'))) > tuple(map(int, latest.split('.'))):
            raise SystemExit(f'{platform}: minimum exceeds latest')
    feed = ET.parse(root / 'public/appcast.xml')
    item = feed.find('./channel/item')
    if item is None:
        raise SystemExit('Sparkle appcast is empty')
    latest = item.findtext('{http://www.andymatuschak.org/xml-namespaces/sparkle}shortVersionString')
    if latest != values['MACOS_LATEST_VERSION']:
        raise SystemExit('macOS latest metadata disagrees with the newest Sparkle item')
print('Local release version/build metadata agrees; published availability was not checked')
