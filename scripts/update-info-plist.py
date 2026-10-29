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
    "LSItemContentTypes": ["com.apple.mobiledevicepairing", "com.apple.property-list"],
}]
info["UTImportedTypeDeclarations"] = [{
    "UTTypeIdentifier": "com.apple.mobiledevicepairing",
    "UTTypeConformsTo": ["public.data"],
    "UTTypeTagSpecification": {
        "public.filename-extension": ["mobiledevicepairing", "plist"],
    },
}]
# Cofre's own version for Settings → About. CFBundleShortVersionString stays Air's: Air's update checks read it.
info["CofreVersion"] = "0.1"
info["CofreBuild"] = subprocess.run(
    ["git", "-C", str(Path(__file__).parent), "rev-parse", "--short", "HEAD"], capture_output=True, text=True
).stdout.strip()
path.write_bytes(plistlib.dumps(info))
