# Round 4a simulator build notes

- HEAD tested: `192a226`
- Build script: `scripts/sim.sh`
- Output: `/tmp/cofre-sim-head`
- Install target: iPad `SIMULATOR_UDID`
- Script validation: every Mach-O under the app was checked for `LC_BUILD_VERSION platform IOSSIMULATOR`; nested code was re-signed inside-out.
- Install passed. Launch returned simulator `NSPOSIXErrorDomain code=3` with no process, so interactive verification could not proceed.
- UI tests passed: 48/48. Whole-app compile remains blocked by the two existing UIKit notification names in `app/Shell/CofreRootViewController.swift`.
