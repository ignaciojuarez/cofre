# Cofre runners

```sh
# Phone attached to this Mac
scripts/run.sh local fast
scripts/run.sh local sim

# Phone attached to the configured MacBook over SSH
scripts/run.sh remote fast
```

`RELAY_HOST` and `RELAY_DEVICE_ID` belong in the uncommitted
`scripts/run.local.config`. The runner uses Cofre's normal Air build, then
installs and launches with `devicectl` locally or the SSH relay remotely.

