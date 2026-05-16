#!/usr/bin/env python3
from __future__ import annotations

import argparse
import struct
from pathlib import Path

BOOT_MAGIC = b"ANDROID!"
PAGE_SIZE = 4096


def align(value: int, alignment: int = PAGE_SIZE) -> int:
    return (value + alignment - 1) // alignment * alignment


def decode_boot_header(data: bytes) -> dict[str, int]:
    if data[:8] != BOOT_MAGIC:
        raise SystemExit("input is not an Android boot image: missing ANDROID! magic")
    if len(data) < PAGE_SIZE:
        raise SystemExit("input boot image is too small")

    kernel_size, ramdisk_size, os_version, header_size = struct.unpack_from("<IIII", data, 8)
    header_version = struct.unpack_from("<I", data, 40)[0]
    if header_version not in (3, 4):
        raise SystemExit(f"only boot header v3/v4 is supported, got v{header_version}")
    if header_size <= 0 or header_size > PAGE_SIZE:
        raise SystemExit(f"unexpected header_size={header_size}")

    signature_size = 0
    if header_version >= 4 and header_size >= 1584:
        signature_size = struct.unpack_from("<I", data, 1580)[0]

    kernel_offset = PAGE_SIZE
    ramdisk_offset = align(kernel_offset + kernel_size)
    signature_offset = align(ramdisk_offset + ramdisk_size)

    if kernel_offset + kernel_size > len(data):
        raise SystemExit("kernel extends beyond input boot image")
    if ramdisk_size and ramdisk_offset + ramdisk_size > len(data):
        raise SystemExit("ramdisk extends beyond input boot image")
    if signature_size and signature_offset + signature_size > len(data):
        raise SystemExit("boot signature extends beyond input boot image")

    return {
        "kernel_size": kernel_size,
        "ramdisk_size": ramdisk_size,
        "os_version": os_version,
        "header_size": header_size,
        "header_version": header_version,
        "signature_size": signature_size,
        "kernel_offset": kernel_offset,
        "ramdisk_offset": ramdisk_offset,
        "signature_offset": signature_offset,
    }


def kernel_kind(kernel: bytes) -> str:
    if kernel.startswith(b"\x1f\x8b"):
        return "gzip"
    if kernel.startswith(bytes.fromhex("02214c18")):
        return "lz4-legacy"
    if kernel.startswith(bytes.fromhex("04224d18")):
        return "lz4-frame"
    if kernel.startswith(b"MZ"):
        return "arm64-Image"
    return "unknown"


def main() -> None:
    parser = argparse.ArgumentParser(description="Replace the kernel inside an Android boot v3/v4 image while preserving the stock header and ramdisk.")
    parser.add_argument("base_boot", type=Path, help="stock boot.img used as template")
    parser.add_argument("kernel", type=Path, help="replacement kernel Image/Image.gz/Image.lz4")
    parser.add_argument("output", type=Path, help="output boot.img")
    parser.add_argument("--no-preserve-size", action="store_true", help="do not pad output to the original boot image size")
    args = parser.parse_args()

    base = args.base_boot.read_bytes()
    new_kernel = args.kernel.read_bytes()
    info = decode_boot_header(base)

    header = bytearray(base[:PAGE_SIZE])
    struct.pack_into("<I", header, 8, len(new_kernel))
    if info["header_version"] >= 4 and info["header_size"] >= 1584:
        # Replacing the kernel invalidates any v4 boot signature. The Meizu 20 stock boot
        # currently has signature_size=0, but force this to zero for safety.
        struct.pack_into("<I", header, 1580, 0)

    old_ramdisk = b""
    if info["ramdisk_size"]:
        start = info["ramdisk_offset"]
        old_ramdisk = base[start:start + info["ramdisk_size"]]

    out = bytearray(header)
    out.extend(new_kernel)
    out.extend(b"\x00" * (align(len(out)) - len(out)))
    if old_ramdisk:
        out.extend(old_ramdisk)
        out.extend(b"\x00" * (align(len(out)) - len(out)))

    if not args.no_preserve_size:
        if len(out) > len(base):
            raise SystemExit(f"new boot image is larger than base boot image: {len(out)} > {len(base)}")
        out.extend(b"\x00" * (len(base) - len(out)))

    args.output.write_bytes(out)

    print(f"base_header_version={info['header_version']}")
    print(f"base_header_size={info['header_size']}")
    print(f"base_kernel_size={info['kernel_size']}")
    print(f"new_kernel_size={len(new_kernel)}")
    print(f"base_ramdisk_size={info['ramdisk_size']}")
    print(f"base_signature_size={info['signature_size']}")
    print(f"new_kernel_kind={kernel_kind(new_kernel)}")
    print(f"output={args.output}")
    print(f"output_size={len(out)}")


if __name__ == "__main__":
    main()
