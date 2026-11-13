# msi-fancontrol

Load-aware fan control for MSI laptops on Linux, built on the
[msi-ec](https://github.com/BeardOverflow/msi-ec) kernel driver.

Many MSI gaming laptops ship with a fan profile tuned for low noise, so they run hot under sustained load
(simulators, games, compiling). Maxing the fans with **Cooler Boost** fixes the temperatures but
is loud. msi-fancontrol turns boost on only when the machine is actually hot, and switches it back off
once things have cooled down.

It also provides a `fanprofile` command to switch between a few fixed profiles.

## Tested on

So far this has been tested on **one** machine:

| | |
|---|---|
| Model | MSI Cyborg 15 A13VE (board MS-15K1) |
| CPU / GPU | Intel Core i7-13620H / NVIDIA GeForce RTX 4050 Laptop |
| BIOS | E15K1IMS.10E (2023-09-04) |
| EC firmware | `15K1IMS1.110` (from `/sys/devices/platform/msi-ec/fw_version`) |
| OS | Ubuntu 26.04.1 LTS, GNOME 50, kernel 7.0.0-43-generic |
| Driver | msi-ec 0.18 (DKMS, upstream); the kernel's built-in msi-ec did **not** support this firmware |

### Probably compatible (untested)

- **Same EC firmware family (`15K1IMS1.1xx`):** msi-ec lists this family for the
  Cyborg 15 A12VF / A13VF(K), and it uses the same register layout. These models should work
  as-is.
- **Other msi-ec-supported MSI laptops:** these should work if they expose `cooler_boost` and the
  shift modes `comfort`, `eco` and `turbo`. Check with:

  ```bash
  cat /sys/devices/platform/msi-ec/fw_version
  cat /sys/devices/platform/msi-ec/available_shift_modes
  ```

  If your model uses other names, for example `sport` instead of `turbo`, edit the `apply` calls in
  `msi-fancontrol.sh`.

If you try this on another model, please open an issue or PR with your model and `fw_version` so it
can be added to the list.

## Profiles

| Profile | shift_mode | cooler_boost | Use it for |
|---|---|---|---|
| `auto` (default) | `turbo` when hot, `comfort` when cool | on when hot | everyday use |
| `quiet` | `eco` | off | meetings, battery; slower CPU |
| `balanced` | `comfort` | off | light work, no boost ever |
| `max` | `turbo` | on | long heavy sessions |

`fan_mode` is kept at `auto` in all profiles. That stops the firmware's `silent` preset from
coming back.

### How `auto` decides

- **Boost on:** CPU ≥ 85 °C **or** GPU ≥ 75 °C for 10 s.
- **Boost off:** CPU < 70 °C **and** GPU < 62 °C for 60 s.

The thresholds are far apart on purpose, so the fans don't keep switching between loud and quiet.
Temperatures come from the embedded controller (`/sys/devices/platform/msi-ec/{cpu,gpu}/realtime_temperature`),
not from `nvidia-smi`, so polling never wakes a sleeping dGPU.

The service writes its chosen state every 2 s. Settings that the firmware resets after
suspend/resume are therefore fixed automatically.

## Install

### 1. Install the msi-ec driver (DKMS)

Some kernels include an older msi-ec that may not know your firmware. If that's the case,
`/sys/devices/platform/msi-ec` won't exist after `sudo modprobe msi_ec`. The upstream DKMS version
supports more models:

```bash
sudo apt install build-essential linux-headers-$(uname -r) dkms git
git clone https://github.com/BeardOverflow/msi-ec
cd msi-ec
sudo make dkms-install
sudo modprobe -r msi_ec; sudo modprobe msi_ec
ls /sys/devices/platform/msi-ec/     # should list cooler_boost, shift_mode, fan_mode, ...
```

If it fails to load, your firmware may not be supported yet. Check `sudo dmesg | grep msi` and the
msi-ec project's device support discussions.

### 2. Install msi-fancontrol

```bash
git clone <this repo> msi-fancontrol
sudo msi-fancontrol/install.sh
```

This installs:

- `/usr/local/bin/msi-fancontrol.sh`: the daemon
- `/usr/local/bin/fanprofile`: the CLI
- `/etc/systemd/system/msi-fancontrol.service`: enabled at boot
- `/etc/modules-load.d/msi-ec.conf`: loads the driver at boot
- `/var/lib/msi-fancontrol/profile`: the current profile, initially `auto`

To update after editing the scripts, run `install.sh` again.

## Usage

```bash
fanprofile            # status: profile, modes, temperatures, fan RPM (no sudo needed)
fanprofile auto       # switch profile (asks for sudo)
fanprofile quiet
fanprofile balanced
fanprofile max
fanprofile --help

journalctl -u msi-fancontrol -f   # watch boost on/off decisions live
```

The selected profile persists across reboots.

## Tuning

Override any of these in `/etc/default/msi-fancontrol`, then run `sudo systemctl restart msi-fancontrol`:

```bash
CPU_HOT=85      # boost when CPU >= this (°C)
GPU_HOT=75      # ...or GPU >= this
CPU_COOL=70     # un-boost only when CPU < this
GPU_COOL=62     # ...and GPU < this
HOT_SECS=10     # must be hot this long before boosting
COOL_SECS=60    # must be cool this long before un-boosting
INTERVAL=2      # polling interval (s)
```

You can test changes without touching the hardware: `DRY_RUN=1 ./msi-fancontrol.sh` prints what it would
change instead of writing.

## Uninstall

```bash
sudo ./uninstall.sh
```

This removes msi-fancontrol but leaves the msi-ec driver installed. To remove the driver as well, run
`sudo make dkms-uninstall` in the msi-ec checkout.

## Notes

- `msi-ec`'s `realtime_fan_speed` is not a reliable percentage: it reads the same with and
  without Cooler Boost on. `fanprofile` shows the real RPM from the `msi_wmi_platform` hwmon instead.
- On DKMS, `dkms status` may report "Original modules exist". That is fine: the DKMS build takes
  precedence over the in-kernel module.
- This writes to your laptop's embedded controller through msi-ec. That is generally safe on
  supported firmware, because msi-ec refuses to load on firmware it doesn't know. Still, use it at
  your own risk.

## License

MIT. See [LICENSE](LICENSE).

---

<sub>Built with the help of AI coding agents. It was reviewed and tested on real hardware (see
[Tested on](#tested-on)), but it is still a set of scripts that write to your laptop's embedded
controller, so please read them before running.</sub>
