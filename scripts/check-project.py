#!/usr/bin/env python3
"""Check generated project membership, plist files, research integrity and local links."""
from pathlib import Path
import hashlib
import json
import plistlib
import subprocess
import xml.etree.ElementTree as ET
from html.parser import HTMLParser

ROOT = Path(__file__).resolve().parent.parent
project = ROOT / "HabitBuddy.xcodeproj/project.pbxproj"
before = project.read_bytes()
subprocess.run(["python3", str(ROOT / "scripts/generate-project.py")], check=True)
assert project.read_bytes() == before, "Project is stale; regenerate and commit it."
source = project.read_text()
for folder in ["HabitBuddy", "Shared", "Widgets"]:
    for path in (ROOT / folder).rglob("*.swift"):
        assert str(path.relative_to(ROOT)) in source, f"Source missing from project: {path}"
for extension in ["*.plist", "*.entitlements", "*.xcprivacy"]:
    for path in ROOT.rglob(extension):
        if ".build" not in path.parts: plistlib.loads(path.read_bytes())
for path in ROOT.rglob("*.xcscheme"): ET.parse(path)
for path in (ROOT / "research").rglob("*.json"): json.loads(path.read_text())
research = ROOT / "research/habitkit"
for line in (research / "CHECKSUMS.sha256").read_text().splitlines():
    digest, name = line.split(None, 1)
    path = research / name.lstrip("* ")
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, f"Research changed: {name}"
class Links(HTMLParser):
    def __init__(self): super().__init__(); self.links = []
    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key in ["href", "src"] and value: self.links.append(value)
for path in research.rglob("*.html"):
    parser = Links(); parser.feed(path.read_text())
    for link in parser.links:
        if ":" not in link and not link.startswith("#"):
            assert (path.parent / link.split("#")[0]).exists(), f"Broken research link: {path}: {link}"
print("Project, plists, schemes, research checksums, JSON and gallery links passed.")
