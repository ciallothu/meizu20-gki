# Meizu 20 GKI A/B kernel builds

This repository builds experimental Meizu 20 GKI kernels. The default build is
a stock-like compatibility baseline pinned to the same 5.15.119 Android common
kernel family as the device, with Meizu CRC/module compatibility handled before
adding Droidspaces, SukiSU Ultra, or SUSFS.

The build runs on GitHub Actions only. Release artifacts are AnyKernel3 zip
packages plus raw `Image` / `Image.gz` and diagnostics. Stock `boot.img`,
`vendor_boot.img`, `dtbo.img`, and `vendor_dlkm.img` are intentionally not
stored here.

## Device baseline

Current target baseline:

- Device: `meizu20`
- Platform: Qualcomm SM8550 / kalama
- Android userspace: 16 / SDK 36
- Vendor baseline: Android 13 / SDK 33
- Stock kernel: `5.15.119-android13-8-gdae8b7f03305-ab1764128685`
- Stock build string: `#1 SMP PREEMPT Tue Jan 27 20:32:22 UTC 2026`
- Stock missing features: `PID_NS`, `SYSVIPC`, `POSIX_MQUEUE`, `DEVTMPFS`
- Stock module policy: `MODVERSIONS=y`, `MODULE_SIG=y`, `MODULE_SIG_ALL=y`,
  `MODULE_SIG_FORCE=n`

Vendor modules currently report two version prefixes:

- `5.15.119-g22235541249b-ab1764128685 SMP preempt mod_unload modversions aarch64`
- `5.15.119-g22235541249b-dirty SMP preempt mod_unload modversions aarch64`

Because Android's `same_magic()` ignores the version prefix when module CRCs
exist, branch A focuses on CRC/export matching while preserving strict checks.

## Branches

- `A`: strict module loader. It keeps vermagic and CRC checks enabled, forces
  stock-style `uname -r`, and applies pre-build CRC overrides through
  `genksyms` so generated kernel CRC tables can match extracted stock CRCs
  where symbol names overlap.
- `B`: same selected feature set, but patches module loading to accept vermagic
  and CRC mismatches while keeping warning logs.

## Running builds

Use GitHub Actions manually:

```sh
gh workflow run build-kernel.yml -r A -f strategy=A -f feature_set=compat
gh workflow run build-kernel.yml -r B -f strategy=B -f feature_set=compat
```

`minimal` is available only as a packaging and early boot-chain sanity check:

```sh
gh workflow run build-kernel.yml -r A -f strategy=A -f feature_set=minimal
gh workflow run build-kernel.yml -r B -f strategy=B -f feature_set=minimal
```

Successful runs create a pre-release named:

```text
pr-<run_number>-<short_sha>
```

Each release contains:

- `AnyKernel3-Meizu20-A.zip` or `AnyKernel3-Meizu20-B.zip`
- `Image`
- `Image.gz`
- `Image.lz4`
- fastboot boot image when stock boot repacking succeeds
- `Module.symvers`
- `kernel.config`
- reports under `reports/`

## Flashing note

These builds are experimental. Test `feature_set=compat` first because the
closed-source Meizu vendor modules need either matching CRCs or the branch B
loader bypass. Only move to `droidspaces` or `full` after the compatibility
kernel reaches Android userspace. The AnyKernel package only replaces the boot
kernel and leaves `vendor_boot`, `dtbo`, and `vendor_dlkm` untouched.

## Boot failure logs

`compat`, `droidspaces`, and `full` enable pstore/ramoops console capture. If a
test kernel reaches a panic path and reboots, boot back into a working kernel or
recovery and check:

```sh
adb shell su -c 'ls -l /sys/fs/pstore; cat /sys/fs/pstore/console-ramoops* 2>/dev/null'
```

Printing directly over the MEIZU logo is usually not useful on this device
class because the Android display stack is not a kernel text console at that
stage.
