#!/usr/bin/env python3
"""Sign every nested executable/library, then containers, then the host app.

No security verification in the app/helper is disabled. An ad-hoc build cannot
use the root helper. Developer ID signing uses the same identity for all code.
"""
from pathlib import Path
import subprocess
import plistlib
import sys

app = Path(sys.argv[1]).resolve()
identity = sys.argv[2] if len(sys.argv) > 2 else "-"
if app.suffix != ".app" or not (app / "Contents/Info.plist").is_file():
    raise SystemExit("Expected an existing .app bundle")
root = Path(__file__).resolve().parent.parent
flags = ["--force", "--sign", identity]
flags += ["--timestamp=none"] if identity == "-" else ["--options", "runtime", "--timestamp"]
magic = {b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}

def sign(path, entitlements=None):
    command = ["/usr/bin/codesign", *flags]
    if entitlements:
        command += ["--entitlements", str(entitlements)]
    subprocess.run([*command, str(path)], check=True)

# A bundle's primary executable must be signed via its container, after its
# nested code. codesign on Contents/MacOS/<main> can implicitly sign the app.
bundle_suffixes = {".framework", ".appex", ".systemextension", ".driver", ".xpc", ".app"}
bundles = [app] + [p for p in app.rglob("*") if p.is_dir() and not p.is_symlink() and p.suffix in bundle_suffixes]
primary_executables = set()
for bundle in bundles:
    candidates = [bundle / "Contents/Info.plist", bundle / "Resources/Info.plist", bundle / "Info.plist"]
    for info in candidates:
        if not info.is_file():
            continue
        with info.open("rb") as stream:
            name = plistlib.load(stream).get("CFBundleExecutable")
        if name:
            executable = bundle / name if bundle.suffix == ".framework" else bundle / "Contents/MacOS" / name
            primary_executables.add(executable.resolve())
        break
for path in sorted(app.rglob("*"), key=lambda p: len(p.parts), reverse=True):
    if path.is_symlink() or not path.is_file() or path.resolve() in primary_executables:
        continue
    with path.open("rb") as stream:
        is_macho = stream.read(4) in magic
    if is_macho:
        sign(path)
for bundle in sorted((b for b in bundles if b != app), key=lambda p: len(p.parts), reverse=True):
    entitlements = root / "SapphireAndroidWidgets/SapphireAndroidWidgets.entitlements" if bundle.name == "SapphireAndroidWidgets.appex" else None
    sign(bundle, entitlements)
sign(app, root / "Sapphire/SapphirePublic.entitlements")
