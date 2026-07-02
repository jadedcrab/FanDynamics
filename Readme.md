# FanDynamics

**Automatic, temperature-driven fan curves for Intel Macs — including OCLP-patched ones.**

FanDynamics continuously maps a temperature sensor to fan RPM through a fully editable curve — the headline feature of paid fan utilities, free and open source. Define your curve (or pick a preset), and the fans follow the heat: quiet at idle, aggressive when it matters.

## Features

- **Automatic fan curves** — piecewise-linear temperature→RPM curves per fan, evaluated every 5 seconds with EMA smoothing and a write deadband so fans never hunt or twitch.
- **Curve editor** — visual preview of the curve exactly as the control loop interprets it, live temperature marker, editable point table with steppers, °C/°F toggle, and built-in presets (Quiet / Balanced / Cool / Basic Ramp) that scale to any fan's hardware limits.
- **Unified settings window** — Status (live temp + RPM, manual sliders), Fan Curves, General, and Maintenance tabs. The menu bar stays minimal: two toggles, Preferences, Quit.
- **Menu bar readout** — optional live temp + RPM next to the fan icon.
- **Safety first** — targets clamped to true hardware limits, fans handed back to SMC automatic control at the bottom of the curve, on quit, and on SIGTERM (logout/shutdown).
- **OCLP support** — inherited from smcFanControl CE: boot-time fan daemon, Sleep/Wake fix, and update guardian for OpenCore Legacy Patcher Macs.

## Requirements

- Intel Mac, macOS 10.13+
- Apple Silicon support is planned (SMC fan writes are heavily restricted on M-series)

## Building

```sh
xcodebuild -scheme smcFanControl -configuration Release ARCHS=x86_64 MACOSX_DEPLOYMENT_TARGET=10.13 CODE_SIGNING_ALLOWED=NO build
```

(The Xcode project retains its original internal name; the product it builds is `FanDynamics.app`.)

## Lineage & license

FanDynamics is a fork of [smcFanControl Community Edition](https://github.com/wolffcatskyy/smcFanControl) (wolffcatskyy), itself a modernized fork of [smcFanControl](https://github.com/hholtmann/smcFanControl) by Hendrik Holtmann. The automatic curve engine, curve editor, presets, and unified settings window are new in FanDynamics; the SMC plumbing, OCLP support, and Sleep/Wake fix come from upstream. Bug fixes discovered here (broken link step from a clean clone; F0Mn min-speed register read back as the hardware floor) are candidates for upstreaming.

Licensed under the **GNU GPL v2** (see `LICENSE`), as inherited from upstream. Original copyright © 2006–2012 Hendrik Holtmann and contributors; Community Edition changes © their respective contributors; FanDynamics changes © 2026 jadedcrab.

**Disclaimer:** manipulating fan speeds affects thermals. The app refuses to go below hardware minimums, but you use it at your own risk, same as every fan utility.
