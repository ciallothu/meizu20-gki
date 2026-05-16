#!/usr/bin/env bash
set -euo pipefail

strategy="$1"
dist_dir="$2"
repo_root="$3"
out_dir="$4"

ak_dir="${out_dir}/AnyKernel3-${strategy}"
zip_name="${out_dir}/AnyKernel3-Meizu20-${strategy}.zip"

rm -rf "${ak_dir}"
git clone --depth=1 https://github.com/osm0sis/AnyKernel3.git "${ak_dir}"
rm -rf "${ak_dir}/.git" "${ak_dir}/.github" "${ak_dir}/README.md"

cp "${repo_root}/anykernel/anykernel.sh" "${ak_dir}/anykernel.sh"
cp "${dist_dir}/Image.gz" "${ak_dir}/Image.gz"
cp "${dist_dir}/Image" "${ak_dir}/Image"

(
	cd "${ak_dir}"
	zip -r9 "${zip_name}" . -x '*.git*'
)

echo "${zip_name}"

