# wlanpi-lidar-survey

**wlanpi-lidar-survey** combines a **WLAN Pi R4** dual-radio Wi-Fi survey backend and web dashboard with an **iOS / iPadOS (iOS 17+)** app using **Apple LiDAR + RoomPlan + ARKit** to produce real-time 2D Cisco Prime-style thermal heatmaps, 3D Cisco DNA-style volumetric coverage views, channel spectrum analysis, and executive PDF reports.

---

## Project Layout

| Path | Contents |
| --- | --- |
| `ios/` | Modular SwiftUI iOS/iPadOS app (`Sources/`), `Info.plist`, `project.yml`, and `wlanpi-lidar-survey.xcodeproj` |
| `wlanpi/` | Zero-dependency Python 3 WLAN Pi RF survey server (`server.py`) and web dashboard (`dashboard.html`) |

```text
wlanpi-lidar-survey/
├── ios/
│   ├── Info.plist
│   ├── project.yml
│   ├── wlanpi-lidar-survey.xcodeproj/
│   └── Sources/
│       ├── App/
│       │   └── WlanPiLidarSurveyApp.swift      # @main entry point
│       ├── Models/
│       │   └── SurveyModels.swift              # WLAN Pi JSON contract, RoomPlan geometry, Calibration math
│       ├── Networking/
│       │   ├── WlanPiClient.swift              # HTTP polling, Bonjour (_wifisurvey._tcp), Pi sync, Demo Mode
│       │   └── DemoSurveyFactory.swift         # Synthetic multi-band probe & sample office survey
│       ├── Store/
│       │   └── SurveyStore.swift               # App state, RoomPlan processing, Auto-Walk, AP centroid estimator
│       ├── RoomPlan/
│       │   └── RoomPlanCaptureContainer.swift  # RoomCaptureView wrapper + AR pose timer + Simulator fallback
│       ├── Rendering/
│       │   ├── CiscoColors.swift               # Cisco Prime thermal color stops & polygon math
│       │   └── CiscoHeatmapRenderer.swift      # Thread-safe IDW contour generator & async cache controller
│       ├── Export/
│       │   └── SurveyReportExporter.swift      # Multi-page Executive PDF report generator
│       └── Views/
│           ├── ContentView.swift               # Main split/2D/3D/RoomScan dashboard
│           ├── CiscoFloorplanView.swift        # Interactive 2D CAD & calibrated floorplan canvas
│           ├── RoomPlan3DSceneView.swift       # Interactive 3D SceneKit room + domes + thermal sheet
│           └── Sheets/
│               ├── APInspectorSheets.swift     # AP list, deep inspector & client vendor list
│               ├── ChannelSpectrumView.swift   # 2.4 / 5 / 6 GHz channel width & CCI spectrum chart
│               ├── FloorplanCalibrationSheet.swift
│               ├── SavedMapsSheet.swift
│               ├── SettingsSheet.swift
│               └── SurveyPointInspectorSheet.swift
└── wlanpi/
    ├── server.py                               # Dual-radio iw scan + monitor mode sniffer + REST/SSE API
    └── dashboard.html                          # Live web analyzer & saved survey viewer
```

---

## Features

- **Apple RoomPlan + ARKit Tracking**: Automatically maps architectural walls, doors, windows, floor polygons, and furniture while tracking 6DoF surveyor pose (`x, y, z, yaw`) at ~12.5 Hz.
- **2D Cisco Prime Thermal Heatmap**:
  - Async off-thread bitmap caching (`HeatmapCacheController`) for smooth 60/120fps pan, zoom, and live walking.
  - Works on auto-generated RoomPlan CAD **or** an imported floorplan image aligned via 2-point walk calibration + drift re-anchoring.
  - Supports **Primary RSSI**, **Secondary RSSI**, **AP Overlap**, **QBSS Channel Util %**, and **Monitor Mode Retry %**.
  - Tap any measured point on the map to inspect heard APs or delete individual points, plus 1-tap **Undo** for the last sample.
