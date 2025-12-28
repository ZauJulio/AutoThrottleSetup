# AutoThrottleSetup

![Linux](https://img.shields.io/badge/Linux-FCC624?style=flat&logo=linux&logoColor=black)
![Shell Script](https://img.shields.io/badge/Shell_Script-121011?style=flat&logo=gnu-bash&logoColor=white)
![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?logo=arch-linux&logoColor=white)
![Debian](https://img.shields.io/badge/Debian-A81D33?logo=debian&logoColor=white)
![Fedora](https://img.shields.io/badge/Fedora-51A2DA?logo=fedora&logoColor=white)

---

A lightweight, user-space orchestration tool for thermal and power management on Linux. It serves as a "ThrottleStop" alternative for Linux users, specifically tuned for Intel CPUs with Speed Shift (HWP) support or newer AMD processors.

## 📖 Technical Overview

This tool interfaces directly with the Linux kernel's `sysfs` to manage hardware power states. It interacts with the `powercap` (RAPL) subsystem to enforce physical power limits (PL1/PL2) and the `cpufreq` subsystem. It sets the scaling governor and fine-tunes the Energy Performance Preference (EPP) to achieve an optimal balance between thermals and performance.

## ⚡ Default Configuration (i5-12450H Sweet Spot)

| Setting              | Value         | Description                                             |
| :------------------- | :------------ | :------------------------------------------------------ |
| **PL1 (Long Term)**  | **30W**       | Sustained power limit. Keeps temps ~75°C.               |
| **PL2 (Short Term)** | **45W**       | Burst power limit for quick tasks/app launching.        |
| **Max Frequency**    | **4.0 GHz**   | Caps the top 400MHz to maximize efficiency.             |
| **EPP**              | **84**        | "Balance Performance". Quick response, aggressive idle. |
| **Governor**         | **Powersave** | Required for HWP/Speed Shift to function correctly.     |

### Tip 👽

Before running this tool, study your CPU's specifications to determine safe PL1/PL2 values. Use `lscpu` or `cpupower` to check supported frequencies and governors. Study your system's thermal limits to avoid overheating. Good starting points are often 60-70% of your CPU's TDP for PL1 and 90-100% for PL2.

The most cpu's power consumption occurs at high frequencies under load. By capping the max frequency slightly below the peak, you can often achieve significant thermal and power savings with minimal performance impact.

## 🚀 Installation

### Option A: Arch Linux (AUR)

If you have published the package to AUR:

```bash
yay -S auto-throttle

```

Or manually via this repo:

```bash
git clone https://github.com/ZauJulio/AutoThrottleSetup.git
cd AutoThrottleSetup
makepkg -si

```

### Option B: Debian / Ubuntu / Mint

1. Download the latest `.deb` file from the [link suspeito removido].
2. Install using `dpkg`:

```bash
sudo dpkg -i auto-throttle_1.0.0_amd64.deb
# If missing dependencies occur:
sudo apt-get install -f

```

### Option C: Fedora / RHEL / CentOS

1. Download the latest `.rpm` file from the [link suspeito removido].
2. Install using `rpm`:

```bash
sudo rpm -ivh auto-throttle-1.0.0.x86_64.rpm

```

### Option D: Manual Install (Universal)

If you prefer not to use packages:

1. Copy the script to bin:

```bash
sudo cp auto-throttle.sh /usr/local/bin/auto-throttle
sudo chmod +x /usr/local/bin/auto-throttle

```

2. Copy the config file:

```bash
sudo cp auto-throttle.conf /etc/auto-throttle.conf

```

3. Setup Systemd service:

```bash
sudo cp auto-throttle.service /etc/systemd/system/
sudo systemctl enable --now auto-throttle.service

```

## ⚙️ Configuration

You do not need to edit the script code. All settings are managed in `/etc/auto-throttle.conf`.

1. **Open the configuration file:**

```bash
sudo nano /etc/auto-throttle.conf

```

2. **Adjust the variables:**

The file is commented with instructions. Key variables:
* `PL1_WATTS` / `PL2_WATTS`: Your CPU Thermal Design Power limits.
* *Example for Dell Ultrabooks:* Set PL1 to 15, PL2 to 25.


* `MAX_FREQ_GHZ`: Hard cap on CPU frequency (e.g., 4.0). Set to `0` to disable.
* `EPP_INTEL`: Energy Preference.
* `84` = Balanced Gaming (Recommended)
* `170` = Battery Saving


* `TARGET_GOVERNOR`: Keep as `powersave` for modern Intel CPUs (it enables Speed Shift). Use `performance` only if you want max clocks at all times.


1. **Apply Changes:**
Restart the service to apply new settings immediately:

```bash
# Enable/Start service (if not already running)
sudo systemctl enable --now auto-throttle.service

# Restart to apply changes on the fly
sudo systemctl restart auto-throttle
```

## 📊 Monitoring

To verify if settings are applied correctly, use the built-in Linux tools or this watch command:

```bash
watch -n 1 "echo '=== CPU Power ==='; sensors | grep -A 1 'Package id 0'; echo ''; echo '=== Clocks (MHz) ==='; grep 'MHz' /proc/cpuinfo | awk '{print \$4}' | head -n 8"

```

*Note: You may need to install `lm_sensors` (`sudo pacman -S lm_sensors` or `sudo apt install lm-sensors`).*

## ⚠️ Disclaimer

This tool manipulates hardware power registers. While the provided values are safe "limiting" techniques (which generally extend lifespan), using values outside of your hardware's specifications can lead to instability. Use at your own risk.

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](https://www.google.com/search?q=LICENSE) file for details.
