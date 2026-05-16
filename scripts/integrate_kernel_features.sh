#!/usr/bin/env bash
set -euo pipefail

feature_set="${1:-full}"
strategy="${2:-A}"
common="${3:?common source dir is required}"
repo_root="${4:?repo root is required}"

cd "${common}"

relax_kleaf_checks() {
  python3 - <<'PY'
from pathlib import Path
import re

path = Path("BUILD.bazel")
text = path.read_text()
text = text.replace("check_defconfig = True", "check_defconfig = False")
path.write_text(text)

kleaf = Path("../build/kernel/kleaf/common_kernels.bzl")
text = kleaf.read_text()
text, _ = re.subn(
    r'check_defconfig = select\(\{.*?\}\),',
    'check_defconfig = "disabled",',
    text,
    count=1,
    flags=re.S,
)
text = text.replace(
    '"kmi_symbol_list_strict_mode": aarch64_trim_and_check,',
    '"kmi_symbol_list_strict_mode": False,',
)
kleaf.write_text(text)

kernel_config = Path("../build/kernel/kleaf/impl/kernel_config.bzl")
text = kernel_config.read_text()
text = text.replace(
    'if check_defconfig_attr_value != "minimized":',
    'if True or check_defconfig_attr_value != "minimized":',
    1,
)
text = text.replace(
    'if check_defconfig_attr_value == "disabled":',
    'if True or check_defconfig_attr_value == "disabled":',
    1,
)
kernel_config.write_text(text)

build_utils = Path("../build/kernel/build_utils.sh")
with build_utils.open("a") as f:
    f.write(
        "\n# Meizu 20 Actions build: allow generated GKI defconfig fragments.\n"
        "kleaf_internal_check_defconfig_minimized() { return 0; }\n"
        "kleaf_internal_check_dot_config_against_defconfig() { return 0; }\n"
    )
PY
}

apply_crc_support() {
  python3 "${repo_root}/scripts/apply_crc_override_patch.py" "${common}"
  cp "${repo_root}/data/original_crcs.tsv" .meizu_crc_overrides.tsv
}

apply_sukisu_susfs() {
  curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash -s main
  rm -rf KernelSU/.git
  test -f drivers/kernelsu/Kconfig

  susfs="${repo_root}/workspace/susfs"
  git clone --depth=1 -b gki-android13-5.15 https://gitlab.com/simonpunk/susfs4ksu.git "${susfs}"
  cp -r "${susfs}/kernel_patches/fs/"* fs/
  cp -r "${susfs}/kernel_patches/include/linux/"* include/linux/
  patch -p1 --forward --batch < "${susfs}/kernel_patches/50_add_susfs_in_gki-android13-5.15.patch"
  (
    cd KernelSU
    patch -p1 --forward --batch < "${susfs}/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
  )
}

apply_fragment_file() {
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    [[ "${line}" == \#* && "${line}" != "# CONFIG_"* ]] && continue
    if [[ "${line}" =~ ^CONFIG_([^=]+)=y$ ]]; then
      ./scripts/config --file arch/arm64/configs/gki_defconfig --enable "${BASH_REMATCH[1]}"
    elif [[ "${line}" =~ ^CONFIG_([^=]+)=m$ ]]; then
      ./scripts/config --file arch/arm64/configs/gki_defconfig --module "${BASH_REMATCH[1]}"
    elif [[ "${line}" =~ ^#\ CONFIG_([^[:space:]]+)\ is\ not\ set$ ]]; then
      ./scripts/config --file arch/arm64/configs/gki_defconfig --disable "${BASH_REMATCH[1]}"
    fi
  done < "${repo_root}/data/meizu20.fragment"
}

apply_droidspaces_only_config() {
  for opt in \
    NAMESPACES PID_NS IPC_NS SYSVIPC POSIX_MQUEUE \
    DEVTMPFS DEVTMPFS_MOUNT CGROUP_DEVICE CGROUP_PIDS MEMCG \
    MODVERSIONS MODULE_SIG; do
    ./scripts/config --file arch/arm64/configs/gki_defconfig --enable "${opt}"
  done
  ./scripts/config --file arch/arm64/configs/gki_defconfig --disable MODULE_SIG_FORCE
}

relax_kleaf_checks

case "${feature_set}" in
  minimal)
    echo "[feature_set=minimal] Build plain GKI plus local version only."
    ;;
  droidspaces)
    echo "[feature_set=droidspaces] Build Droidspaces namespace/devtmpfs features without KSU/SUSFS."
    apply_crc_support
    apply_droidspaces_only_config
    ;;
  full)
    echo "[feature_set=full] Build SukiSU Ultra + SUSFS + Droidspaces features."
    apply_sukisu_susfs
    apply_crc_support
    apply_fragment_file
    ;;
  *)
    echo "Unsupported feature_set=${feature_set}. Use minimal, droidspaces, or full." >&2
    exit 1
    ;;
esac

if [[ "${strategy}" == "B" ]]; then
  patch -p1 --forward --batch < "${repo_root}/patches/strategy-b/module-version-bypass.patch"
fi

./scripts/config --file arch/arm64/configs/gki_defconfig --set-str LOCALVERSION "-android13-8-gdae8b7f03305-ab1764128685"
./scripts/config --file arch/arm64/configs/gki_defconfig --disable LOCALVERSION_AUTO
./scripts/config --file arch/arm64/configs/gki_defconfig --disable MODULE_SIG_FORCE

tmp_config_out="$(mktemp -d)"
make -C . ARCH=arm64 O="${tmp_config_out}" gki_defconfig savedefconfig
cp "${tmp_config_out}/defconfig" arch/arm64/configs/gki_defconfig
rm -rf "${tmp_config_out}"

# Prevent local patch state from leaking into the kernel release string as -dirty/-maybe-dirty.
git add -A
git commit -m "Apply Meizu 20 ${feature_set} GKI patches" || true
git status --short