- **3D SceneKit Room Visualizer**: Switch between **Cisco DNA 3D Volumetric Coverage Domes + Health Score Pins** and an **Elevated 3D Thermal Surface**.
- **RSSI-Weighted AP Localization**: Estimates physical AP coordinates via linear power-weighted centroids over the strongest observations per BSSID.
- **RF, Channel Spectrum & Client Inspector**:
  - Deep AP beacon inspection (OUI vendor, Cisco Aironet/WPS model, spatial streams, Max PHY, 802.11k/v/r, PMF, HE BSS Color, QBSS load, basic rates, CCI/ACI warnings).
  - Visual **2.4 / 5 / 6 GHz Channel Overlap & Width Spectrum** chart with least-congested channel recommendation.
  - Live client visibility combining **QBSS station counts** and optional **USB Monitor Mode** frame sniffing.
- **Auto-Walk with Stale-Scan Guard**: Distance-triggered sampling (`0.5m – 2.0m`) that waits for a fresh `scan_id` from the WLAN Pi to prevent duplicate RF readings when walking quickly.
- **Offline Storage, WLAN Pi Sync & PDF Reporting**:
  - Local offline JSON map library + bidirectional sync with WLAN Pi (`/api/surveys`).
  - **Executive PDF Report Export** (`UIGraphicsPDFRenderer`) containing the 2D heatmap, coverage pass/fail KPIs, AP inventory table, and RF health warnings.
- **Demo / Mock Probe Mode**: Built-in simulated WLAN Pi feed + 18-point sample office RoomPlan survey for testing in Xcode Simulator without physical hardware.

---

## Run on a WLAN Pi

Install `iw` and Python 3.10 or later on the WLAN Pi. From the repository root, start the server with the privileges needed for wireless scanning:

```sh
sudo python3 wlanpi/server.py
```

Open `http://<wlan-pi-address>:8090/` on the same network to view the live web dashboard.

### Environment Variables

| Variable | Default | Description |
| --- | --- | --- |
| `SURVEY_PORT` | `8090` | HTTP server listen port |
| `SURVEY_SCAN_IFACE` | *(auto-detect)* | Wireless interface used for `iw scan -u` |
| `SURVEY_MON_IFACE` | *(auto-detect)* | Optional secondary USB monitor-mode interface |
| `SURVEY_INTERVAL` | `0.5` | Scan loop interval in seconds |
| `SURVEY_DATA_DIR` | `/var/lib/wifi-survey/sessions` | Directory for persisted survey JSON sessions |

### WLAN Pi Transport Presets & HTTP Endpoints (Port `8090`)

| Transport | Default Preset Host |
| --- | --- |
| Bluetooth PAN (Wireless) | `10.43.0.1:8090` |
| mDNS Auto | `wlanpi-9a0.local:8090` |
| iPad LAN Direct | `10.42.0.1:8090` |
| USB-C OTG | `198.18.42.1:8090` |
| PC ICS LAN | `192.168.137.169:8090` |

- `GET /` → Web dashboard (`wlanpi/dashboard.html`)
- `GET /api/health` → Probe status & active interfaces
- `GET /api/scan` → Latest `ScanPayload` JSON (`?fresh=1` waits for a fresh scan)
- `GET /api/monitor` → Live monitor-mode retry % & client frame stats
- `GET /api/stream` → Server-Sent Events (`text/event-stream`) live scan feed
- `GET /api/surveys` → List saved surveys on the WLAN Pi
- `POST /api/surveys` → Upload/save a `SurveySessionExport` JSON payload
- `GET /api/surveys/{id}` → Fetch a saved survey JSON payload
- `DELETE /api/surveys/{id}` → Delete a saved survey

---

## Build the iOS App

### Prerequisites
- Xcode 15+ (iOS 17.0+ deployment target)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`xcodegen`) — optional if opening the pre-generated `.xcodeproj`
- Physical LiDAR-equipped iPad Pro or iPhone Pro for live RoomPlan scanning (or Xcode Simulator using **Settings → Demo / Mock WLAN Pi Probe → Load Sample Office Survey**)

### Generate Project & Build

```sh
cd ios
xcodegen generate
open wlanpi-lidar-survey.xcodeproj
```

Or build from CLI for the iOS Simulator:

```sh
xcodebuild -project ios/wlanpi-lidar-survey.xcodeproj \
  -scheme wlanpi-lidar-survey \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  build
```
