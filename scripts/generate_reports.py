#!/usr/bin/env python3
from pathlib import Path
import os
import re
import sys


def load_crcs(path: Path) -> dict[str, str]:
    crcs: dict[str, str] = {}
    if not path.exists():
        return crcs
    for line in path.read_text(errors="ignore").splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        if parts[0].startswith("0x"):
            crcs[parts[1]] = parts[0].lower()
        elif parts[1].startswith("0x"):
            crcs[parts[0]] = parts[1].lower()
    return crcs


def load_symvers(path: Path) -> dict[str, str]:
    symbols: dict[str, str] = {}
    if not path.exists():
        return symbols
    for line in path.read_text(errors="ignore").splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0].startswith("0x"):
            symbols[parts[1]] = parts[0].lower()
    return symbols


def grep_config(config: Path, names: list[str]) -> list[str]:
    lines = config.read_text(errors="ignore").splitlines() if config.exists() else []
    out: list[str] = []
    for name in names:
        prefix = f"CONFIG_{name}="
        disabled = f"# CONFIG_{name} is not set"
        value = next((line for line in lines if line.startswith(prefix) or line == disabled), None)
        out.append(value or f"CONFIG_{name}=<missing>")
    return out


def main() -> None:
    if len(sys.argv) != 6:
        raise SystemExit("usage: generate_reports.py <strategy> <dist> <data> <reports> <gki-tag>")
    strategy = sys.argv[1]
    dist = Path(sys.argv[2])
    data = Path(sys.argv[3])
    reports = Path(sys.argv[4])
    gki_tag = sys.argv[5]
    reports.mkdir(parents=True, exist_ok=True)

    symvers = load_symvers(dist / "Module.symvers")
    stock_crcs = load_crcs(data / "original_crcs.tsv")
    overlap = sorted(set(symvers) & set(stock_crcs))
    mismatches = [s for s in overlap if symvers[s] != stock_crcs[s]]
    missing_from_build = sorted(set(stock_crcs) - set(symvers))

    (reports / "crc-summary.txt").write_text(
        "\n".join(
            [
                f"strategy={strategy}",
                f"gki_tag={gki_tag}",
                f"stock_crc_symbols={len(stock_crcs)}",
                f"built_exported_symbols={len(symvers)}",
                f"overlap={len(overlap)}",
                f"matching_crc={len(overlap) - len(mismatches)}",
                f"mismatching_crc={len(mismatches)}",
                f"stock_symbols_missing_from_build={len(missing_from_build)}",
                "",
                "[first mismatches]",
                *[f"{s} stock={stock_crcs[s]} built={symvers[s]}" for s in mismatches[:200]],
                "",
                "[first stock symbols missing from build]",
                *missing_from_build[:200],
            ]
        )
        + "\n"
    )

    config = dist / "kernel.config"
    if not config.exists():
        config = dist / ".config"
    config_names = [
        "LOCALVERSION",
        "LOCALVERSION_AUTO",
        "NAMESPACES",
        "PID_NS",
        "IPC_NS",
        "SYSVIPC",
        "POSIX_MQUEUE",
        "DEVTMPFS",
        "DEVTMPFS_MOUNT",
        "MODVERSIONS",
        "MODULE_SIG",
        "MODULE_SIG_FORCE",
        "MODULE_SIG_ALL",
        "PRINTK",
        "LOG_BUF_SHIFT",
        "PRINTK_SAFE_LOG_BUF_SHIFT",
        "PANIC_TIMEOUT",
        "PSTORE",
        "PSTORE_CONSOLE",
        "PSTORE_PMSG",
        "PSTORE_RAM",
        "KSU",
        "KSU_SUSFS",
    ]
    (reports / "config-check.txt").write_text("\n".join(grep_config(config, config_names)) + "\n")

    vendor_vermagic = data / "vendor-vermagic.txt"
    (reports / "vermagic-risk.txt").write_text(
        "\n".join(
            [
                f"strategy={strategy}",
                "stock_vendor_module_vermagic:",
                vendor_vermagic.read_text(errors="ignore").strip() if vendor_vermagic.exists() else "<missing>",
                "",
                "note:",
                "Branch A preserves module loader checks. With CONFIG_MODVERSIONS=y, Android 5.15 same_magic() ignores the version prefix and compares the feature tail after the first space.",
                "CRC mismatches still reject modules on branch A.",
                "Branch B accepts vermagic and CRC mismatches but logs warnings.",
            ]
        )
        + "\n"
    )

    release_notes = reports / "release-notes.md"
    release_notes.write_text(
        "\n".join(
            [
                f"# Meizu 20 GKI strategy {strategy}",
                "",
                f"- GKI tag: `{gki_tag}`",
                f"- GitHub run: `{os.environ.get('GITHUB_RUN_ID', '<local>')}`",
                "- Artifacts: AnyKernel3 zip, Image, Image.gz, Module.symvers, kernel.config, reports",
                "- Stock vendor_boot, dtbo, and vendor_dlkm are not modified by this package.",
                "",
                "Check `reports/config-check.txt`, `reports/crc-summary.txt`, and `reports/vermagic-risk.txt` before flashing.",
                "If the kernel reaches a panic/reboot path, check `/sys/fs/pstore/console-ramoops*` after the next successful boot.",
            ]
        )
        + "\n"
    )


if __name__ == "__main__":
    main()
