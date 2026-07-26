# 9M2PJU - POCO F7 Debloat Script

A safe, reversible, no-root debloat toolkit for the **POCO F7 (codename `onyx_global`)** running HyperOS 2 / Android 16.

> Maintained by [9M2PJU](https://github.com/9M2PJU) · Tested on ROM `OS3.0.302.0.WOLMIXM` (HyperOS V816, Android 16, security patch 2026-05-01)

---

## One-liner (the fast way)

Connect your POCO F7 via USB with USB debugging enabled, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/9M2PJU/9M2PJU-POCO-F7-Debloat-Script/main/install.sh | bash
```

This downloads `debloat.sh` + `restore.sh` into the current directory and runs `debloat.sh` interactively (prompts y/N before each batch).

### One-liner variants

```bash
# Preview only - show what would be removed, change nothing
curl -fsSL https://raw.githubusercontent.com/9M2PJU/9M2PJU-POCO-F7-Debloat-Script/main/install.sh | bash -s -- --list

# Download only, don't run yet (review the scripts first)
curl -fsSL https://raw.githubusercontent.com/9M2PJU/9M2PJU-POCO-F7-Debloat-Script/main/install.sh | bash -s -- --no-run

# Non-interactive - remove all 6 batches without prompting
curl -fsSL https://raw.githubusercontent.com/9M2PJU/9M2PJU-POCO-F7-Debloat-Script/main/install.sh | bash -s -- --yes

# Run only a specific batch (1-6)
curl -fsSL https://raw.githubusercontent.com/9M2PJU/9M2PJU-POCO-F7-Debloat-Script/main/install.sh | bash -s -- --batch 1

# Install to a specific directory
curl -fsSL https://raw.githubusercontent.com/9M2PJU/9M2PJU-POCO-F7-Debloat-Script/main/install.sh | bash -s -- --dir ~/poco-f7
```

> **Security note:** `curl | bash` runs code from the internet. If you'd rather review first, use `--no-run` or clone the repo (see [Quick start](#quick-start)) and inspect the scripts before executing.

---

## Table of contents

- [One-liner (the fast way)](#one-liner-the-fast-way)
- [What this project does](#what-this-project-does)
- [Why debloat?](#why-debloat)
- [How it works (the science)](#how-it-works-the-science)
- [Repository structure](#repository-structure)
- [Requirements](#requirements)
  - [Step 1: Install `adb` on your computer](#step-1-install-adb-on-your-computer)
  - [Step 2: Enable Developer Options on the phone](#step-2-enable-developer-options-on-the-phone)
  - [Step 3: Enable USB debugging](#step-3-enable-usb-debugging)
  - [Step 4: Connect the phone and authorize the computer](#step-4-connect-the-phone-and-authorize-the-computer)
  - [Step 5: Verify the connection](#step-5-verify-the-connection)
  - [Troubleshooting the ADB connection](#troubleshooting-the-adb-connection)
- [Quick start](#quick-start)
- [The debloat batches explained](#the-debloat-batches-explained)
- [Backup & restore](#backup--restore)
- [Safety guarantees](#safety-guarantees)
- [What is NOT removed (and why)](#what-is-not-removed-and-why)
- [HyperOS-specific notes](#hyperos-specific-notes)
- [Performance optimizations applied](#performance-optimizations-applied)
  - [Animation speed-up (0.5x)](#animation-speed-up-05x)
  - [Bluetooth off (if unused)](#bluetooth-off-if-unused)
  - [Encrypted private DNS (Cloudflare)](#encrypted-private-dns-cloudflare)
  - [Memory Extension - disable it (12 GB RAM variant)](#memory-extension---disable-it-12-gb-ram-variant)
- [Battery health notes](#battery-health-notes)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Disclaimer](#disclaimer)

---

## What this project does

Three bash scripts that talk to your POCO F7 over `adb`:

| Script | Purpose |
|---|---|
| `install.sh` | One-liner installer - downloads `debloat.sh` + `restore.sh` from GitHub and runs debloat interactively |
| `debloat.sh` | Removes 26 known-safe bloat packages in 6 small batches, with interactive prompts and a dry-run mode |
| `restore.sh` | Restores any removed package instantly from the untouched `/system` partition (no internet needed) |

Everything is **reversible**, **no root**, **no bootloader unlock**, **no warranty impact**, **no banking/Play Integrity breakage**.

The repository also ships with the actual backup snapshot from the author's device under `backup/`, so you can see exactly what was removed and when.

---

## Why debloat?

A stock POCO F7 ships with ~405 system packages. Many are useful, but a meaningful subset is:

1. **Ad/telemetry SDKs** that run constantly in the background and phone home (Xiaomi MSA, Joyose, analytics, bugreport, MiSightService)
2. **Duplicate Xiaomi apps** you've already replaced with better alternatives (Mi Browser, Mi Music, Mi Video, YellowPage, TouchAssistant, etc.)
3. **Meta background services** that track you even when you're not using Facebook (`com.facebook.system`, `services`, `appmanager`)
4. **Microsoft Link to Windows** services that run whether or not you use Phone Link on a PC
5. **Xiaomi's app recommendation engine** (GetApps / `mipicks` / `discover`) which pushes junk app installs in the background
6. **Google + Xiaomi extra bloat** (Google Duo/Meet, YouTube Music system app, Digital Wellbeing, Xiaomi barrage) that waste RAM or have better replacements

Removing these:
- Cuts background CPU/RAM usage (~500 MB+ RAM savings total)
- Stops most Xiaomi + Meta telemetry
- Prevents GetApps from auto-installing junk
- Frees storage (small) and RAM (noticeable)
- Improves battery life (modestly)
- Reduces ad surface area in Notification shade, Settings, and the launcher

---

## How it works (the science)

The whole toolkit is built on a single Android package-manager command:

```bash
adb shell pm uninstall -k --user 0 <package>
```

What this actually does:

| Flag | Meaning |
|---|---|
| `pm` | Android's package manager |
| `uninstall` | Remove the package |
| `-k` | **Keep the app's data** (so a restore brings back the same state) |
| `--user 0` | Only remove it for the **primary user profile**, not system-wide |

The crucial detail: **the APK on the read-only `/system` partition is never touched.** Only the user-profile registration is removed. This means:

- ✅ No root required
- ✅ No bootloader unlock required
- ✅ Banking apps / Play Integrity / SafetyNet keep working
- ✅ Warranty is unaffected (Xiaomi service centers don't check this)
- ✅ A factory reset restores every removed app instantly
- ✅ `pm install-existing --user 0 <pkg>` re-registers the app from `/system` - **no internet needed, instant**

This is the safest possible debloat method. The riskier alternatives (root + `/system` deletion, Magisk module hides, bootloader unlock + custom ROM) are not used here.

---

## Repository structure

```
9M2PJU-POCO-F7-Debloat-Script/
├── install.sh                          # One-liner installer (downloads + runs)
├── debloat.sh                          # Main debloat script (executable)
├── restore.sh                          # Restore script (executable)
├── README.md                           # This file
└── backup/                             # Snapshot of the author's debloat session
    ├── build_info.txt                  # ROM fingerprint, HyperOS version, security patch
    ├── removed_packages.txt            # The removal log (26 packages, batched + dated)
    ├── removed_diff.txt                # Auto-generated diff confirming what was removed
    ├── system_packages_before.txt      # 405 system packages before debloat
    ├── system_packages_after.txt       # 379 system packages after debloat
    ├── enabled_packages_before.txt     # 547 user-0 packages before
    ├── enabled_packages_after.txt      # 532 user-0 packages after
    ├── disabled_packages_before.txt    # Pre-existing disabled packages (4)
    ├── uninstalled_packages_before.txt # Pre-existing uninstalled-for-user packages (554)
    ├── third_party_packages_before.txt # User-installed apps (146)
    └── restore_all.sh                  # Legacy one-shot restore (use restore.sh instead)
```

The `backup/` folder is committed so others can see exactly what was removed on a real device. You do **not** need to keep this folder for your own debloat - `debloat.sh` will create it automatically.

---

## Requirements

- A POCO F7 (or any Xiaomi device running HyperOS 2 - package names may differ on other models)
- A computer with `adb` (Android Platform Tools) installed and in `PATH`
- A USB cable (data-capable, not charge-only)
- USB debugging enabled on the phone (see below)

### Step 1: Install `adb` on your computer

**Linux:**
```bash
# Debian / Ubuntu / Mint
sudo apt install adb

# Arch / Manjaro / CachyOS
sudo pacman -S android-tools

# Fedora
sudo dnf install android-tools
```

**macOS:**
```bash
brew install android-platform-tools
```

**Windows:**
- Download Platform Tools from https://developer.android.com/tools/releases/platform-tools
- Extract the ZIP to e.g. `C:\platform-tools`
- Add `C:\platform-tools` to your PATH, or open a terminal in that folder

Verify it works:
```bash
adb version
```

### Step 2: Enable Developer Options on the phone

These steps are for HyperOS 2 on the POCO F7. The flow is similar on other Xiaomi devices.

1. Open **Settings**
2. Tap **About phone** (top of the settings list)
3. Find the entry labeled **"HyperOS version"** (on older MIUI: **"MIUI version"**)
   - On the POCO F7 it's the tile that shows the HyperOS logo and version string
4. Tap it **7 times rapidly** in a row
5. You'll see a countdown toast: *"You are N steps away from being a developer"*
6. After the 7th tap, you'll see: *"You are now a developer"*
7. Developer Options is now unlocked

> If you don't see the toast, you may already be a developer. Try tapping 3-4 more times - you'll get *"You are already a developer"*.

### Step 3: Enable USB debugging

1. Go back to the main **Settings** screen
2. Scroll down and tap **Additional settings** (sometimes labeled **More settings**)
3. At the very bottom, you'll now see **Developer options** - tap it
4. Toggle **Developer options** ON at the top (the master switch)
5. Scroll down to the **Debugging** section
6. Toggle **USB debugging** ON
7. A dialog appears: *"Allow USB debugging? / USB debugging is intended for development purposes only..."* - tap **OK**
8. (Optional but recommended) Also enable **"Install via USB"** - some HyperOS builds require this for `pm install-existing` to work during restore
9. (Optional) Enable **"USB debugging (Security settings)"** if present - allows signing into some Xiaomi services over ADB. Not required for debloat.

### Step 4: Connect the phone and authorize the computer

1. Plug the phone into your computer with a **data-capable USB cable** (some cables only carry power - if `adb devices` shows nothing, try a different cable)
2. Pull down the **notification shade** on the phone
3. Tap the USB notification (usually says "Charging this device via USB" or "USB charging")
4. Change USB mode to **"File transfer"** / **"MTP"** (some HyperOS builds need this for ADB to be detected)
5. A dialog appears on the phone: *"Allow USB debugging?* / *The computer's RSA key fingerprint is: XX:XX:XX:..."*
6. (Recommended) Check the box **"Always allow from this computer"**
7. Tap **Allow** / **OK**

### Step 5: Verify the connection

On your computer, run:
```bash
adb devices -l
```

You should see something like:
```
List of devices attached
db80429a               device usb:1-1.2 product:onyx_global model:25053PC47G device:onyx transport_id:1
```

The state column should say **`device`**. If it says:
- **`unauthorized`** - you didn't accept the prompt on the phone, or you need to revoke and re-authorize (see Troubleshooting below)
- **`offline`** - the cable or USB port is flaky, or ADB server is stuck - try `adb kill-server && adb start-server` and replug
- **(empty list)** - cable is charge-only, USB mode is wrong, or driver issue (Windows)

### Troubleshooting the ADB connection

**`adb devices` shows nothing:**
- Make sure the cable is data-capable (try a different cable - many cheap cables are charge-only)
- Try a different USB port (prefer USB-A on a desktop, not a hub)
- On the phone, pull down the notification shade and switch USB mode to **"File transfer"**
- Restart the ADB server: `adb kill-server && adb start-server`
- On Windows, you may need to install the **Xiaomi USB driver** (download from https://miuirom.org/xiaomi-usb-drivers or use the generic Google USB driver from Platform Tools)

**`adb devices` shows `unauthorized`:**
- Look at the phone screen - there should be an "Allow USB debugging?" dialog. Tap **Allow**.
- If you previously denied it, revoke and retry:
  1. On the phone: Settings → Additional settings → Developer options → scroll to bottom → **"Revoke USB debugging authorizations"**
  2. Tap **OK** on the confirmation
  3. Unplug and replug the USB cable
  4. Accept the new authorization prompt

**`adb devices` shows `offline`:**
- `adb kill-server && adb start-server`
- Replug the cable
- Try a different USB port

**The "Allow USB debugging?" prompt never appears:**
- Make sure USB mode is set to **"File transfer"** (not "Charging only" or "PTP")
- Toggle USB debugging OFF and back ON in Developer options
- Revoke authorizations (see above) and replug

**Developer options disappeared after a reboot:**
- This shouldn't happen on HyperOS 2. If it does, re-do Step 2 (tap HyperOS version 7 times). Some Xiaomi accounts sync this setting - sign out of Mi Account in Settings → Mi Account if it keeps resetting.

---

## Quick start

```bash
# 1. Clone
git clone git@github.com:9M2PJU/9M2PJU-POCO-F7-Debloat-Script.git
cd 9M2PJU-POCO-F7-Debloat-Script

# 2. Verify your phone is connected
adb devices -l

# 3. Preview what would be removed (dry run, changes nothing)
bash debloat.sh --list

# 4. Run interactively (prompts y/N before each batch)
bash debloat.sh

# Or run non-interactively (removes all 6 batches)
bash debloat.sh --yes

# Or run a single batch only
bash debloat.sh --batch 1
```

After each batch, **test the phone** (unlock, open Settings, open the launcher, take a screenshot, reboot once). If anything breaks, restore that batch:

```bash
bash restore.sh --batch 1
```

---

## The debloat batches explained

### Batch 1 - Ad/telemetry (4 packages)

| Package | What it is | Why remove |
|---|---|---|
| `com.miui.msa.global` | **Xiaomi Ad SDK** - pushes ads in Notifications, GetApps, Settings | Single biggest privacy win |
| `com.xiaomi.joyose` | Telemetry + Game Turbo backend | Stops Xiaomi usage analytics; disables Game Turbo advanced features (acceptable trade-off if you don't game seriously) |
| `com.miui.analytics` | Usage analytics | Stops usage pattern reporting |
| `com.miui.bugreport` | Bug report uploader | Stops automatic bug report telemetry |

### Batch 2 - Xiaomi duplicate apps (9 packages)

| Package | What it is | Why remove |
|---|---|---|
| `com.mi.globalbrowser` | Mi Browser | Replaced by Firefox/Chrome |
| `com.miui.player` | Mi Music | Replaced by Spotify/YouTube Music |
| `com.miui.videoplayer` | Mi Video | Replaced by VLC |
| `com.miui.yellowpage` | Business directory spam | Useless in most regions |
| `com.miui.touchassistant` | Floating ball assistant | Gimmick; uses RAM |
| `com.miui.thirdappassistant` | Third-party app promo | Pushes app recommendations |
| `com.miui.securityadd` | Security add-on module | Redundant with main Security Center |
| `com.xiaomi.mipicks` | **GetApps** - Xiaomi's app store | Pushes junk app installs in background; major nuisance |
| `com.xiaomi.discover` | GetApps companion | Same as above |

### Batch 3 - Meta background services (3 packages)

| Package | What it is | Why remove |
|---|---|---|
| `com.facebook.system` | Meta background service | Tracking SDK; runs constantly |
| `com.facebook.services` | Meta app support service | Background helper |
| `com.facebook.appmanager` | Meta app updater | Auto-updates FB apps; Play Store does this anyway |

> **Note:** `com.facebook.katana` (the Facebook app itself) is intentionally **NOT** removed. The app still works without these three services - they're optional helpers, not required dependencies.

### Batch 4 - Microsoft Link to Windows (3 packages)

| Package | What it is | Why remove |
|---|---|---|
| `com.microsoft.appmanager` | Phone Link companion | Only useful if you use Phone Link on Windows |
| `com.microsoft.deviceintegrationservice` | Cross-device integration service | Same |
| `com.microsoftsdk.crossdeviceservicebroker` | SDK broker for Link to Windows | Same |

> **Note:** `com.microsoft.office.word` (the Word user app) is intentionally **NOT** removed.

### Batch 5 - Xiaomi app drawer search + minus screen (2 packages)

| Package | What it is | Why remove |
|---|---|---|
| `com.mi.appfinder` | App drawer search bar (~298 MB RAM) | Spyware-ish; indexes app usage |
| `com.mi.globalminusscreen` | Leftmost "minus screen" with news/ads (~255 MB RAM) | Ad surface; rarely used |

### Batch 6 - Google + Xiaomi extra bloat (5 packages)

| Package | What it is | Why remove |
|---|---|---|
| `com.google.android.apps.tachyon` | Google Duo/Meet (83 MB RAM running) | Replaced by WhatsApp/Discord for video calls |
| `com.google.android.apps.youtube.music` | YouTube Music system app | Replaced by ReVanced YouTube Music |
| `com.google.android.apps.wellbeing` | Digital Wellbeing (37 MB RAM running) | Screen time tracker; not used |
| `com.miui.misightservice` | Xiaomi insights/telemetry (10 MB RAM running) | Same telemetry category as Joyose (Batch 1) |
| `com.xiaomi.barrage` | Xiaomi bullet comments (danmaku overlay) | Chinese-market feature; useless outside China |

---

## Backup & restore

### What gets backed up

When `debloat.sh` runs, it creates a `backup/` folder (if missing) and writes:

- `removed_packages.txt` - every removed package, grouped by batch with date headers
- (Optionally, you can pre-snapshot with `adb shell pm list packages -s > backup/system_packages_before.txt`)

### How to restore

```bash
# Restore everything in the log
bash restore.sh

# Restore one specific package
bash restore.sh com.miui.msa.global

# Restore several packages
bash restore.sh com.miui.msa.global com.xiaomi.joyose com.miui.analytics

# Restore a specific batch (1-5)
bash restore.sh --batch 3

# Preview what would be restored (dry run)
bash restore.sh --list
```

Restore uses `pm install-existing --user 0`, which re-registers the app from the **untouched `/system` APK** - instant, no internet required. If a package was disabled rather than uninstalled, the script falls back to `pm enable`.

### The nuclear undo

A factory reset (Settings → Additional settings → Back up and reset → Factory reset) restores every system app, regardless of what `removed_packages.txt` says. This is always available as a last resort.

---

## Safety guarantees

1. **No root, no bootloader unlock** - works on a fully stock, locked device.
2. **No banking/Play Integrity breakage** - SafetyNet / Play Integrity checks pass because the system partition is untouched and the bootloader is locked.
3. **No warranty impact** - Xiaomi service centers do not check user-profile package state.
4. **Fully reversible** - every removal is logged; `restore.sh` brings everything back in seconds.
5. **Idempotent** - running `debloat.sh` twice is safe; already-removed packages are skipped.
6. **No data loss** - the `-k` flag preserves app data, so a restore brings back the same state.
7. **No bricking possible** - `pm uninstall --user 0` cannot bootloop a phone. The worst case is a disabled feature, which `restore.sh` fixes.

---

## What is NOT removed (and why)

These packages are intentionally left alone because removing them causes bootloops, broken Settings, lost features, or breaks core Xiaomi services:

| Package | Why it stays |
|---|---|
| `com.android.systemui` | System UI (status bar, navigation, notifications) |
| `com.android.settings` | Settings app |
| `com.android.phone` | Telephony stack |
| `com.android.providers.*` | Content providers - removing breaks everything |
| `com.miui.home` | Default launcher (keep as fallback even if using Nova) |
| `com.xiaomi.finddevice` | Find My Phone |
| `com.xiaomi.account` | Mi Account services |
| `com.xiaomi.misettings` | Mi Settings panel - many HyperOS features depend on it |
| `com.miui.securitycenter` | Main Security Center app |
| `com.miui.daemon` | System daemon - **never touch** |
| `com.miui.miwallpaper` | Wallpaper engine (removing breaks AOD/lockscreen wallpaper) |
| `com.miui.misound` | Audio settings (removing hides Dolby Atmos toggle) |
| `com.miui.screenshot` | Screenshot tool (removing breaks 3-finger swipe) |
| `com.miui.cloudservice` | Mi Cloud sync (only disable if you don't use Mi Cloud) |
| `com.miui.backup` | Xiaomi backup tool (some HyperOS features depend on it) |
| `com.miui.accessibility` | Accessibility framework |
| `com.google.android.gms` | Google Play Services - removing breaks everything Google |
| `com.google.android.gsf` | Google Services Framework |
| `com.android.vending` | Play Store |
| `com.android.inputmethod.*` | Keyboard |

If you're tempted to remove something in this list, **don't**. The risk/reward is not worth it.

---

## HyperOS-specific notes

- **GetApps (`com.xiaomi.mipicks`) re-installs apps after OTA.** This is why we remove it entirely rather than just disabling it. After major HyperOS updates, re-run `debloat.sh --yes` to re-remove anything that came back.
- **Joyose controls Game Turbo.** Removing it disables Game Turbo's advanced features (frame interpolation, per-game performance profiles). If you game seriously, keep Joyose. If not, remove it for the telemetry cut.
- **MSA (`com.miui.msa.global`) is the single most worthwhile removal** for privacy - it's the Xiaomi Ad SDK that powers ads across Notifications, GetApps, and Settings.
- **After a HyperOS major update**, some removed apps come back. Re-run `debloat.sh --yes` from the saved log to clean up.
- **Some packages are stub overlays** (e.g. `com.miui.miwallpaper.overlay`). Don't remove overlays individually - they're tiny and harmless, and removing the wrong one can break theming.
- **HyperOS 2 on Android 16** uses kernel 6.6.77 with the `walt` CPU governor. The debloat doesn't touch any of this - it's purely user-profile package removal.

---

## Performance optimizations applied

In addition to debloating, the author applied these optimizations to the test device (NOT done by `debloat.sh` - run them manually if you want them):

### Animation speed-up (0.5x)

```bash
adb shell settings put global window_animation_scale 0.5
adb shell settings put global transition_animation_scale 0.5
adb shell settings put global animator_duration_scale 0.5
```

Makes the UI feel noticeably snappier. Undo with `1.0` instead of `0.5`.

### Bluetooth off (if unused)

```bash
adb shell svc bluetooth disable
```

Saves a small amount of battery. Re-enable with `svc bluetooth enable` or the Quick Settings toggle.

### Encrypted private DNS (Cloudflare)

Set in Settings → Private DNS → "Custom provider hostname":
```
dns.cloudflare.com
```

Or use the DNS-over-HTTPS hostname for stricter malware blocking:
```
security.cloudflare-dns.com
```

System-wide encrypted DNS via Cloudflare's 1.1.1.1 resolver. Free, fast, privacy-respecting (no IP logging). Pairs well with the MSA removal for privacy.

### Memory Extension - disable it (12 GB RAM variant)

HyperOS "Memory Extension" (Settings → Additional settings → Memory Extension) is a hybrid swap system with two layers:

1. **ZRAM** (always on, kernel-level) - compresses cold RAM pages in-place. On the POCO F7 it uses ~800 MB of physical RAM to hold ~2.6 GB of compressed data at a ~3.3x ratio. This is **good** - effectively free extra RAM at RAM speed.
2. **Storage-backed swap** (the toggle) - uses a file on UFS 4.1 storage as additional swap. This is the **slow** layer: ~10-50x slower than RAM when touched.

On the 12 GB RAM variant, the storage-backed layer is essentially unused (only ~2.6 GB of swap is actually in use, all in ZRAM). Disabling it:

- Removes the slow storage-swap layer (no more micro-stutters from page-in stalls)
- Reduces UFS write wear (random small IOs are the worst for flash)
- Keeps ZRAM (the fast, beneficial layer) - you don't lose the compression benefit
- Frees whatever the swap file was reserving on storage (usually 4-8 GB)

**Recommendation for 12 GB RAM variant: disable.** You have plenty of RAM (typically 7+ GB free) and will essentially never hit the 12 GB ceiling with normal usage. ZRAM stays on and gives you the real benefit.

**When to keep it ON instead:**
- You play heavy 3D games (Genshin, CoD Mobile at max) AND keep many apps in background
- You regularly see "apps reloading" when switching between them
- You have the 8 GB RAM variant (you actually need it then)

**How to disable:**
Settings → Additional settings → Memory Extension → toggle OFF → reboot

After reboot, verify ZRAM-only swap is active:
```bash
adb shell "cat /proc/meminfo | grep -E 'SwapTotal|SwapFree'"
# SwapTotal should drop from ~12.5 GB to ~4-6 GB (ZRAM-only)
```

**What to expect after disabling:**
- Day-to-day: no noticeable change (you have plenty of RAM)
- Heavy multitasking: apps may reload slightly more often instead of resuming from storage swap (rare with 12 GB)
- Gaming: same or slightly better (no storage-swap stalls)
- Battery: negligible change
- Storage: get back 4-8 GB
- UFS lifespan: slightly improved (less random write wear)

---

## Battery health notes

The author's POCO F7 (activated 2025-10-31) shows:

```
Estimated battery capacity:    6500 mAh   (design spec)
Last learned battery capacity: 6209 mAh   (BMS-measured)
Retention:                     95.5%      (after ~8.9 months)
```

**95.5% is normal and healthy.** A brand-new POCO F7 typically shows 97-99% out of the box due to:
1. Factory cell variance (design spec is the *minimum* rated capacity)
2. BMS safety margins (the BMS reports usable capacity, not raw chemical capacity)
3. Normal chemical aging (~0.5%/month is typical for Li-poly)

Tips to slow future degradation:
- Enable HyperOS charging optimization (Settings → Battery → hold at 80% overnight)
- Avoid deep discharges (keep it in 30-80% range)
- Avoid hot fast-charging sessions (use a slower charger overnight)
- Don't worry about "training" the battery - that's outdated advice for NiMH, not Li-poly

Monitor over time with:
```bash
adb shell dumpsys batterystats --charged | grep -iE 'Estimated battery capacity|learned battery capacity'
```

Replace the battery when "learned" capacity drops below ~5200 mAh (80%).

---

## Troubleshooting

> For ADB connection issues (device not detected, `unauthorized`, `offline`), see [Troubleshooting the ADB connection](#troubleshooting-the-adb-connection) under Requirements above.

### A removal fails with `DELETE_FAILED_INTERNAL_ERROR`

The package is protected by the system. Skip it - don't fight it. The script will report `FAIL` and continue.

### Settings crashes after a removal

Restore the most recent batch:
```bash
bash restore.sh --batch N    # where N is the batch you just ran
```

If you don't know which batch caused it, restore everything:
```bash
bash restore.sh
```

### The phone bootloops

This **cannot** happen from `pm uninstall --user 0`. If your phone is bootlooping, something else caused it (a bad OTA, a Magisk module, etc.). The debloat is not the cause. Factory reset to recover.

### `restore.sh` reports `FAIL` for some packages

This happens after a HyperOS OTA if the package was removed from the system partition entirely. A factory reset will restore everything. Otherwise, the package is genuinely gone from your firmware.

---

## FAQ

**Q: Will this void my warranty?**
A: No. `pm uninstall --user 0` only affects your user profile. The system partition is untouched, the bootloader stays locked, and Xiaomi service centers don't check user-profile package state.

**Q: Will banking apps still work?**
A: Yes. Play Integrity / SafetyNet checks pass because the system partition is untouched and the bootloader is locked. Root would break these - this script does not root.

**Q: Will OTA updates still work?**
A: Yes. System updates install normally. Some removed apps may come back after a major OTA - re-run `debloat.sh --yes` to clean up.

**Q: Can I run this on other Xiaomi phones?**
A: The package names are HyperOS-specific and most apply to any recent Xiaomi device (POCO, Redmi, Mi). However, some packages may not exist on your firmware - the script skips missing packages gracefully. Always run `--list` first to preview.

**Q: Can I run this on non-Xiaomi phones?**
A: No. The package names (`com.miui.*`, `com.xiaomi.*`) are Xiaomi-specific. Samsung, Pixel, etc. have their own bloat with different package names.

**Q: Does this need root?**
A: No. This is the whole point - it works on a fully stock, locked device.

**Q: How much RAM/storage does this free?**
A: RAM: ~600 MB - 1.2 GB depending on what was running (Batch 6 alone frees ~130 MB from running processes). Storage: minimal (~50-100 MB), because the APKs stay on `/system`. The main benefit is reduced background CPU/battery drain and privacy, not storage.

**Q: Will GetApps come back?**
A: After a major HyperOS OTA, possibly yes. Re-run `debloat.sh --yes` to re-remove. This is why the script is idempotent.

**Q: Can I add my own packages to remove?**
A: Yes. Either pass them explicitly to `restore.sh` for undo, or add a new `BATCH6=(...)` line to `debloat.sh` following the existing pattern. Always test with `--list` first.

**Q: The load average is high after debloat - is something wrong?**
A: No. On Snapdragon 8s Gen 4 + HyperOS, the `cpudmof/*` kernel DMA-fence threads sit in D-state and inflate the load average. This is cosmetic - actual CPU usage is low (cores idle at 441 MHz). Check `top -n 1 -m 10 -s cpu` for real CPU consumers.

---

## Disclaimer

This script is provided as-is, without warranty. The author has tested it on their own POCO F7 (onyx_global, HyperOS V816) and it works cleanly there. Different ROM versions, regions, or future OTA updates may behave differently.

**You are responsible for your own device.** The script is designed to be safe (no root, no system partition changes, fully reversible), but if something goes wrong:

1. Run `bash restore.sh` to undo
2. If that doesn't help, factory reset
3. If that doesn't help, reflash the fastboot ROM via Mi Flash Tool

The author is not liable for any damage, data loss, or inconvenience. Use at your own risk.

---

## License

This project is licensed under the **GNU General Public License v3.0** (GPL-3.0). See the [LICENSE](LICENSE) file for the full text.

In short: you can use, modify, and distribute this project, including commercially, **but** any derivative work must also be licensed under GPL-3.0 and include the source code. This keeps the project and its derivatives open forever.

---

## Acknowledgements

- The Android open-source community for documenting `pm uninstall -k --user 0` as a safe debloat method
- [Universal Android Debloater](https://github.com/0x192/universal-android-debloater) for the inspiration and the comprehensive package database
- Xiaomi / POCO for making decent hardware that just needs a little cleanup

---

**73 de 9M2PJU** - happy debloating!

---

## Sponsor

If this script saved you time, consider buying me a coffee:

[![Buy me a coffee](https://cdn.buymeacoffee.com/buttons/default-orange.png)](https://www.buymeacoffee.com/9m2pju)

Or use the **Sponsor** button at the top of this repo on GitHub.
