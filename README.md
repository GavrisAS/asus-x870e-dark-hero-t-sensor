# ASUS ROG CROSSHAIR X870E DARK HERO T_Sensor

This repository tracks Linux `hwmon` support for the external `T_SENSOR`
header on the ASUS ROG CROSSHAIR X870E DARK HERO.

## Status

As of mainline commit [`165768bb7026`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=165768bb70265b5c38cf0b73fafd75be235f8b14), dated 2026-09-24, `asus-ec-sensors` had a profile for the ROG CROSSHAIR X870E HERO but no exact match for the DARK HERO. The minimal upstream patch is in [`patches/`](patches/).

## Sensor mapping

The profile exposes only `T_Sensor`. It reuses the driver's AMD 800-series
mapping: EC bank `0`, index `0x36`, one signed byte in degrees Celsius. The
driver exports the reading through hwmon in millidegrees Celsius. The profile
uses the existing ACPI mutex `\_SB_.PCI0.SBRG.SIO1.MUT0` and an exact DMI board
name match. It adds no EC access code, does not write to the EC, and does not
rename an AUXTIN channel.

The register mapping is already defined in the
[upstream AMD 800-series sensor table](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/hwmon/asus-ec-sensors.c?id=165768bb70265b5c38cf0b73fafd75be235f8b14#n309).
A [merged LibreHardwareMonitor profile](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/blob/931616f513334e50293ce88838c2707cdf2b2bf5/LibreHardwareMonitorLib/Hardware/Motherboard/Lpc/EC/EmbeddedController.cs#L27-L29)
independently matches this board to the AMD 800-series family and exposes only
`T_Sensor`.

## Hardware validation

Validation was performed on DMI board vendor `ASUSTeK COMPUTER INC.`, board
`ROG CROSSHAIR X870E DARK HERO`, revision `Rev 1.xx`, with the coolant probe
connected to `T_SENSOR`. The installed test module exposed only the expected
`T_Sensor` hwmon attribute.

An idle baseline was sampled for three minutes, followed by a sustained CUDA
matrix-multiplication load. The NVIDIA GPU reached 100% utilization and
603.59 W for about one minute. `T_Sensor` was 33 °C for most idle samples
(32–33 °C range), rose under load, peaked at 35 °C shortly after the load
stopped, and returned to 32 °C during the seven-minute cooldown. The GPU core
temperature fell much faster than the sensor reading. The EC reading has
1 °C resolution; the raw samples preserve its quantization. See
[`validation/real-gpu-load-summary.md`](validation/real-gpu-load-summary.md)
and [`validation/real-gpu-load-2026-09-25.csv`](validation/real-gpu-load-2026-09-25.csv).

## Reading the sensor

The driver registers the hwmon device as `asusec` and labels the temperature
channel `T_Sensor`. The `hwmonN` number can change between boots, so find the
device and label instead of hard-coding a number:

```sh
for hwmon in /sys/class/hwmon/hwmon*; do
	[ -r "$hwmon/name" ] || continue
	[ "$(cat "$hwmon/name")" = asusec ] || continue
	for label in "$hwmon"/temp*_label; do
		[ -r "$label" ] || continue
		[ "$(cat "$label")" = T_Sensor ] || continue
		cat "${label%_label}_input"
	done
done
```

The value is millidegrees Celsius. `sensors` can also display it when the
driver is loaded.

## Temporary DKMS workaround

`dkms/asus-ec-sensors.c` is the tested driver source for kernel
`7.2.5-3-omarchy`; the upstream patch is separate and does not include DKMS
files. With matching kernel headers installed, install the workaround with:

```sh
sudo ./scripts/install-asus-ec-sensors-dkms.sh
```

The installer checks the board DMI identity and the source checksum, asks DKMS
to preserve the packaged module, and enables module loading at boot. The
workaround is specific to the included driver source; other kernel versions may
need an updated source file.

Once using a kernel with native support, remove the workaround and restore the
packaged module:

```sh
sudo rmmod asus_ec_sensors
sudo dkms remove -m asus-ec-sensors-x870e-darkhero -v 0.1 --all
sudo rm -rf /usr/src/asus-ec-sensors-x870e-darkhero-0.1
sudo rm -f /etc/modules-load.d/asus-ec-sensors.conf
sudo depmod -a
sudo modprobe asus_ec_sensors
```

The Linux hwmon contribution uses inline email. The email-ready patch is in
`patches/` and is awaiting submission.

## License

The driver patch and DKMS source are distributed under GPL-2.0-or-later, as
marked in the source. The sampling script is also GPL-2.0-or-later.
