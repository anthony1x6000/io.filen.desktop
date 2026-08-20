#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
import datetime
import sys
import xml.etree.ElementTree as ET

if len(sys.argv) < 2:
    print("Usage: update-metainfo.py <VERSION> [DATE]", file=sys.stderr)
    sys.exit(1)

version = sys.argv[1]
date_str = sys.argv[2] if len(sys.argv) > 2 else datetime.date.today().strftime("%Y-%m-%d")

metainfo_file = "io.filen.desktop.metainfo.xml"
tree = ET.parse(metainfo_file)
root = tree.getroot()
releases = root.find("releases")

if releases is not None:
    for r in releases.findall("release"):
        if r.get("version") == version:
            print(f"Release {version} already exists in {metainfo_file}")
            sys.exit(0)

    new_release = ET.Element("release", {"version": version, "date": date_str})
    desc = ET.SubElement(new_release, "description")
    p = ET.SubElement(desc, "p")
    p.text = f"Automatic update to version {version}"

    releases.insert(0, new_release)
    ET.indent(tree, space="  ", level=0)
    tree.write(metainfo_file, encoding="utf-8", xml_declaration=True)
    print(f"✓ Added release {version} ({date_str}) to {metainfo_file}")
