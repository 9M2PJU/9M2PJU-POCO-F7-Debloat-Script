# 9M2PJU — POCO F7 Debloat Script

A safe, reversible, no-root debloat toolkit for the **POCO F7 (codename `onyx_global`)** running HyperOS 2 / Android 16.

> Maintained by [9M2PJU](https://github.com/9M2PJU) · Tested on ROM `OS3.0.302.0.WOLMIXM` (HyperOS V816, Android 16, security patch 2026-05-01)

---

## Table of contents

- [What this project does](#what-this-project-does)
- [Why debloat?](#why-debloat)
- [How it works (the science)](#how-it-works-the-science)
- [Repository structure](#repository-structure)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [The debloat batches explained](#the-debloat-batches-explained)
- [Backup & restore](#backup--restore)
- [Safety guarantees](#safety-guarantees)
- [What is NOT removed (and why)](#what-is-not-removed-and-why)
- [HyperOS-specific notes](#hyperos-specific-notes)
- [Performance optimizations applied](#performance-optimizations-applied)
- [Battery health notes](#battery-health-notes)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Disclaimer](#disclaimer)

---

## What this project does

Two bash scripts that talk to your POCO F7 over `adb`:

| Script | Purpose |
|---|---|
| `debloat.sh` | Removes 21 known-safe bloat packages in 5 small batches, with interactive prompts and a dry-run mode |
| `restore.sh` | Restores any removed package instantly from the untouched `/system` partition (no internet needed) |

Everything is **reversible**, **no root**, **no bootloader unlock**, **no warranty impact**, **no banking/Play Integrity breakage**.

The repository also ships with the actual backup snapshot from the author's device under `backup/`, so you can see exactly what was removed and when.

---

## Why debloat?

A stock POCO F7 ships with ~405 system packages. Many are useful, but a meaningful subset is:

1. **Ad/telemetry SDKs** that run constantly in the background and phone home (Xiaomi MSA, Joyose, analytics, bugreport)
2. **Duplicate Xiaomi apps** you've already replaced with better alternatives (Mi Browser, Mi Music, Mi Video, YellowPage, TouchAssistant, …)
3. **Meta background services** that track you even when you're not using Facebook (`com.facebook.system`, `services`, `appmanager`)
4. **Microsoft Link to Windows** services that run whether or not you use Phone Link on a PC
5. **Xiaomi's app recommendation engine** (GetApps / `mipicks` / `discover`) which pushes junk app installs in the background

Removing these:
- Cuts background CPU/RAM usage
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
- ✅ `pm install-existing --user 0 <pkg>` re-registers the app from `/system` — **no internet needed, instant**

This is the safest possible debloat method. The riskier alternatives (root + `/system` deletion, Magisk module hides, bootloader unlock + custom ROM) are not used here.

---

## Repository structure

```
9M2PJU-POCO-F7-Debloat-Script/
├── debloat.sh                          # Main debloat script (executable)
├── restore.sh                          # Restore script (executable)
├── README.md                           # This file
└── backup/                             # Snapshot of the author's debloat session
    ├── build_info.txt                  # ROM fingerprint, HyperOS version, security patch
    ├── removed_packages.txt            # The removal log (21 packages, batched + dated)
    ├── removed_diff.txt                # Auto-generated diff confirming what was removed
    ├── system_packages_before.txt      # 405 system packages before debloat
    ├── system_packages_after.txt       # 386 system packages after debloat
    ├── enabled_packages_before.txt     # 547 user-0 packages before
    ├── enabled_packages_after.txt      # 532 user-0 packages after
    ├── disabled_packages_before.txt    # Pre-existing disabled packages (4)
    ├── uninstalled_packages_before.txt # Pre-existing uninstalled-for-user packages (554)
    ├── third_party_packages_before.txt # User-installed apps (146)
    └── restore_all.sh                  # Legacy one-shot restore (use restore.sh instead)
```

The `backup/` folder is committed so others can see exactly what was removed on a real device. You do **not** need to keep this folder for your own debloat — `debloat.sh` will create it automatically.

---

## Requirements

- A POCO F7 (or any Xiaomi device running HyperOS 2 — package names may differ on other models)
- A computer with `adb` (Android Platform Tools) installed and in `PATH`
- A USB cable (data-capable, not charge-only)
- USB debugging enabled on the phone:
  1. Settings → About phone → tap "HyperOS version" / "MIUI version" 7 times to unlock Developer options
  2. Settings → Additional settings → Developer options → enable **USB debugging**
  3. Plug in the phone, accept the "Allow USB debugging?" prompt
- Verify with `adb devices -l` — your phone should show as `device` (not `unauthorized`)

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

# Or run non-interactively (removes all 5 batches)
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

### Batch 1 — Ad/telemetry (4 packages)

| Package | What it is | Why remove |
|---|---|---|
| `com.miui.msa.global` | **Xiaomi Ad SDK** — pushes ads in Notifications, GetApps, Settings | Single biggest privacy win |
| `com.xiaomi.joyose` | Telemetry + Game Turbo backend | Stops Xiaomi usage analytics; disables Game Turbo advanced features (acceptable trade-off if you don't game seriously) |
| `com.miui.analytics` | Usage analytics | Stops usage pattern reporting |
| `com.miui.bugreport` | Bug report uploader | Stops automatic bug report telemetry |

### Batch 2 — Xiaomi duplicate apps (9 packages)

| Package | What it is | Why remove |
|---|---|---|
| `com.mi.globalbrowser` | Mi Browser | Replaced by Firefox/Chrome |
| `com.miui.player` | Mi Music | Replaced by Spotify/YouTube Music |
| `com.miui.videoplayer` | Mi Video | Replaced by VLC |
| `com.miui.yellowpage` | Business directory spam | Useless in most regions |
| `com.miui.touchassistant` | Floating ball assistant | Gimmick; uses RAM |
| `com.miui.thirdappassistant` | Third-party app promo | Pushes app recommendations |
| `com.miui.securityadd` | Security add-on module | Redundant with main Security Center |
| `com.xiaomi.mipicks` | **GetApps** — Xiaomi's app store | Pushes junk app installs in background; major nuisance |
| `com.xiaomi.discover` | GetApps companion | Same as above |

### Batch 3 — Meta background services (3 packages)

| Package | What it is | Why remove |
|---|---|---|
| `com.facebook.system` | Meta background service | Tracking SDK; runs constantly |
| `com.facebook.services` | Meta app support service | Background helper |
| `com.facebook.appmanager` | Meta app updater | Auto-updates FB apps; Play Store does this anyway |

> **Note:** `com.facebook.katana` (the Facebook app itself) is intentionally **NOT** removed. The app still works without these three services — they're optional helpers, not required dependencies.

### Batch 4 — Microsoft Link to Windows (3 packages)

| Package | What it is | Why remove |
|---|---|---|
| `com.microsoft.appmanager` | Phone Link companion | Only useful if you use Phone Link on Windows |
| `com.microsoft.deviceintegrationservice` | Cross-device integration service | Same |
| `com.microsoftsdk.crossdeviceservicebroker` | SDK broker for Link to Windows | Same |

> **Note:** `com.microsoft.office.word` (the Word user app) is intentionally **NOT** removed.

### Batch 5 — Xiaomi app drawer search + minus screen (2 packages)

| Package | What it is | Why remove |
|---|---|---|
| `com.mi.appfinder` | App drawer search bar (~298 MB RAM) | Spyware-ish; indexes app usage |
| `com.mi.globalminusscreen` | Leftmost "minus screen" with news/ads (~255 MB RAM) | Ad surface; rarely used |

---

## Backup & restore

### What gets backed up

When `debloat.sh` runs, it creates a `backup/` folder (if missing) and writes:

- `removed_packages.txt` — every removed package, grouped by batch with date headers
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

Restore uses `pm install-existing --user 0`, which re-registers the app from the **untouched `/system` APK** — instant, no internet required. If a package was disabled rather than uninstalled, the script falls back to `pm enable`.

### The nuclear undo

A factory reset (Settings → Additional settings → Back up and reset → Factory reset) restores every system app, regardless of what `removed_packages.txt` says. This is always available as a last resort.

---

## Safety guarantees

1. **No root, no bootloader unlock** — works on a fully stock, locked device.
2. **No banking/Play Integrity breakage** — SafetyNet / Play Integrity checks pass because the system partition is untouched and the bootloader is locked.
3. **No warranty impact** — Xiaomi service centers do not check user-profile package state.
4. **Fully reversible** — every removal is logged; `restore.sh` brings everything back in seconds.
5. **Idempotent** — running `debloat.sh` twice is safe; already-removed packages are skipped.
6. **No data loss** — the `-k` flag preserves app data, so a restore brings back the same state.
7. **No bricking possible** — `pm uninstall --user 0` cannot bootloop a phone. The worst case is a disabled feature, which `restore.sh` fixes.

---

## What is NOT removed (and why)

These packages are intentionally left alone because removing them causes bootloops, broken Settings, lost features, or breaks core Xiaomi services:

| Package | Why it stays |
|---|---|
| `com.android.systemui` | System UI (status bar, navigation, notifications) |
| `com.android.settings` | Settings app |
| `com.android.phone` | Telephony stack |
| `com.android.providers.*` | Content providers — removing breaks everything |
| `com.miui.home` | Default launcher (keep as fallback even if using Nova) |
| `com.xiaomi.finddevice` | Find My Phone |
| `com.xiaomi.account` | Mi Account services |
| `com.xiaomi.misettings` | Mi Settings panel — many HyperOS features depend on it |
| `com.miui.securitycenter` | Main Security Center app |
| `com.miui.daemon` | System daemon — **never touch** |
| `com.miui.miwallpaper` | Wallpaper engine (removing breaks AOD/lockscreen wallpaper) |
| `com.miui.misound` | Audio settings (removing hides Dolby Atmos toggle) |
| `com.miui.screenshot` | Screenshot tool (removing breaks 3-finger swipe) |
| `com.miui.cloudservice` | Mi Cloud sync (only disable if you don't use Mi Cloud) |
| `com.miui.backup` | Xiaomi backup tool (some HyperOS features depend on it) |
| `com.miui.accessibility` | Accessibility framework |
| `com.google.android.gms` | Google Play Services — removing breaks everything Google |
| `com.google.android.gsf` | Google Services Framework |
| `com.android.vending` | Play Store |
| `com.android.inputmethod.*` | Keyboard |

If you're tempted to remove something in this list, **don't**. The risk/reward is not worth it.

---

## HyperOS-specific notes

- **GetApps (`com.xiaomi.mipicks`) re-installs apps after OTA.** This is why we remove it entirely rather than just disabling it. After major HyperOS updates, re-run `debloat.sh --yes` to re-remove anything that came back.
- **Joyose controls Game Turbo.** Removing it disables Game Turbo's advanced features (frame interpolation, per-game performance profiles). If you game seriously, keep Joyose. If not, remove it for the telemetry cut.
- **MSA (`com.miui.msa.global`) is the single most worthwhile removal** for privacy — it's the Xiaomi Ad SDK that powers ads across Notifications, GetApps, and Settings.
- **After a HyperOS major update**, some removed apps come back. Re-run `debloat.sh --yes` from the saved log to clean up.
- **Some packages are stub overlays** (e.g. `com.miui.miwallpaper.overlay`). Don't remove overlays individually — they're tiny and harmless, and removing the wrong one can break theming.
- **HyperOS 2 on Android 16** uses kernel 6.6.77 with the `walt` CPU governor. The debloat doesn't touch any of this — it's purely user-profile package removal.

---

## Performance optimizations applied

In addition to debloating, the author applied these optimizations to the test device (NOT done by `debloat.sh` — run them manually if you want them):

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

### Encrypted private DNS (NextDNS)

Set in Settings → Private DNS → "Custom provider hostname":
```
e5872a.dns.nextdns.io
```

System-wide encrypted DNS, blocks ads/trackers at the DNS level. Pairs well with the MSA removal for privacy.

---

## Battery health notes

The author's POCO F7 (activated 2025-10-31) shows:

```
Estimated battery capacity:    6500 mAh   (design spec)
Last learned battery capacity: 6209 mAh   (BMS-measured)
Retention:                     95.5%      (after ~8.9 months)
```

**95.5% is normal and healthy.** A brand-new POCO F7 typically shows 97–99% out of the box due to:
1. Factory cell variance (design spec is the *minimum* rated capacity)
2. BMS safety margins (the BMS reports usable capacity, not raw chemical capacity)
3. Normal chemical aging (~0.5%/month is typical for Li-poly)

Tips to slow future degradation:
- Enable HyperOS charging optimization (Settings → Battery → hold at 80% overnight)
- Avoid deep discharges (keep it in 30–80% range)
- Avoid hot fast-charging sessions (use a slower charger overnight)
- Don't worry about "training" the battery — that's outdated advice for NiMH, not Li-poly

Monitor over time with:
```bash
adb shell dumpsys batterystats --charged | grep -iE 'Estimated battery capacity|learned battery capacity'
```

Replace the battery when "learned" capacity drops below ~5200 mAh (80%).

---

## Troubleshooting

### `adb devices` shows nothing

- USB debugging not enabled → Settings → Additional settings → Developer options → USB debugging
- Cable is charge-only → use a data cable
- USB mode wrong → pull down notification shade, switch to "File transfer (MTP)"
- Authorization prompt not accepted → tap "Allow" on the phone when prompted
- ADB server stuck → `adb kill-server && adb start-server`

### `adb devices` shows `unauthorized`

Accept the "Allow USB debugging?" prompt on the phone. If you previously denied it:
```bash
adb shell pm clear com.android.providers.settings  # not recommended
# Better: revoke and re-authorize
# Developer options → Revoke USB debugging authorizations → replug
```

### A removal fails with `DELETE_FAILED_INTERNAL_ERROR`

The package is protected by the system. Skip it — don't fight it. The script will report `FAIL` and continue.

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
A: Yes. Play Integrity / SafetyNet checks pass because the system partition is untouched and the bootloader is locked. Root would break these — this script does not root.

**Q: Will OTA updates still work?**
A: Yes. System updates install normally. Some removed apps may come back after a major OTA — re-run `debloat.sh --yes` to clean up.

**Q: Can I run this on other Xiaomi phones?**
A: The package names are HyperOS-specific and most apply to any recent Xiaomi device (POCO, Redmi, Mi). However, some packages may not exist on your firmware — the script skips missing packages gracefully. Always run `--list` first to preview.

**Q: Can I run this on non-Xiaomi phones?**
A: No. The package names (`com.miui.*`, `com.xiaomi.*`) are Xiaomi-specific. Samsung, Pixel, etc. have their own bloat with different package names.

**Q: Does this need root?**
A: No. This is the whole point — it works on a fully stock, locked device.

**Q: How much RAM/storage does this free?**
A: RAM: ~500 MB - 1 GB depending on what was running. Storage: minimal (~50-100 MB), because the APKs stay on `/system`. The main benefit is reduced background CPU/battery drain and privacy, not storage.

**Q: Will GetApps come back?**
A: After a major HyperOS OTA, possibly yes. Re-run `debloat.sh --yes` to re-remove. This is why the script is idempotent.

**Q: Can I add my own packages to remove?**
A: Yes. Either pass them explicitly to `restore.sh` for undo, or add a new `BATCH6=(...)` line to `debloat.sh` following the existing pattern. Always test with `--list` first.

**Q: The load average is high after debloat — is something wrong?**
A: No. On Snapdragon 8s Gen 4 + HyperOS, the `cpudmof/*` kernel DMA-fence threads sit in D-state and inflate the load average. This is cosmetic — actual CPU usage is low (cores idle at 441 MHz). Check `top -n 1 -m 10 -s cpu` for real CPU consumers.

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

This project is released into the public domain under the terms of [CC0](https://creativecommons.org/publicdomain/zero/1.0/). Do whatever you want with it.

---

## Acknowledgements

- The Android open-source community for documenting `pm uninstall -k --user 0` as a safe debloat method
- [Universal Android Debloater](https://github.com/0x192/universal-android-debloater) for the inspiration and the comprehensive package database
- Xiaomi / POCO for making decent hardware that just needs a little cleanup

---

**73 de 9M2PJU** — happy debloating!
