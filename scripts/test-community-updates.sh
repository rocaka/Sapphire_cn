#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-community-update.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
python3 - "$ROOT" "$TEMP_DIR" <<'PY'
from pathlib import Path
import os, plistlib, subprocess, sys
root, temp = map(Path,sys.argv[1:])
s=(root/'Sapphire/App Settings/UpdateChecker.swift').read_text()
models=s[s.index('enum AppVersionOrdering'):s.index('enum UpdateStatus:')]
probe='''
@main struct Probe {
 static func main() throws {
 let json = #"[{"tag_name":"cn-2026.10.29-stability","prerelease":false,"draft":false,"published_at":"2026-10-29T03:00:00Z","assets":[]},{"tag_name":"cn-2026.10.29-progress-fix","prerelease":true,"draft":false,"published_at":"2026-10-29T09:30:00Z","assets":[]}]"#
 let releases=try JSONDecoder().decode([GitHubRelease].self,from:Data(json.utf8))
 precondition(releases.max(by:{CommunityReleaseOrdering.isOlder($0,than:$1)})?.tagName == "cn-2026.10.29-progress-fix")
 precondition(AppVersionOrdering.compare("v2026.1030.1","2026.1030.1") == .orderedSame)
 precondition(AppVersionOrdering.isNewer("2026.1101.1",than:"2026.1030.1"))
 precondition(!AppVersionOrdering.isNewer("2026.1030.1",than:"2026.1030.2"))
 print("Community publication ordering, preview selection and standard version matching passed")
 }
}
'''
(temp/'Probe.swift').write_text('import Foundation\n'+models+probe)
code=(root/'scripts/build-cn.sh').read_text().split('<<\'PY\'\n',1)[1].split('\nPY\n',1)[0]
app=temp/'Sapphire.fixture-data'
main=app/'Contents/Info.plist'; child=app/'Contents/PlugIns/Widget.appex/Contents/Info.plist'
for p,bid in [(main,'com.rocaka.sapphirecn'),(child,'com.rocaka.sapphirecn.widget')]:
 p.parent.mkdir(parents=True,exist_ok=True)
 p.write_bytes(plistlib.dumps({'CFBundleIdentifier':bid,'CFBundleShortVersionString':'0.9','CFBundleVersion':'1'}))
env=dict(os.environ,RELEASE_VERSION='2026.1030.1',GITHUB_RUN_NUMBER='999')
subprocess.run([sys.executable,'-',str(main)],input=code,text=True,check=True,cwd=root,env=env)
for p in [main,child]:
 data=plistlib.loads(p.read_bytes())
 assert data['CFBundleShortVersionString']=='2026.1030.1'
 assert data['CFBundleVersion']=='1'
print('Real packaging version stamp: host and embedded widget aligned; bundle build version preserved')
PY
xcrun swiftc -parse-as-library -module-cache-path "$TEMP_DIR/cache" "$TEMP_DIR/Probe.swift" -o "$TEMP_DIR/probe"
"$TEMP_DIR/probe"
