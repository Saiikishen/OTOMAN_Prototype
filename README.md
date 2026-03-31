# OTOMAN — Intelligent Living

> A Flutter-based smart home controller for ESP32-powered motor automation, featuring MQTT real-time control, WiFi provisioning, and time-based scheduling.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Features](#features)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [MQTT Interface](#mqtt-interface)
- [WiFi Provisioning Flow](#wifi-provisioning-flow)
- [Scheduling System](#scheduling-system)
- [ESP32 Firmware Requirements](#esp32-firmware-requirements)
- [Getting Started](#getting-started)
- [Building for Release](#building-for-release)

---

## Overview

OTOMAN is a production-grade Flutter application that communicates with an ESP32 microcontroller over MQTT to control industrial motor relays. It supports zero-config WiFi provisioning, persistent device scheduling, and verified command delivery with automatic UI revert on failure.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Flutter App                         │
│                                                         │
│  BuildingSelectionScreen                                │
│         │                                               │
│         ▼                                               │
│  DashboardScreen  ◄──── SchedulerService (Timer 30s)   │
│         │                      │                        │
│         ▼                      ▼                        │
│    Esp32Service ◄──────── DeviceSchedule / ScheduleSlot │
│         │                                               │
│  WifiProvisionService (HTTP — AP mode only)             │
└────────────┬────────────────────────────────────────────┘
             │ MQTT (broker.hivemq.com:1883)
             │
┌────────────▼────────────────────────────────────────────┐
│                     ESP32 Firmware                      │
│                                                         │
│  Normal mode:   WiFi STA + MQTT PubSubClient            │
│  Provision mode: WiFi AP + HTTP WebServer               │
│                                                         │
│  Motor 1: Dual-pin latching relay (GPIO 26 / 27)        │
│  Motor 2: Single-pin relay        (GPIO 25)             │
│  Reset:   BOOT button             (GPIO 0)              │
└─────────────────────────────────────────────────────────┘
```

---

## Features

- **Real-time motor control** — ON/OFF commands over MQTT with hardware-verified state echo
- **Optimistic UI with auto-revert** — UI updates instantly; reverts if ESP32 doesn't echo within 5 seconds
- **WiFi provisioning** — First-boot AP hotspot flow; credentials tested on-device before saving to NVS
- **Re-provisioning** — Via MQTT `RESET` command from the app, or hold BOOT button 3 seconds
- **Multi-slot scheduling** — Per-device time-based schedules with Turn ON / Turn OFF actions, individually togglable
- **Auto-reconnect** — MQTT client reconnects automatically on disconnect with 5s backoff
- **Retained status** — ESP32 publishes retained `esp32/status`; app reads last known state on connect
- **Last Will Testament** — ESP32 marks itself offline (`esp32/online: false`) if it drops unexpectedly
- **Editable entity names** — Long-press any building or device card to rename it

---

## Tech Stack

### Flutter App

| Package | Version | Purpose |
|---|---|---|
| `mqtt_client` | ^9.7.4 | MQTT broker communication |
| `http` | ^1.2.0 | HTTP provisioning (AP mode) |
| `uuid` | ^4.0.0 | Unique MQTT client IDs, schedule slot IDs |
| `google_fonts` | ^8.0.2 | Outfit typeface |
| `flutter_animate` | ^4.5.2 | Entry animations |
| `font_awesome_flutter` | ^10.12.0 | Device icons |
| `intl` | ^0.20.2 | Internationalisation utilities |

### ESP32 Firmware

| Library | Purpose |
|---|---|
| `PubSubClient` (Nick O'Leary) | MQTT client |
| `ArduinoJson` (Benoit Blanchon v6+) | JSON serialisation |
| `Preferences` (built-in) | NVS credential storage |
| `WiFi` / `WebServer` (built-in) | STA + AP mode |

---

## Project Structure

```
lib/
├── main.dart                        # App entry point
├── theme/
│   └── app_theme.dart               # AppColors, AppTheme (dark)
├── models/
│   └── schedule_entry.dart          # ScheduleSlot, DeviceSchedule, ScheduleAction
├── services/
│   ├── esp32_service.dart           # MQTT connect, command, verify, auto-reconnect
│   ├── wifi_provision_service.dart  # HTTP provisioning + MQTT WiFi reset
│   └── scheduler_service.dart       # Periodic timer, slot matching, MQTT trigger
├── screens/
│   ├── splash_screen.dart
│   ├── building_selection_screen.dart
│   ├── dashboard_screen.dart        # Device cards, schedule sheet, edit dialogs
│   └── provisioning_screen.dart     # Step-by-step WiFi setup flow
└── widgets/
    └── device_control_sheets.dart   # Fan / AC control bottom sheets
```

---

## MQTT Interface

All topics use the public HiveMQ broker (`broker.hivemq.com:1883`). Replace with a private broker for production.

### Subscribed by App

| Topic | Payload | Description |
|---|---|---|
| `esp32/status` | `{"motor1":bool,"motor2":bool,"wifi":"SSID"}` | Retained — real hardware state |
| `esp32/online` | `true` / `false` | LWT — device presence |

### Published by App

| Topic | Payload | Description |
|---|---|---|
| `esp32/motor1/control` | `ON` or `OFF` | DOL Motor command |
| `esp32/motor2/control` | `ON` or `OFF` | Normal Motor command |
| `esp32/system/wifi` | `RESET` | Triggers AP mode restart |

### Command Verification Flow

```
App  ──[esp32/motor1/control: "ON"]──►  Broker  ──►  ESP32
                                                        │
                                                   acts on relay
                                                        │
App  ◄──[esp32/status: {"motor1":true}]──  Broker  ◄──┘

If no echo within 5s → UI reverts to previous state
```

---

## WiFi Provisioning Flow

```
First Boot / After Reset
        │
        ▼
ESP32 starts AP: "ESP32-Setup" (open, no password)
        │
        ▼
User opens app → Settings ⚙ → Configure ESP32 WiFi
        │
        ▼
ProvisioningScreen:
  Step 1 — Instructions (connect phone to "ESP32-Setup")
  Step 2 — Reachability check  GET 192.168.4.1/status
  Step 3 — Enter SSID + password
  Step 4 — POST 192.168.4.1/configure {"ssid":"...","password":"..."}
        │
        ▼
ESP32 tests credentials (up to 10s) → saves to NVS → restarts
        │
        ▼
ESP32 connects to home WiFi → MQTT broker
User reconnects phone to home WiFi → app connects via MQTT
```

### Re-provisioning Options

| Method | How |
|---|---|
| Via app | Settings → Configure ESP32 WiFi → sends `RESET` to `esp32/system/wifi` |
| Physical | Hold BOOT button (GPIO 0) for 3 seconds |

---

## Scheduling System

Each device supports multiple independent schedule slots. The scheduler runs a `Timer.periodic` every 30 seconds and compares each active slot's time against `DateTime.now()`.

```
DeviceSchedule (per device)
└── ScheduleSlot[]
    ├── id        (UUID v4)
    ├── hour      (0–23)
    ├── minute    (0–59)
    ├── action    (ScheduleAction.turnOn | turnOff)
    └── enabled   (bool — per-slot toggle)
```

When a slot fires, it calls `Esp32Service.toggleMotor1/2()` which uses the same verified MQTT flow as manual taps — the UI updates only when the ESP32 echoes back the new state.

---

## ESP32 Firmware Requirements

The firmware must implement the following for full app compatibility:

### MQTT
- Connect to `broker.hivemq.com:1883` with client ID `esp32-motor-001`
- Subscribe to `esp32/motor1/control`, `esp32/motor2/control`, `esp32/system/wifi`
- On receiving a motor command → act on relay → **immediately publish retained `esp32/status`**
- Set LWT: topic `esp32/online`, payload `false`, retain `true`
- Publish `esp32/online: true` on connect

### HTTP (AP mode — 192.168.4.1)
- `GET /status` → `200 {"configured":false,"mode":"provisioning"}`
- `POST /configure` body `{"ssid":"...","password":"..."}` → test creds → save to NVS → restart → `200 {"success":true}`

### GPIO
| Pin | Function |
|---|---|
| GPIO 26 | Motor 1 — relay ON pulse |
| GPIO 27 | Motor 1 — relay OFF pulse |
| GPIO 25 | Motor 2 — relay toggle |
| GPIO 0 | Reset button (INPUT_PULLUP) |

---

## Getting Started

### Prerequisites

- Flutter SDK `^3.11.0`
- Android SDK (min API 21) or iOS 12+
- ESP32 flashed with compatible firmware

### Run

```bash
flutter pub get
flutter run
```

### Regenerate launcher icon (after replacing `assets/images/launcher_icon.png`)

```bash
flutter pub run flutter_launcher_icons
flutter run
```

---

## Building for Release

```bash
# Android APK
flutter build apk --release

# Android App Bundle (Play Store)
flutter build appbundle --release

# iOS
flutter build ios --release
```

> For production deployment, replace `broker.hivemq.com` in `esp32_service.dart` and the ESP32 firmware with a private MQTT broker and enable TLS on port 8883.
