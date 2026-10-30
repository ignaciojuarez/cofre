#!/usr/bin/env python3
from pathlib import Path
import plistlib
import subprocess
import sys

path = Path(sys.argv[1])
info = plistlib.loads(path.read_bytes())
info["CFBundleURLTypes"] = [{"CFBundleURLSchemes": ["cofre"]}]
info["CFBundleDocumentTypes"] = [{
    "CFBundleTypeName": "iPhone Pairing File",
    "LSItemContentTypes": ["com.apple.mobiledevicepairing", "com.apple.property-list", "com.cofre.mrpack", "public.zip-archive", "com.cofre.mcworld"],
}]
info["UTImportedTypeDeclarations"] = [{
    "UTTypeIdentifier": "com.apple.mobiledevicepairing",
    "UTTypeConformsTo": ["public.data"],
    "UTTypeTagSpecification": {
        "public.filename-extension": ["mobiledevicepairing", "plist"],
    },
}, {
    "UTTypeIdentifier": "com.cofre.mrpack", "UTTypeConformsTo": ["public.zip-archive"],
    "UTTypeTagSpecification": {"public.filename-extension": ["mrpack"]},
}, {
    "UTTypeIdentifier": "com.cofre.mcworld", "UTTypeConformsTo": ["public.zip-archive"],
    "UTTypeTagSpecification": {"public.filename-extension": ["mcworld"]},
}]
# Cofre's own version for Settings → About. CFBundleShortVersionString stays Air's: Air's update checks read it.
info["CofreVersion"] = "0.1"
info["CofreBuildNumber"] = int(subprocess.run(
    ["git", "-C", str(Path(__file__).parent), "rev-list", "--count", "HEAD"], capture_output=True, text=True
).stdout.strip() or "0")
info["CofreBuild"] = subprocess.run(
    ["git", "-C", str(Path(__file__).parent), "rev-parse", "--short", "HEAD"], capture_output=True, text=True
).stdout.strip()
path.write_bytes(plistlib.dumps(info))
