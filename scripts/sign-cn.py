#!/usr/bin/env python3
"""Sign every nested executable/library, then containers, then the host app.

No security verification in the app/helper is disabled. An ad-hoc build cannot
use the root helper. Developer ID signing uses the same identity for all code.
"""
from pathlib import Path
import subprocess
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

# Do not follow framework symlinks or sign a linked file twice.
for path in sorted(app.rglob("*"), key=lambda p: len(p.parts), reverse=True):
    if path.is_symlink() or not path.is_file():
        continue
    with path.open("rb") as stream:
        is_macho = stream.read(4) in magic
    if is_macho:
        sign(path)
for path in sorted(app.rglob("*"), key=lambda p: len(p.parts), reverse=True):
    if path.is_symlink() or not path.is_dir():
        continue
    if path.suffix in {".framework", ".appex", ".systemextension", ".driver", ".xpc", ".app"}:
        entitlements = root / "SapphireAndroidWidgets/SapphireAndroidWidgets.entitlements" if path.name == "SapphireAndroidWidgets.appex" else None
        sign(path, entitlements)
sign(app, root / "Sapphire/SapphirePublic.entitlements")
