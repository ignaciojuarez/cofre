# StikJIT patches

`scripts/stikjit-sources.sh` copies `upstream/stikjit/Sources` to `.work/stikjit/Sources` and applies these patches in
order; the PacketTunnel target builds that copy. Same rules as Air: at most 5, each with `Reason:` and `Drop when:`.

| Patch | Why |
|---|---|
| 0001 | Prepare JIT pages with full 64-bit addresses (regions above 64 GB crashed) |
