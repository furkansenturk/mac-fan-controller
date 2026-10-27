# SMC keys

The System Management Controller (SMC) exposes hardware state as four-character keys. Each key has a data type and a size. Fan Controller talks to the SMC through the `AppleSMC` IOKit user client (`SMCKit/SMC.swift`).

Apple doesn't document the keys; there is no list on developer.apple.com. Names on this page come from two community sources, and every key was confirmed to exist on real hardware:

- [Stats](https://github.com/exelban/stats), `Modules/Sensors/values.swift` (MIT licensed)
- [Asahi Linux SMC notes](https://asahilinux.org/docs/hw/soc/smc/), which point out that names are mostly guessed from the four-character key

Each section says which Mac it was confirmed on.

## Data types

| Type | Size | Encoding | Seen on |
| --- | --- | --- | --- |
| `flt ` | 4 | IEEE 754 float, **little-endian** | Apple Silicon temperatures and fan speeds |
| `fpe2` | 2 | Unsigned fixed point 14.2, big-endian | Intel fan speeds |
| `sp78` | 2 | Signed fixed point 8.8, big-endian | Intel temperatures |
| `fp88` | 2 | Unsigned fixed point 8.8, big-endian | |
| `ui8 ` `ui16` `ui32` | 1/2/4 | Unsigned integer, big-endian | Counts, modes |
| `si8 ` `si16` | 1/2 | Signed integer, big-endian | |
| `flag` | 1 | 0 or 1 | |

Decoding lives in `SMCValue.doubleValue`, and encoding for writes in `SMCDataType.encode(_:)`.

## Fans

`<n>` is the fan index, starting at 0.

| Key | Type | Meaning | Access |
| --- | --- | --- | --- |
| `FNum` | `ui8` | Number of fans | read |
| `F<n>Ac` | `flt` | Current speed (RPM) | read |
| `F<n>Mn` | `flt` | Minimum speed (RPM) | read |
| `F<n>Mx` | `flt` | Maximum speed (RPM) | read |
| `F<n>Tg` | `flt` | Target speed (RPM), honoured in manual mode | read, write (root) |
| `F<n>Md` | `ui8` | Mode: `0` automatic, `1` manual | read, write (root) |

Notes:

- On Apple Silicon the fans stop completely under light load, so `F<n>Ac` reads `0`.
- The SMC doesn't store fan names. On two-fan MacBook Pros, fan 0 is the left fan.
- The M1 Pro has no `Ftst` key. Some newer chips reportedly need `Ftst = 1` before they accept manual mode. This will be checked when those Macs are added.

## Temperatures

Temperature keys start with `T`. One key can mean different things on different chips, so `SensorCatalog` maps keys **per chip**. The chip is identified by `machdep.cpu.brand_string`.

### Apple M1 Pro / M1 Max

Confirmed on MacBookPro18,3 (M1 Pro, 14-inch).

| Key | Sensor |
| --- | --- |
| `Tp09`, `Tp0T` | Efficiency Core 1–2 |
| `Tp01`, `Tp05`, `Tp0D`, `Tp0H`, `Tp0L`, `Tp0P`, `Tp0X`, `Tp0b` | Performance Core 1–8 |
| `Tg05`, `Tg0D` | GPU Cluster 1–2 (M1 Max also has `Tg0L`, `Tg0T`) |
| `Tm02`, `Tm06` | Memory 1–2 (Stats lists `Tm08`, `Tm09` as Memory 3–4; not present on MacBookPro18,3) |

### All Apple Silicon Macs

| Key | Sensor |
| --- | --- |
| `TaLP`, `TaRF` | Airflow Left / Right (Stats) |
| `TCHP` | Charger (Asahi: rises slightly while charging) |
| `TB0T` | Battery (Asahi: the hottest battery reading) |
| `TB1T`, `TB2T` | Battery 1–2 (Stats) |
| `TW0P` | Wi-Fi module |
| `Ts0P` | Trackpad |

Not shown: `TH0x`, which Stats calls NAND, because the HID SSD sensor below measures the same thing; and `TPD*`, `TRD*`, `TD*`, `TV*`, `TS*`, which no source names.

### IOHID sensors

Some temperatures on Apple Silicon aren't SMC keys. They are IOHID services (usage page `0xFF00`, usage `5`) with a product name, read through `IOHIDEventSystemClient` (`FanKit/HIDTemperatures.swift`). Products with several services are averaged.

| Product name | Sensor |
| --- | --- |
| `NAND CH0 temp` (`NAND CH1 temp`, … on Macs with more channels) | The internal SSD, shown under Disk Drives with its model name from the I/O Registry (`IOEmbeddedNVMeBlockDevice` › `Device Characteristics` › `Product Name`, e.g. "APPLE SSD AP0512R") |
| `gas gauge battery` | Battery Gas Gauge |
| `PMU tdie0` … `PMU tdie10` | Power Manager Die Average |

Confirmed on MacBookPro18,3, where the readings are in line with what Macs Fan Control shows for the same sensors (Power Manager Die Average ≈ 43 °C, Battery Gas Gauge ≈ 34 °C at idle). `Scripts/dump-sensors.sh` lists every HID temperature service.

Not shown: `PMU tdev1…8`, `PMU TP*` and `PMU tcal`, whose meaning isn't known.

Keys a Mac doesn't expose are skipped when the app starts. Sensors that read `0` are hidden, because that means they are powered down.

## Warm and critical limits

The Temperatures page and the menu bar panel shift a reading's color toward red between a sensor's **warm** and **critical** limits, and show it in full red with a warning symbol at the critical limit (`FanKit/ThermalLimits.swift`). Apple doesn't publish per-sensor limits; these are reasoned defaults:

| Sensor | Warm | Critical | Reasoning |
| --- | --- | --- | --- |
| CPU cores, GPU clusters | 70 °C | 95 °C | Apple Silicon throttles at about 100–105 °C |
| Memory | 65 °C | 90 °C | |
| SSD | 50 °C | 70 °C | NVMe drives typically throttle at 70–80 °C |
| Battery, battery cells, gas gauge | 35 °C | 45 °C | Apple advises against batteries running above 35 °C |
| Charger | 50 °C | 70 °C | |
| Power manager | 60 °C | 85 °C | |
| Wi-Fi | 55 °C | 75 °C | |
| Airflow | 50 °C | 65 °C | Exhaust air |
| Trackpad | 38 °C | 45 °C | A surface under the hands; uncomfortable from about 43 °C |

If your Mac shows a different normal range, open an issue with a `dump-sensors.sh` output taken under load.

## Adding a chip

1. Run `Scripts/dump-sensors.sh` on the Mac.
2. Put the Mac under load (for example `yes > /dev/null` on a few cores) and run it again. Keys whose values rise with load are core or GPU sensors.
3. Add a `case` for the chip to `SensorCatalog.definitions(forChip:)` and a test to `SensorCatalogTests`.
4. Add the Mac to [supported-models.md](supported-models.md).
