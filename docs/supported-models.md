# Supported models

| Model identifier | Mac | Chip | Fans | Reading | Fan control |
| --- | --- | --- | --- | --- | --- |
| MacBookPro18,3 | MacBook Pro (14-inch, 2021) | M1 Pro | 2 | ✅ Verified | ✅ Verified |

On MacBookPro18,3, fan control was confirmed in the SMC: Manual, Full Speed and Custom profiles set `F<n>Md = 1` and the target speed, the fans followed, and quitting the app returned them to automatic.

Other Apple Silicon Macs show their fans and the sensors that keep their meaning across chips: battery, Wi-Fi, trackpad, airflow, charger, and the SSD, battery gauge and power manager from IOHID. Their CPU, GPU and memory sensors appear once someone adds their chip to `SensorCatalog`. Fan control should use the same keys on other Apple Silicon Macs, but only MacBookPro18,3 has been tested, and some newer chips may need an extra key (`Ftst`). Reports are welcome.

## Reporting your Mac

1. Find your model identifier: hold Option, open the Apple menu and choose System Information. The identifier is under Hardware Overview.
2. Run:

   ```sh
   Scripts/dump-sensors.sh > my-mac.txt
   ```

3. Open an issue titled "Model support: <model identifier>" and attach `my-mac.txt`.

The dump only contains hardware readings: the model identifier, the macOS version, fan speeds and temperature keys. It contains no personal data.
