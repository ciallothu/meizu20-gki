#!/usr/bin/env bash
set -euo pipefail

strategy="$1"
dist_dir="$2"
repo_root="$3"
out_dir="$4"
kernel_format="${KERNEL_FORMAT:-Image.gz}"

ak_dir="${out_dir}/AnyKernel3-${strategy}"
zip_name="${out_dir}/AnyKernel3-Meizu20-${strategy}.zip"

rm -rf "${ak_dir}"
git clone --depth=1 https://github.com/osm0sis/AnyKernel3.git "${ak_dir}"
rm -rf "${ak_dir}/.git" "${ak_dir}/.github" "${ak_dir}/README.md"

cp "${repo_root}/anykernel/anykernel.sh" "${ak_dir}/anykernel.sh"

case "${kernel_format}" in
	Image)
		kernel_src="${dist_dir}/Image"
		kernel_dst="Image"
		;;
	Image.gz)
		kernel_src="${dist_dir}/Image.gz"
		kernel_dst="Image.gz"
		;;
	Image.lz4)
		kernel_src="${dist_dir}/Image.lz4"
		kernel_dst="Image.lz4"
		;;
	*)
		echo "Unsupported KERNEL_FORMAT=${kernel_format}. Use Image, Image.gz, or Image.lz4." >&2
		exit 1
		;;
esac

if [[ ! -f "${kernel_src}" ]]; then
	echo "Kernel artifact not found: ${kernel_src}" >&2
	exit 1
fi

cp "${kernel_src}" "${ak_dir}/${kernel_dst}"

(
	cd "${ak_dir}"
	zip -r9 "${zip_name}" . -x '*.git*'
)

echo "${zip_name}"
