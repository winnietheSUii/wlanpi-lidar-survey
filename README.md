# WiFi LiDAR Survey (`wlanpi-lidar-survey`)

An iOS / iPadOS (iOS 17+) Wi-Fi RF Site Survey application that pairs **Apple LiDAR + RoomPlan + ARKit** with a **WLAN Pi R4** dual-radio RF survey probe to produce real-time 2D Cisco Prime-style thermal heatmaps, 3D Cisco DNA-style volumetric coverage views, channel spectrum analysis, and executive PDF reports.

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

## Project Structure

```text
Sources/
├── App/
│   └── WlanPiLidarSurveyApp.swift      # @main entry point
├── Models/
│   └── SurveyModels.swift              # WLAN Pi JSON contract, RoomPlan geometry, Calibration math
├── Networking/
│   ├── WlanPiClient.swift              # HTTP polling, Bonjour (_wifisurvey._tcp), Pi sync, Demo Mode
│   └── DemoSurveyFactory.swift         # Synthetic multi-band probe & sample office survey
├── Store/
│   └── SurveyStore.swift               # App state, RoomPlan processing, Auto-Walk, AP centroid estimator
├── RoomPlan/
│   └── RoomPlanCaptureContainer.swift  # RoomCaptureView wrapper + AR pose timer + Simulator fallback
├── Rendering/
│   ├── CiscoColors.swift               # Cisco Prime thermal color stops & polygon math
│   └── CiscoHeatmapRenderer.swift      # Thread-safe IDW contour generator & async cache controller
├── Export/
│   └── SurveyReportExporter.swift      # Multi-page Executive PDF report generator
└── Views/
    ├── ContentView.swift               # Main split/2D/3D/RoomScan dashboard
    ├── CiscoFloorplanView.swift        # Interactive 2D CAD & calibrated floorplan canvas
    ├── RoomPlan3DSceneView.swift       # Interactive 3D SceneKit room + domes + thermal sheet
    └── Sheets/
        ├── APInspectorSheets.swift     # AP list, deep inspector & client vendor list
        ├── ChannelSpectrumView.swift   # 2.4 / 5 / 6 GHz channel width & CCI spectrum chart
        ├── FloorplanCalibrationSheet.swift
        ├── SavedMapsSheet.swift
        ├── SettingsSheet.swift
        └── SurveyPointInspectorSheet.swift
```

---

## WLAN Pi R4 Probe Setup & API Contract

Connect your iPad/iPhone to the WLAN Pi over any supported transport (built-in presets + Bonjour `_wifisurvey._tcp` discovery):

| Transport | Default Preset Host |
| :--- | :--- |
| Bluetooth PAN (Wireless) | `10.43.0.1:8090` |
| mDNS Auto | `wlanpi-9a0.local:8090` |
| iPad LAN Direct | `10.42.0.1:8090` |
| USB-C OTG | `198.18.42.1:8090` |
| PC ICS LAN | `192.168.137.169:8090` |

### HTTP Endpoints Expected on Port `8090`

- `GET /api/health` → `200 OK` (probe discovery / health check)
- `GET /api/scan` → JSON `ScanPayload` (`scan_id`, `hostname`, `interface`, `timestamp_unix`, `timestamp_iso`, `scan_duration_ms`, `ap_count`, `qbss_total_clients`, `band_counts`, `strongest_rssi`, `monitor`, `aps[]`)
- `GET /api/surveys` → `{ "surveys": [ { "id", "name", "created_at", "point_count", "wall_count" } ] }`
- `POST /api/surveys` → Stores a `SurveySessionExport` JSON payload (compacted automatically for fast Bluetooth PAN upload)
- `GET /api/surveys/{id}` → Returns full `SurveySessionExport` JSON
- `DELETE /api/surveys/{id}` → Deletes a saved survey on the Pi

---

## Building the App

### Prerequisites
- Xcode 15+ (iOS 17.0+ deployment target)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`xcodegen`)
- Physical LiDAR iPad Pro / iPhone Pro for live RoomPlan scanning (or Xcode Simulator using **Settings → Demo / Mock WLAN Pi Probe → Load Sample Office Survey**)

### Generate Project & Build
```bash
xcodegen generate
open wlanpi-lidar-survey.xcodeproj
```

Or build from CLI for Simulator:
```bash
xcodebuild -project wlanpi-lidar-survey.xcodeproj -scheme wlanpi-lidar-survey -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```
