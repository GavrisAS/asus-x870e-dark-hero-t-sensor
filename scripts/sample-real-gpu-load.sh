#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

usage() {
	printf 'Usage: %s <idle|gpu_load|cooldown> <seconds> [output.csv]\n' "$0" >&2
	exit 2
}

(( $# >= 2 && $# <= 3 )) || usage
phase=$1
duration=$2
case "$phase" in
	idle|gpu_load|cooldown) ;;
	*) usage ;;
esac
[[ "$duration" =~ ^[1-9][0-9]*$ ]] || usage

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
output=${3:-"$repo_root/validation/real-gpu-load-$(date +%F).csv"}
mkdir -p -- "$(dirname -- "$output")"

find_hwmon() {
	local target=$1 hwmon
	for hwmon in /sys/class/hwmon/hwmon*; do
		[[ -r "$hwmon/name" ]] || continue
		if [[ $(<"$hwmon/name") == "$target" ]]; then
			printf '%s\n' "$hwmon"
			return 0
		fi
	done
	return 1
}

read_value() {
	local path=$1
	if [[ -r "$path" ]]; then
		tr -d '\n' <"$path"
	fi
}

trim() {
	local value=$1
	value=${value#"${value%%[![:space:]]*}"}
	value=${value%"${value##*[![:space:]]}"}
	printf '%s' "$value"
}

asusec=$(find_hwmon asusec) || {
	printf 'Could not find the asusec hwmon device.\n' >&2
	exit 1
}
cpu=$(find_hwmon k10temp) || {
	printf 'Could not find the k10temp hwmon device.\n' >&2
	exit 1
}
nct=$(find_hwmon nct6799 || true)

sensor_input=
for label in "$asusec"/temp*_label; do
	[[ -r "$label" ]] || continue
	if [[ $(<"$label") == T_Sensor ]]; then
		sensor_input=${label%_label}_input
		break
	fi
done
[[ -r "$sensor_input" ]] || {
	printf 'Could not find a readable T_Sensor input.\n' >&2
	exit 1
}

output_header='timestamp,phase,t_sensor_mC,cpu_tctl_mC,gpu_temp_C,gpu_util_pct,gpu_power_W,gpu_memory_used_MiB,nct_fan1_rpm,nct_fan2_rpm,nct_fan3_rpm,nct_fan4_rpm,nct_fan5_rpm,flow_tach_rpm,pump_rpm'
if [[ ! -e "$output" || ! -s "$output" ]]; then
	printf '%s\n' "$output_header" >"$output"
fi

status_interval=30
count=0
initial_t_sensor=
reaction_reported=0
while (( count < duration )); do
	timestamp=$(date -u +'%Y-%m-%dT%H:%M:%S.%3NZ')
	t_sensor=$(read_value "$sensor_input")
	cpu_tctl=$(read_value "$cpu/temp1_input")
	gpu_data=$(nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,power.draw,memory.used --format=csv,noheader,nounits)
	IFS=, read -r gpu_temp gpu_util gpu_power gpu_memory <<<"$gpu_data"
	gpu_temp=$(trim "${gpu_temp:-}")
	gpu_util=$(trim "${gpu_util:-}")
	gpu_power=$(trim "${gpu_power:-}")
	gpu_memory=$(trim "${gpu_memory:-}")
	[[ "$t_sensor" =~ ^-?[0-9]+$ && "$cpu_tctl" =~ ^-?[0-9]+$ ]] || {
		printf 'T_Sensor or CPU Tctl read failed.\n' >&2
		exit 1
	}

	fans=()
	for fan in {1..7}; do
		fans+=("$(read_value "${nct:-/missing}/fan${fan}_input")")
	done
	row="$timestamp,$phase,$t_sensor,$cpu_tctl,$gpu_temp,$gpu_util,$gpu_power,$gpu_memory"
	for rpm in "${fans[@]}"; do
		row+=",$rpm"
	done
	printf '%s\n' "$row" >>"$output"

	(( count += 1 ))
	print_status=0
	if (( count == 1 )); then
		initial_t_sensor=$t_sensor
		print_status=1
	elif [[ "$phase" == gpu_load && $reaction_reported -eq 0 ]] && \
		(( t_sensor >= initial_t_sensor + 1000 )); then
		reaction_reported=1
		print_status=1
	elif (( count % status_interval == 0 || count == duration )); then
		print_status=1
	fi
	if (( print_status )); then
		printf 'phase=%s elapsed=%ss GPU util=%s%% power=%sW temp=%sC VRAM=%sMiB T_Sensor=%s mC pump=%s RPM flow_tach=%s RPM\n' \
			"$phase" "$count" "$gpu_util" "$gpu_power" "$gpu_temp" "$gpu_memory" "$t_sensor" "${fans[6]}" "${fans[5]}"
	fi
	sleep 1
done

printf 'Wrote %s samples to %s\n' "$count" "$output"
