#!/usr/bin/env python3
"""Fetch PrismarineJS's maintained protocol map into the shipped snapshot."""
import json, pathlib, urllib.request
url='https://raw.githubusercontent.com/PrismarineJS/minecraft-data/master/data/pc/common/protocolVersions.json'
data=urllib.request.urlopen(url, timeout=30).read()
out=pathlib.Path(__file__).parent.parent/'app/UI/Sources/CofreKit/Resources/protocolVersions.json'
out.write_bytes(data)
