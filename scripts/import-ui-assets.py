#!/usr/bin/env python3
"""Vendor the Lucide icon font and Figtree text faces into Shared/Resources.

Usage: import-ui-assets.py <lucide-static package dir> <figtree repository dir>
Sources: `npm pack lucide-static` (ISC) and github.com/erikdkennedy/figtree (SIL OFL 1.1).
"""
from pathlib import Path
import json
import shutil
import sys

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Shared/Resources"
lucide, figtree = (Path(p) for p in sys.argv[1:3])

codepoints = json.loads((lucide / "font/codepoints.json").read_text())
tags = json.loads((lucide / "tags.json").read_text())
# tags.json lists the canonical, non-brand names; codepoints.json adds aliases that share glyphs.
icons = [{"id": "lu:" + name, "name": name.replace("-", " ").title(), "unicode": format(codepoints[name], "x"), "regular": False,
          "keywords": [str(t) for t in tags[name]]} for name in sorted(tags) if name in codepoints]
(RESOURCES / "lucide-icons.json").write_text(json.dumps(icons, separators=(",", ":"), ensure_ascii=False) + "\n")
shutil.copyfile(lucide / "font/lucide.ttf", RESOURCES / "Lucide.ttf")
version = json.loads((lucide / "package.json").read_text())["version"]
license_text = f"Lucide {version} icon font (lucide-static)\n\n" + (lucide / "LICENSE").read_text()
for target in [RESOURCES / "Lucide-LICENSE.txt", ROOT / "docs/third-party/Lucide-LICENSE.txt"]: target.write_text(license_text)

for weight in ["Regular", "Medium", "SemiBold", "Bold", "ExtraBold"]:
    shutil.copyfile(figtree / f"fonts/ttf/Figtree-{weight}.ttf", RESOURCES / f"Figtree-{weight}.ttf")
for target in [RESOURCES / "Figtree-OFL.txt", ROOT / "docs/third-party/Figtree-OFL.txt"]: shutil.copyfile(figtree / "OFL.txt", target)
print(f"Imported {len(icons)} Lucide icons and five Figtree weights.")
