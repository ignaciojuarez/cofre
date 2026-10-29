#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT/core"
cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-apple-darwin
mkdir -p target/universal "$ROOT/App/Resources"
lipo -create target/aarch64-apple-darwin/release/llave-pair target/x86_64-apple-darwin/release/llave-pair -output target/universal/llave-pair
cp target/universal/llave-pair "$ROOT/App/Resources/llave-pair"; chmod 755 "$ROOT/App/Resources/llave-pair"
(cd "$ROOT/App" && xcodegen generate)
xcodebuild -project "$ROOT/App/Llave.xcodeproj" -scheme Llave -configuration Release -derivedDataPath "$ROOT/build/DerivedData" CODE_SIGNING_ALLOWED=NO build
mkdir -p "$ROOT/build"; rm -rf "$ROOT/build/Llave.app"; cp -R "$ROOT/build/DerivedData/Build/Products/Release/Llave.app" "$ROOT/build/Llave.app"
IDENTITY=$(security find-identity -v -p codesigning | awk -F '"' '/Developer ID Application:/ {print $2; exit}')
[ -n "$IDENTITY" ] || { echo "Developer ID Application identity not found" >&2; exit 1; }
codesign --force --deep --sign "$IDENTITY" --timestamp=none "$ROOT/build/Llave.app"
codesign --verify --deep --strict "$ROOT/build/Llave.app"
echo "Built and signed $ROOT/build/Llave.app"
