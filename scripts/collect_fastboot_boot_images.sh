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

generated_stock_template=0

case "${kernel_format}" in
  Image) kernel="${dist_dir}/Image" ;;
  Image.gz) kernel="${dist_dir}/Image.gz" ;;
  Image.lz4) kernel="${dist_dir}/Image.lz4" ;;
  *) kernel="" ;;
esac

if [[ -n "${stock_boot}" && -f "${stock_boot}" && -f "${kernel}" ]]; then
  out_img="${out_dir}/boot-stock-template-${kernel_format//./-}.img"
  python3 "${GITHUB_WORKSPACE}/scripts/repack_bootimg_kernel.py" \
    "${stock_boot}" \
    "${kernel}" \
    "${out_img}" \
    --no-preserve-size | tee -a "${summary}"

  avbtool="$(mktemp "${TMPDIR:-/tmp}/avbtool.XXXXXX.py")"
  curl -fsSL "https://android.googlesource.com/platform/external/avb/+/refs/heads/master/avbtool.py?format=TEXT" \
    | base64 -d > "${avbtool}"
  chmod +x "${avbtool}"

  partition_size="$(python3 - <<'PY' "${stock_boot}"
from pathlib import Path
import sys
print(Path(sys.argv[1]).stat().st_size)
PY
)"
  avb_info="$(python3 "${avbtool}" info_image --image "${stock_boot}")"
  rollback_index="$(printf '%s\n' "${avb_info}" | awk -F: '/Rollback Index:/ {gsub(/[[:space:]]/, "", $2); print $2; exit}')"
  rollback_location="$(printf '%s\n' "${avb_info}" | awk -F: '/Rollback Index Location:/ {gsub(/[[:space:]]/, "", $2); print $2; exit}')"
  salt="$(printf '%s\n' "${avb_info}" | awk -F: '/Salt:/ {gsub(/[[:space:]]/, "", $2); print $2; exit}')"
  rollback_index="${rollback_index:-0}"
  rollback_location="${rollback_location:-0}"

  avb_args=(
    add_hash_footer
    --image "${out_img}"
    --partition_size "${partition_size}"
    --partition_name boot
    --algorithm NONE
    --rollback_index "${rollback_index}"
    --rollback_index_location "${rollback_location}"
    --set_verification_disabled_flag
  )
  if [[ -n "${salt}" ]]; then
    avb_args+=(--salt "${salt}")
  fi
  while IFS= read -r prop; do
    avb_args+=(--prop "${prop}")
  done < <(
    printf '%s\n' "${avb_info}" \
      | sed -n "s/^    Prop: \\([^ ]*\\) -> '\\(.*\\)'$/\\1:\\2/p"
  )

  python3 "${avbtool}" "${avb_args[@]}" | tee -a "${summary}"
  python3 "${avbtool}" info_image --image "${out_img}" | sed -n '1,80p' | tee -a "${summary}"
  rm -f "${avbtool}"
  log "generated_stock_template_boot=$(basename "${out_img}")"
  generated_stock_template=1
fi

copied=0
if [[ "${generated_stock_template}" -eq 0 ]]; then
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
  log "copied_dist_boot=skipped_stock_template_available"
fi

if [[ "${copied}" -eq 0 && "${generated_stock_template}" -eq 0 ]]; then
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

log "note=Fastboot boot images are generated from the stock Meizu boot template when available and include a rebuilt AVB hash footer. Generic boot images are only fallback artifacts."
