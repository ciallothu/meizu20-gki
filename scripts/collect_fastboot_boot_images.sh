#!/usr/bin/env bash
set -euo pipefail

dist_dir="${1:?dist dir is required}"
out_dir="${2:?artifact dir is required}"
reports_dir="${3:?reports dir is required}"
kernel_format="${4:-Image}"
stock_boot="${5:-}"

mkdir -p "${out_dir}" "${reports_dir}"
summary="${reports_dir}/fastboot-boot-summary.txt"
: > "${summary}"

log() {
  echo "$*" | tee -a "${summary}"
}

log "kernel_format=${kernel_format}"
log "dist_dir=${dist_dir}"
log "stock_boot=${stock_boot:-<none>}"

generated_magiskboot=0

case "${kernel_format}" in
  Image) kernel="${dist_dir}/Image" ;;
  Image.gz) kernel="${dist_dir}/Image.gz" ;;
  Image.lz4) kernel="${dist_dir}/Image.lz4" ;;
  *) kernel="" ;;
esac

download_magisk_apk() {
  local version="$1"
  local dest="$2"
  local base="https://github.com/topjohnwu/Magisk/releases/download/${version}"
  local candidates=(
    "Magisk-${version}.apk"
    "Magisk-${version#v}.apk"
    "app-release.apk"
    "app-debug.apk"
  )
  local name

  for name in "${candidates[@]}"; do
    log "magisk_apk_try=${base}/${name}"
    if curl -fsSL "${base}/${name}" -o "${dest}"; then
      log "magisk_apk=${name}"
      return 0
    fi
  done
  return 1
}

if [[ -n "${stock_boot}" && -f "${stock_boot}" && -f "${kernel}" ]]; then
  work_dir="$(mktemp -d)"
  magisk_version="${MAGISK_VERSION:-v30.7}"
  magisk_apk="${work_dir}/Magisk.apk"
  magiskboot="${work_dir}/magiskboot"
  out_img="${out_dir}/boot-magiskboot-${kernel_format//./-}.img"

  log "magiskboot_source=topjohnwu/Magisk ${magisk_version}"
  if download_magisk_apk "${magisk_version}" "${magisk_apk}" &&
     unzip -p "${magisk_apk}" lib/x86_64/libmagiskboot.so > "${magiskboot}"; then
    chmod +x "${magiskboot}"

    cp "${stock_boot}" "${work_dir}/boot.img"
    if (
      cd "${work_dir}"
      ./magiskboot unpack -h boot.img
      cp "${kernel}" kernel
      PATCHVBMETAFLAG=true ./magiskboot repack boot.img "${out_img}"
    ) 2>&1 | tee -a "${summary}"; then
      if [[ -f "${out_img}" ]]; then
        log "generated_magiskboot_boot=$(basename "${out_img}")"
        log "generated_magiskboot_boot_size=$(wc -c < "${out_img}")"
        generated_magiskboot=1
      else
        log "generated_magiskboot_boot=missing_output"
      fi
    else
      log "generated_magiskboot_boot=repack_failed"
    fi
  else
    log "generated_magiskboot_boot=magiskboot_unavailable"
  fi
  rm -rf "${work_dir}"
fi

copied=0
if [[ "${generated_magiskboot}" -eq 0 ]]; then
  while IFS= read -r -d '' img; do
    base="$(basename "${img}")"
    case "${base}" in
      boot*.img|*boot*.img)
        cp "${img}" "${out_dir}/${base}"
        log "copied_dist_boot=${base}"
        copied=$((copied + 1))
      ;;
    esac
  done < <(find "${dist_dir}" -maxdepth 1 -type f -name '*boot*.img' -print0 | sort -z)
else
  log "copied_dist_boot=skipped_magiskboot_available"
fi

if [[ "${copied}" -eq 0 && "${generated_magiskboot}" -eq 0 ]]; then
  log "copied_dist_boot=0"
  workspace_dir="${GITHUB_WORKSPACE:-${PWD}}/workspace"
  if [[ -d "${workspace_dir}" ]]; then
    mkbootimg_py="$(find "${workspace_dir}" -type f -name mkbootimg.py | head -n 1 || true)"
  else
    mkbootimg_py=""
  fi
  if [[ -n "${mkbootimg_py}" && -f "${kernel}" ]]; then
    out_img="${out_dir}/boot-generic-${kernel_format//./-}.img"
    python3 "${mkbootimg_py}" \
      --header_version 4 \
      --kernel "${kernel}" \
      --os_version 13.0.0 \
      --os_patch_level 2023-10 \
      --output "${out_img}"
    log "generated_generic_boot=$(basename "${out_img}")"
  else
    log "generated_generic_boot=skipped"
    log "mkbootimg_py=${mkbootimg_py:-<missing>}"
    log "kernel=${kernel:-<unsupported>}"
  fi
fi

log "note=Fastboot boot images are generated with Magisk magiskboot from the stock Meizu boot template when available. Generic boot images are only fallback artifacts."
