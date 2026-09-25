#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

if (( EUID != 0 )); then
	printf 'Run this script through sudo.\n' >&2
	exit 1
fi

script_path=$(readlink -f -- "${BASH_SOURCE[0]}")
repo_root=$(cd -- "$(dirname -- "$script_path")/.." && pwd)

board=$(< /sys/class/dmi/id/board_name)
vendor=$(< /sys/class/dmi/id/board_vendor)
kernel=$(uname -r)
arch=$(uname -m)
module=asus-ec-sensors-x870e-darkhero
version=0.1
source_dir=$repo_root/dkms
dkms_dir=/usr/src/${module}-${version}
modules_load=/etc/modules-load.d/asus-ec-sensors.conf
expected_source_sha=87f5d750b46280f058f28b489cd84ee6fae7d0acf99358565afe5716c079d2d1
original_archive_dir=/var/lib/dkms/${module}/original_module/${kernel}/${arch}
module_was_switched=0

rollback_on_error() {
	status=$?
	(( status == 0 )) && return
	trap - EXIT
	printf 'Install failed (status %s); removing the local DKMS override.\n' "$status" >&2
	rm -f "$modules_load"
	dkms remove -m "$module" -v "$version" --all >/dev/null 2>&1 || true
	rm -rf "$dkms_dir"
	depmod -a "$kernel" || true
	if (( module_was_switched )); then
		modprobe asus_ec_sensors || true
	fi
	exit "$status"
}
[[ "$vendor" == 'ASUSTeK COMPUTER INC.' && "$board" == 'ROG CROSSHAIR X870E DARK HERO' ]] || {
	printf 'Refusing: unexpected DMI vendor/board: %s / %s\n' "$vendor" "$board" >&2
	exit 1
}
[[ -r "/lib/modules/${kernel}/build/Makefile" ]] || {
	printf 'Refusing: headers/build tree missing for %s\n' "$kernel" >&2
	exit 1
}
[[ -r "${source_dir}/asus-ec-sensors.c" ]] || {
	printf 'Refusing: patched source is missing.\n' >&2
	exit 1
}
actual_source_sha=$(sha256sum "${source_dir}/asus-ec-sensors.c" | awk '{print $1}')
[[ "$actual_source_sha" == "$expected_source_sha" ]] || {
	printf 'Refusing: patched source checksum differs (%s).\n' "$actual_source_sha" >&2
	exit 1
}
packaged_module=$(modinfo -k "$kernel" -n asus_ec_sensors)
[[ -r "$packaged_module" && "$packaged_module" != */updates/dkms/* ]] || {
	printf 'Refusing: a packaged module is not selected for %s.\n' "$kernel" >&2
	exit 1
}
actual_packaged_sha=$(sha256sum "$packaged_module" | awk '{print $1}')
[[ ! -e "$dkms_dir" ]] || {
	printf 'Refusing: DKMS source already exists at %s\n' "$dkms_dir" >&2
	exit 1
}
[[ ! -e "$modules_load" ]] || {
	printf 'Refusing: %s already exists; review it before installing.\n' "$modules_load" >&2
	exit 1
}

sensor_input=
sensor_hwmon=
for hwmon in /sys/class/hwmon/hwmon*; do
	[[ -r "$hwmon/name" ]] || continue
	[[ $(< "$hwmon/name") == asusec ]] || continue
	for label in "$hwmon"/temp*_label; do
		[[ -r "$label" ]] || continue
		[[ $(< "$label") == T_Sensor ]] || continue
		sensor_hwmon=$hwmon
		sensor_input=${label%_label}_input
		break 2
	done
done
[[ -r "$sensor_input" ]] || {
	printf 'Refusing: live T_Sensor read from the reviewed test module is missing.\n' >&2
	exit 1
}

printf 'Installing DKMS build for %s on %s at %s\n' "$board" "$kernel" "$(date --iso-8601=seconds)"
printf 'Pre-install T_Sensor: %s mC at %s (%s)\n' "$(< "$sensor_input")" "$sensor_input" "$sensor_hwmon"
printf 'Packaged module: %s\n' "$packaged_module"
printf 'Packaged module checksum: %s\n' "$actual_packaged_sha"

trap rollback_on_error EXIT
install -d -m 0755 "$dkms_dir"
install -m 0644 "${source_dir}/asus-ec-sensors.c" "${dkms_dir}/asus-ec-sensors.c"
cat >"${dkms_dir}/Makefile" <<'EOF'
obj-m += asus-ec-sensors.o
EOF
cat >"${dkms_dir}/dkms.conf" <<'EOF'
PACKAGE_NAME="asus-ec-sensors-x870e-darkhero"
PACKAGE_VERSION="0.1"
BUILT_MODULE_NAME[0]="asus-ec-sensors"
DEST_MODULE_LOCATION[0]="/updates/dkms"
MAKE[0]="make -C /lib/modules/${kernelver}/build M=${dkms_tree}/${PACKAGE_NAME}/${PACKAGE_VERSION}/build modules"
CLEAN="make -C /lib/modules/${kernelver}/build M=${dkms_tree}/${PACKAGE_NAME}/${PACKAGE_VERSION}/build clean"
AUTOINSTALL="yes"
EOF

dkms add -m "$module" -v "$version"
dkms build -m "$module" -v "$version" -k "$kernel"
dkms install -m "$module" -v "$version" -k "$kernel"

printf 'asus_ec_sensors\n' > "$modules_load"

rmmod asus_ec_sensors
module_was_switched=1

depmod -a "$kernel"
modprobe asus_ec_sensors

loaded_path=$(modinfo -n asus_ec_sensors)
[[ "$loaded_path" == */updates/dkms/* ]] || {
	printf 'Unexpected selected module path: %s\n' "$loaded_path" >&2
	exit 1
}
original_archive=$original_archive_dir/$(basename -- "$packaged_module")
[[ -r "$original_archive" ]] || {
	printf 'DKMS original-module archive is missing.\n' >&2
	exit 1
}
actual_archive_sha=$(sha256sum "$original_archive" | awk '{print $1}')
[[ "$actual_archive_sha" == "$actual_packaged_sha" ]] || {
	printf 'DKMS original-module archive checksum differs (%s).\n' "$actual_archive_sha" >&2
	exit 1
}
label_path=
input_path=
hwmon_path=
for hwmon in /sys/class/hwmon/hwmon*; do
	[[ -r "$hwmon/name" ]] || continue
	[[ $(< "$hwmon/name") == asusec ]] || continue
	for label in "$hwmon"/temp*_label; do
		[[ -r "$label" ]] || continue
		[[ $(< "$label") == T_Sensor ]] || continue
		hwmon_path=$hwmon
		label_path=$label
		input_path=${label%_label}_input
		break 2
	done
done
[[ -r "$input_path" ]] || {
	printf 'DKMS module loaded but T_Sensor is not readable after reload.\n' >&2
	exit 1
}

printf 'DKMS status:\n'
dkms status -m "$module" -v "$version"
printf 'Selected module: %s\n' "$loaded_path"
printf 'DKMS module SHA256: %s\n' "$(sha256sum "$loaded_path" | awk '{print $1}')"
printf 'hwmon name/path: %s / %s\n' "$(< "$hwmon_path/name")" "$hwmon_path"
printf 'T_Sensor label: %s (%s)\n' "$label_path" "$(< "$label_path")"
printf 'T_Sensor input: %s (%s mC)\n' "$input_path" "$(< "$input_path")"
printf 'Boot load config: %s (%s)\n' "$modules_load" "$(< "$modules_load")"
printf 'Original packaged module archived by DKMS: %s\n' "$(basename -- "$original_archive")"
printf 'Original module archive SHA256: %s\n' "$actual_archive_sha"
printf '\nCurrent sensors entry:\n'
sensors asusec-isa-000a
trap - EXIT
