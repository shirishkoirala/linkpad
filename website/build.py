"""Stage the static GitHub Pages site. Run from any working directory."""
import json
import shutil
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
output = root / "bin" / "site"
output.mkdir(parents=True, exist_ok=True)
for name in ("index.html", "styles.css", "app.js", "release.json"):
    shutil.copy2(root / "website" / name, output / name)
shutil.copytree(root / "website" / "fonts", output / "fonts", dirs_exist_ok=True)
assets = output / "assets"
assets.mkdir(exist_ok=True)
for mode in ("touchpad", "remote", "keyboard"):
    shutil.copy2(root / "assets/release/screenshots/iOS" / f"{mode}.png", assets / f"{mode}.png")
shutil.copy2(root / "mobile/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png", assets / "icon.png")
shutil.copy2(root / "assets/release/social-preview.png", assets / "social-preview.png")
if len(sys.argv) > 1:
    release = json.loads(Path(sys.argv[1]).read_text())
    downloads = {}
    for asset in release["assets"]:
        name = asset["name"]
        platform = "mac" if name.endswith("-macos-local.dmg") else "windows" if name.endswith("-windows-x86_64-setup.exe") else "linux" if name.endswith("_amd64.deb") else None
        if platform:
            downloads[platform] = asset["browser_download_url"]
    if set(downloads) != {"mac", "windows", "linux"}:
        raise SystemExit("Latest release must contain Mac, Windows and Linux installers")
    (output / "release.json").write_text(json.dumps({"version": release["tag_name"], "downloads": downloads}) + "\n")
(output / ".nojekyll").touch()
print(f"Site staged at {output}")
