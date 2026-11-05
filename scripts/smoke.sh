#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.."; pwd)
cd "$ROOT"
fail=0
ok() { echo "✓ $1"; }
no() { echo "✗ $1"; fail=1; }
for n in air stikjit stikdebug; do [[ -d upstream/$n/.git || -f upstream/$n/.git ]] && ok "upstream/$n" || no "missing upstream/$n"; done
for f in app/Glue/AirBridge/CofreBackendAdapter.swift app/Glue/AirBridge/AirBridgeAdapter.m extensions/PacketTunnel/PacketTunnelProvider.swift; do [[ -f $f ]] && ok "$f" || no "missing $f"; done
for n in air stikjit stikdebug graft metallum; do c=$(find patches/$n -name '*.patch' 2>/dev/null | wc -l); ((c<=5)) && ok "$n patch budget $c" || no "$n patch budget"; done
[[ $(grep -c '^air\t' UPSTREAM.lock) -eq 1 ]] && ok 'UPSTREAM.lock' || no 'UPSTREAM.lock'
expected_app=com.ignacio.cofre
expected_tunnel=com.ignacio.cofre.tunnel
expected_core=com.ignacio.cofre.core
config_app=$(sed -n 's/^BUNDLE_ID=\${BUNDLE_ID:-\([^}]*\)}$/\1/p' scripts/run.config)
config_tunnel=$(sed -n 's/^TUNNEL_BUNDLE_ID=\${TUNNEL_BUNDLE_ID:-\([^}]*\)}$/\1/p' scripts/run.config)
[[ "$config_app" == "$expected_app" ]] && ok 'app bundle ID in run.config' || no 'app bundle ID in run.config'
[[ "$config_tunnel" == "$expected_tunnel" ]] && ok 'tunnel bundle ID in run.config' || no 'tunnel bundle ID in run.config'
grep -q "COFRE_TUNNEL_BUNDLE_ID @\"$expected_tunnel\"" app/Glue/CofreConstants.h && ok 'tunnel bundle ID in CofreConstants.h' || no 'tunnel bundle ID in CofreConstants.h'
grep -q "tunnelBundleID = \"$expected_tunnel\"" app/Glue/CofreConstants.swift && ok 'tunnel bundle ID in CofreConstants.swift' || no 'tunnel bundle ID in CofreConstants.swift'
grep -q 'PRODUCT_BUNDLE_IDENTIFIER: ${BUNDLE_ID}' .build-tools/signing/project.yml && ok 'app bundle ID in signing project' || no 'app bundle ID in signing project'
grep -q 'PRODUCT_BUNDLE_IDENTIFIER: ${TUNNEL_BUNDLE_ID}' .build-tools/signing/project.yml && ok 'tunnel bundle ID in signing project' || no 'tunnel bundle ID in signing project'
grep -q "PRODUCT_BUNDLE_IDENTIFIER: $expected_core" .build-tools/signing/project.yml && ok 'core bundle ID in signing project' || no 'core bundle ID in signing project'
ipa=${1:-}; if [[ -n $ipa && -f $ipa ]]; then t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; unzip -q "$ipa" -d "$t"; app=$(find "$t/Payload" -maxdepth 1 -name '*.app' | head -1); [[ -d "$app/PlugIns/PacketTunnel.appex" ]] && ok appex || no appex; fi
exit $fail
