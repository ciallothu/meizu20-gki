### AnyKernel3 Ramdisk Mod Script

properties() { '
kernel.string=Meizu20 GKI SukiSU Ultra SUSFS
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=meizu20
device.name2=M2381
device.name3=m2381
device.name4=M381Q
device.name5=m381q
supported.versions=13 - 16
supported.patchlevels=
supported.vendorpatchlevels=
'; }

block=boot;
is_slot_device=auto;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;

. tools/ak3-core.sh;

# Android 13+ launch devices keep the generic ramdisk in init_boot.
# Meizu 20 boot is expected to be kernel-only, so avoid ramdisk unpack/repack.
split_boot;
flash_boot;
