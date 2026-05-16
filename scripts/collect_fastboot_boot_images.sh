#!/usr/bin/env bash
set -euo pipefail

dist_dir="${1:?dist dir is required}"
out_dir="${2:?artifact dir is required}"
reports_dir="${3:?reports dir is required}"
kernel_format="${4:-Image.gz}"

mkdir -p "${out_dir}" "${reports_dir}"
summary="${reports_dir}/fastboot-boot-summary.txt"
: > "${summary}"

log() {
  echo "$*" | tee -a "${summary}"
}

log "kernel_format=${kernel_format}"
log "dist_dir=${dist_dir}"

copied=0
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

case "${kernel_format}" in
  Image) kernel="${dist_dir}/Image" ;;
  Image.gz) kernel="${dist_dir}/Image.gz" ;;
  Image.lz4) kernel="${dist_dir}/Image.lz4" ;;
  *) kernel="" ;;
esac

if [[ "${copied}" -eq 0 ]]; then
  log "copied_dist_boot=0"
  mkbootimg_py="$(find "${GITHUB_WORKSPACE:-${PWD}}/workspace" -type f -name mkbootimg.py | head -n 1 || true)"
  if [[ -n "${mkbootimg_py}" && -f "${kernel}" ]]; then
    out_img="${out_dir}/boot-generic-${kernel_format//./-}.img"
    python3 "${mkbootimg_py}" \
      --header_version 4 \
      --kernel "${kernel}" \
      --os_version 13.0.0 \
      --os_patch_level 2026-01 \
      --output "${out_img}"
    log "generated_generic_boot=$(basename "${out_img}")"
  else
    log "generated_generic_boot=skipped"
    log "mkbootimg_py=${mkbootimg_py:-<missing>}"
    log "kernel=${kernel:-<unsupported>}"
  fi
fi

log "note=Fastboot boot images here are generic/dist boot artifacts. The safest device-specific boot.img is still produced by repacking the stock boot_a/boot_b image with the selected kernel."
