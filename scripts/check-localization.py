#!/usr/bin/env python3
"""Validate Apple .strings files, locale parity and format arguments on macOS."""
from pathlib import Path
import collections
import json
import re
import subprocess

root = Path(__file__).resolve().parent.parent

def read(path):
    subprocess.run(["plutil", "-lint", str(path)], check=True)
    data = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(path)]))
    keys = re.findall(r'^\s*("(?:[^"\\]|\\.)*")\s*=', path.read_text(), re.M)
    decoded = [json.loads(key) for key in keys]
    duplicates = [key for key, count in collections.Counter(decoded).items() if count > 1]
    assert not duplicates, f"Duplicate keys in {path}: {duplicates}"
    assert len(decoded) == len(data), f"Unparsed entries in {path}"
    return data

def arguments(text):
    # Ignore literal %, accept positional arguments and common Foundation types.
    pattern = r'%(?:(\d+)\$)?(?:[-+#0]*\d*(?:\.\d+)?)?(ll|l|z)?([@diuoxXfFeEgGcCsSp])'
    tokens = re.findall(pattern, text.replace("%%", ""))
    return sorted((position or str(index + 1), length, kind) for index, (position, length, kind) in enumerate(tokens))

for table in ["Localizable", "InfoPlist"]:
    en = read(root / f"Sapphire/en.lproj/{table}.strings")
    zh = read(root / f"Sapphire/zh-Hans.lproj/{table}.strings")
    assert en.keys() == zh.keys(), f"Locale keys differ in {table}"
    for key in en:
        assert zh[key].strip(), f"Empty translation: {key}"
        if '%' in en[key]:
            assert arguments(en[key]) == arguments(zh[key]), f"Format arguments differ: {key}"
    print(f"{table}: {len(en)} matching English/Chinese entries")
project = root / "Sapphire.xcodeproj/project.pbxproj"
subprocess.run(["plutil", "-lint", str(project)], check=True)
assert '"zh-Hans"' in project.read_text()
assert 'KVQFWJ7C7S' not in project.read_text(), "Upstream developer team must not sign the fork"
assert 'geteuid() != 0 && helper.isAdHoc && client.isAdHoc' in (root / "com.rocaka.sapphirecnHelper/CodesignCheckError.swift").read_text(), "Privileged helper trust check changed"
print("Localization, project and helper signing invariants passed")
