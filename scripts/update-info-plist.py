#!/usr/bin/env python3
from pathlib import Path
import plistlib
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
path.write_bytes(plistlib.dumps(info))
