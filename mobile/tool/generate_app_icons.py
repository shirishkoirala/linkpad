#!/usr/bin/env python3
"""Resize the approved Linkpad artwork into the existing iOS/Android icon slots.

Run on macOS: python3 mobile/tool/generate_app_icons.py
Uses the built-in sips utility; no third-party imaging dependencies.
"""

import json
from pathlib import Path
import shutil
import subprocess


def main():
    mobile = Path(__file__).resolve().parents[1]
    source = mobile / "assets/branding/linkpad-icon-source.png"
    sips = shutil.which("sips")
    if not sips:
        raise SystemExit("This script requires macOS sips.")
    if not source.is_file():
        raise SystemExit(f"Missing source artwork: {source}")

    icons = mobile / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    images = json.loads((icons / "Contents.json").read_text())["images"]
    targets = {}
    for item in images:
        pixels = float(item["size"].split("x")[0]) * float(item["scale"].removesuffix("x"))
        targets[icons / item["filename"]] = round(pixels)
    for density, pixels in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        targets[mobile / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png"] = pixels

    for target, pixels in targets.items():
        subprocess.run([sips, "--resampleHeightWidth", str(pixels), str(pixels), str(source), "--out", str(target)], check=True, stdout=subprocess.DEVNULL)
    print(f"Generated {len(targets)} iOS/Android app icons from {source.name}.")


if __name__ == "__main__":
    main()
