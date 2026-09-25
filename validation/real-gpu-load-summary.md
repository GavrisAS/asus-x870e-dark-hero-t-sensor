# Real GPU-load validation

- **Board:** ASUSTeK COMPUTER INC. / ROG CROSSHAIR X870E DARK HERO, Rev 1.xx
- **Kernel:** 7.2.5-3-omarchy
- **Test date:** 2026-09-25
- **Trace:** [`real-gpu-load-2026-09-25.csv`](real-gpu-load-2026-09-25.csv), UTC timestamps

## Results

- **Idle baseline:** 180 samples over 3 min 9 s. `T_Sensor` median/mode was
  33 °C, ranging from 32–33 °C. CPU Tctl ranged from 47.9–58.6 °C.
- **GPU workload:** 59 samples over about 60 s. 58 consecutive samples were
  at or above 95% GPU utilization and 500 W. Peak utilization was 100%, peak
  power 603.59 W, GPU temperature 53 °C, and VRAM use 2,419 MiB. CPU Tctl
  ranged from 60.6–70.1 °C.
- **Response:** `T_Sensor` moved from the final idle sample of 32 °C to 33 °C
  after 44.6 s of recorded load; 33 °C was still within the idle range. The
  first reading above the 33 °C idle median was 34 °C in the first cooldown
  sample, recorded 18 s after the final load sample. It peaked at 35 °C about
  15 s later, a 2 °C rise over the idle median.
- **Cooldown:** 414 samples over 7 min 14 s. Per-minute `T_Sensor` medians
  were 34, 34, 33, 33, 33, 32, and 32 °C. It first returned to 32 °C about
  5 min 49 s after cooldown sampling began. GPU temperature fell from 53 °C
  under load to 35 °C in the first cooldown sample and 33 °C by the end.
- **Fan channels:** NCT fan6 (flow tach) ranged from 701–742 RPM; fan7 (pump)
  ranged from 4,411–4,500 RPM. NCT fan1–fan5 are included in the CSV.

## Assessment

The sensor rose during sustained GPU heat input, continued rising briefly
after the load stopped, and declined over several minutes while the GPU core
cooled much faster. This response is consistent with coolant temperature from
the connected `T_SENSOR` probe. The one-degree reading flickered around
thresholds during idle and cooldown, matching the EC reading's 1 °C resolution;
the underlying rise and return remained visible. All sampled channels were
readable. The only warning-priority kernel messages in the test window were
unrelated firewall block notices; no sensor-driver, ACPI, hwmon, or GPU errors
or warnings appeared.

The data validates the board profile and register selection for this system;
it is not a separate calibration measurement of absolute temperature.
