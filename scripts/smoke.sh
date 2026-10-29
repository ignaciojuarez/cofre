#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.."; pwd); cd "$ROOT"; fail=0
ok(){ echo "✓ $1"; }; no(){ echo "✗ $1"; fail=1; }
for n in air stikjit stikdebug; do [[ -d upstream/$n/.git || -f upstream/$n/.git ]] && ok "upstream/$n" || no "missing upstream/$n"; done
for f in app/CofreKit/CofreKit.swift app/Glue/AirBridge/AirBridgeAdapter.m extensions/PacketTunnel/PacketTunnelProvider.swift; do [[ -f $f ]] && ok "$f" || no "missing $f"; done
for n in air stikjit stikdebug; do c=$(find patches/$n -name '*.patch' 2>/dev/null | wc -l); ((c<=5)) && ok "$n patch budget $c" || no "$n patch budget"; done
[[ $(grep -c '^air\t' UPSTREAM.lock) -eq 1 ]] && ok 'UPSTREAM.lock' || no 'UPSTREAM.lock'
ipa=${1:-}; if [[ -n $ipa && -f $ipa ]]; then t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; unzip -q "$ipa" -d "$t"; app=$(find "$t/Payload" -maxdepth 1 -name '*.app' | head -1); [[ -d "$app/PlugIns/PacketTunnel.appex" ]] && ok appex || no appex; fi
exit $fail
