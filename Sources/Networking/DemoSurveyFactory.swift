import Foundation

// MARK: - Demo / Mock Probe & Sample Survey Generator (for Simulator & Offline Showcase)

enum DemoSurveyFactory {
    struct SimulatedAP {
        let bssid: String
        let ssid: String
        let x: Double
        let z: Double
        let freqMhz: Int
        let band: String
        let channel: Int
        let widthMhz: Int
        let wifiGen: String
        let security: String
        let vendor: String
        let apModel: String
        let apName: String?
        let streams: String
        let maxPhyMbps: Int
        let txPowerDbm: Int
        let qbssUtilBase: Double
        let qbssStationsBase: Int
        let cciCount: Int
        let bssColor: Int
        let warnings: [String]
    }

    static let simulatedAPs: [SimulatedAP] = [
        SimulatedAP(
            bssid: "dc:a6:32:10:01:5a", ssid: "Corp-WiFi6E", x: 1.5, z: 1.4,
            freqMhz: 5180, band: "5GHz", channel: 36, widthMhz: 80, wifiGen: "Wi-Fi 6",
            security: "WPA3-Enterprise", vendor: "Cisco Systems", apModel: "Catalyst 9136I",
            apName: "AP-FL3-CONF", streams: "4x4:4", maxPhyMbps: 4804, txPowerDbm: 17,
            qbssUtilBase: 22.0, qbssStationsBase: 14, cciCount: 1, bssColor: 19, warnings: []
        ),
        SimulatedAP(
            bssid: "dc:a6:32:10:01:6a", ssid: "Corp-WiFi6E", x: 1.5, z: 1.4,
            freqMhz: 6135, band: "6GHz", channel: 37, widthMhz: 160, wifiGen: "Wi-Fi 6E",
            security: "WPA3-Enterprise", vendor: "Cisco Systems", apModel: "Catalyst 9136I",
            apName: "AP-FL3-CONF", streams: "4x4:4", maxPhyMbps: 4804, txPowerDbm: 15,
            qbssUtilBase: 9.0, qbssStationsBase: 6, cciCount: 0, bssColor: 24, warnings: []
        ),
        SimulatedAP(
            bssid: "dc:a6:32:10:02:5b", ssid: "Corp-WiFi6E", x: 8.4, z: 4.8,
            freqMhz: 5500, band: "5GHz", channel: 100, widthMhz: 80, wifiGen: "Wi-Fi 6",
            security: "WPA3-Enterprise", vendor: "Cisco Systems", apModel: "Catalyst 9136I",
            apName: "AP-FL3-OPEN", streams: "4x4:4", maxPhyMbps: 4804, txPowerDbm: 17,
            qbssUtilBase: 38.0, qbssStationsBase: 21, cciCount: 2, bssColor: 31, warnings: []
        ),
        SimulatedAP(
            bssid: "74:ac:b9:44:22:01", ssid: "Guest-Lobby", x: 5.0, z: 0.8,
            freqMhz: 2412, band: "2.4GHz", channel: 1, widthMhz: 20, wifiGen: "Wi-Fi 6",
            security: "WPA2-Personal", vendor: "Ubiquiti", apModel: "U6-Pro",
            apName: "AP-LOBBY-01", streams: "2x2:2", maxPhyMbps: 573, txPowerDbm: 14,
            qbssUtilBase: 54.0, qbssStationsBase: 11, cciCount: 3, bssColor: 7,
            warnings: ["High 2.4GHz CCI (3 co-channel APs)", "Legacy 1/2 Mbps basic rates enabled"]
        ),
        SimulatedAP(
            bssid: "20:4c:03:aa:77:11", ssid: "IoT-Sensors", x: 9.2, z: 1.5,
            freqMhz: 2437, band: "2.4GHz", channel: 6, widthMhz: 40, wifiGen: "Wi-Fi 4",
            security: "WPA2-Personal", vendor: "Aruba Networks", apModel: "AP-515",
            apName: "AP-IOT-EAST", streams: "2x2:2", maxPhyMbps: 300, txPowerDbm: 18,
            qbssUtilBase: 61.0, qbssStationsBase: 19, cciCount: 4, bssColor: 0,
            warnings: ["40 MHz wide channel on 2.4GHz causes ACI overlap", "High QBSS Channel Util (>50%)"]
        ),
        SimulatedAP(
            bssid: "f0:9f:c2:88:11:90", ssid: "Neighbor-Office", x: -2.0, z: 6.2,
            freqMhz: 5180, band: "5GHz", channel: 36, widthMhz: 40, wifiGen: "Wi-Fi 5",
            security: "WPA2-Personal", vendor: "TP-Link", apModel: "EAP670",
            apName: nil, streams: "2x2:2", maxPhyMbps: 866, txPowerDbm: 20,
            qbssUtilBase: 41.0, qbssStationsBase: 8, cciCount: 2, bssColor: 0,
            warnings: ["Co-channel overlap with Corp-WiFi6E on Ch 36"]
        ),
        SimulatedAP(
            bssid: "a4:2b:8c:33:09:44", ssid: "Printer-Setup", x: 7.2, z: 6.1,
            freqMhz: 2462, band: "2.4GHz", channel: 11, widthMhz: 20, wifiGen: "Wi-Fi 4",
            security: "Open", vendor: "HP Inc.", apModel: "LaserJet Pro",
            apName: nil, streams: "1x1:1", maxPhyMbps: 72, txPowerDbm: 12,
            qbssUtilBase: 18.0, qbssStationsBase: 2, cciCount: 1, bssColor: 0,
            warnings: ["Open / Unencrypted SSID detected"]
        )
    ]

    static func generateLiveScan(scanId: Int, atX x: Double = 4.5, z: Double = 3.2) -> ScanPayload {
        let now = Date()
        let iso = ISO8601DateFormatter().string(from: now)

        let mockClients: [ClientRecord] = [
            ClientRecord(mac: "a8:51:ab:12:34:56", vendor: "Apple, Inc.", isRandomMac: false, type: "Data STA", bssid: "dc:a6:32:10:01:5a", apSsid: "Corp-WiFi6E", channel: 36, rssiDbm: -52, frames: 184, retryPct: 4.2, ageSec: 1.2),
            ClientRecord(mac: "e2:4f:91:bc:77:09", vendor: "Private / Random", isRandomMac: true, type: "Data STA", bssid: "dc:a6:32:10:02:5b", apSsid: "Corp-WiFi6E", channel: 100, rssiDbm: -61, frames: 96, retryPct: 8.5, ageSec: 2.8),
            ClientRecord(mac: "3c:22:fb:90:11:aa", vendor: "Intel Corporate", isRandomMac: false, type: "Data STA", bssid: "dc:a6:32:10:01:6a", apSsid: "Corp-WiFi6E", channel: 37, rssiDbm: -48, frames: 240, retryPct: 2.1, ageSec: 0.6),
            ClientRecord(mac: "24:6f:28:55:aa:10", vendor: "Espressif Inc.", isRandomMac: false, type: "Data STA", bssid: "20:4c:03:aa:77:11", apSsid: "IoT-Sensors", channel: 6, rssiDbm: -71, frames: 42, retryPct: 19.4, ageSec: 4.1),
            ClientRecord(mac: "da:11:77:20:ff:33", vendor: "Private / Random", isRandomMac: true, type: "Probe Req", bssid: nil, apSsid: nil, channel: 1, rssiDbm: -66, frames: 11, retryPct: 0.0, ageSec: 3.0)
        ]

        let aps: [APRecord] = simulatedAPs.map { ap in
            let dist = max(0.6, hypot(x - ap.x, z - ap.z))
            let pathLossExp = ap.band == "6GHz" ? 28.0 : (ap.band == "5GHz" ? 25.0 : 21.0)
            let baseAt1m = ap.band == "6GHz" ? -42.0 : -39.0
            let jitter = Double.random(in: -1.8...1.8)
            let rssi = max(-92.0, min(-32.0, baseAt1m - pathLossExp * log10(dist) + jitter))
            let util = max(2.0, min(95.0, ap.qbssUtilBase + Double.random(in: -3.5...3.5)))
            let matchingClients = mockClients.filter { $0.bssid == ap.bssid }
            let retry = matchingClients.isEmpty
                ? (ap.band == "2.4GHz" ? Double.random(in: 12...24) : Double.random(in: 2...9))
                : (matchingClients.compactMap { $0.retryPct }.reduce(0, +) / Double(matchingClients.count))

            return APRecord(
                bssid: ap.bssid,
                ssid: ap.ssid,
                rssiDbm: (rssi * 10).rounded() / 10,
                freqMhz: ap.freqMhz,
                band: ap.band,
                channel: ap.channel,
                widthMhz: ap.widthMhz,
                wifiGen: ap.wifiGen,
                security: ap.security,
                vendor: ap.vendor,
                apModel: ap.apModel,
                apName: ap.apName,
                streams: ap.streams,
                maxPhyMbps: ap.maxPhyMbps,
                dot11k: ap.ssid == "Corp-WiFi6E",
                dot11v: ap.ssid == "Corp-WiFi6E",
                dot11r: ap.ssid == "Corp-WiFi6E",
                pmf: ap.security.contains("WPA3") ? "Required" : (ap.security == "Open" ? "Disabled" : "Optional"),
                ciphers: ap.security == "Open" ? [] : ["CCMP-128"],
                akm: ap.security.contains("Enterprise") ? ["802.1X-SHA256", "FT-802.1X"] : (ap.security == "Open" ? [] : ["PSK"]),
                bssColor: ap.bssColor,
                country: "TH",
                beaconIntervalMs: 102.4,
                dtimPeriod: 2,
                basicRatesMbps: ap.band == "2.4GHz" ? [1, 2, 5.5, 11] : [12, 24],
                minBasicRateMbps: ap.band == "2.4GHz" ? 1.0 : 12.0,
                legacyRatesEnabled: ap.band == "2.4GHz",
                physicalApId: ap.apName ?? ap.bssid,
                coBssidCount: ap.ssid == "Corp-WiFi6E" ? 2 : 1,
                siblingSsids: ap.ssid == "Corp-WiFi6E" ? ["Corp-WiFi6E", "Corp-Voice"] : [ap.ssid],
                cciCount: ap.cciCount,
                aciWarning: ap.band == "2.4GHz" && ap.widthMhz > 20,
                healthWarnings: ap.warnings,
                qbssUtilPct: (util * 10).rounded() / 10,
                qbssStations: ap.qbssStationsBase,
                txPowerDbm: ap.txPowerDbm,
                lastSeenMs: 120,
                monFrames: Int.random(in: 35...260),
                monRetryPct: (retry * 10).rounded() / 10,
                monClients: matchingClients.count,
                monClientList: matchingClients,
                monNoiseDbm: -94.0,
                monSnrDb: max(4.0, rssi + 94.0)
            )
        }.sorted { $0.rssiDbm > $1.rssiDbm }

        var bandCounts: [String: Int] = [:]
        for ap in aps { bandCounts[ap.band, default: 0] += 1 }
        let qbssTotal = aps.compactMap { $0.qbssStations }.reduce(0, +)

        let monitor = MonitorSummary(
            active: true,
            interface: "wlan1 (demo)",
            currentChannel: [1, 6, 36, 100, 37][scanId % 5],
            totalFrames10s: Int.random(in: 420...980),
            retryPct10s: Double.random(in: 4.5...11.2),
            dataClients10s: 4,
            probeClients10s: 1,
            uniqueClients10s: mockClients.count,
            probeRequests10s: Int.random(in: 8...24),
            clients: mockClients
        )

        return ScanPayload(
            scanId: scanId,
            hostname: "wlanpi-demo-r4",
            interface: "wlan0 (demo)",
            timestampUnix: now.timeIntervalSince1970,
            timestampIso: iso,
            scanDurationMs: 240,
            apCount: aps.count,
            qbssTotalClients: qbssTotal,
            bandCounts: bandCounts,
            strongestRssi: aps.first?.rssiDbm,
            monitor: monitor,
            aps: aps
        )
    }

    static func sampleOfficeSurvey() -> SurveySessionExport {
        // 10m x 6.5m modern office with conference room partition
        let walls: [RoomSurfaceSegment] = [
            // Perimeter
            RoomSurfaceSegment(kind: "wall", x1: 0, z1: 0, x2: 10, z2: 0, yMin: -1.2, yMax: 1.6),
            RoomSurfaceSegment(kind: "wall", x1: 10, z1: 0, x2: 10, z2: 6.5, yMin: -1.2, yMax: 1.6),
            RoomSurfaceSegment(kind: "wall", x1: 10, z1: 6.5, x2: 0, z2: 6.5, yMin: -1.2, yMax: 1.6),
            RoomSurfaceSegment(kind: "wall", x1: 0, z1: 6.5, x2: 0, z2: 0, yMin: -1.2, yMax: 1.6),
            // Inner conference partition wall with doorway gap
            RoomSurfaceSegment(kind: "wall", x1: 4.2, z1: 0, x2: 4.2, z2: 2.6, yMin: -1.2, yMax: 1.6),
            RoomSurfaceSegment(kind: "wall", x1: 4.2, z1: 3.8, x2: 4.2, z2: 6.5, yMin: -1.2, yMax: 1.6)
        ]
        let doors: [RoomSurfaceSegment] = [
            RoomSurfaceSegment(kind: "door", x1: 4.2, z1: 2.6, x2: 4.2, z2: 3.8, yMin: -1.2, yMax: 1.0),
            RoomSurfaceSegment(kind: "door", x1: 5.2, z1: 0.0, x2: 6.4, z2: 0.0, yMin: -1.2, yMax: 1.0)
        ]
        let windows: [RoomSurfaceSegment] = [
            RoomSurfaceSegment(kind: "window", x1: 1.2, z1: 6.5, x2: 3.4, z2: 6.5, yMin: -0.2, yMax: 1.2),
            RoomSurfaceSegment(kind: "window", x1: 5.5, z1: 6.5, x2: 8.8, z2: 6.5, yMin: -0.2, yMax: 1.2)
        ]
        let floorPoly: [RoomPoint2D] = [
            RoomPoint2D(x: 0, z: 0),
            RoomPoint2D(x: 10, z: 0),
            RoomPoint2D(x: 10, z: 6.5),
            RoomPoint2D(x: 0, z: 6.5)
        ]
        let objects: [RoomObjectBox] = [
            // Conference table
            RoomObjectBox(
                category: "table", cx: 2.1, cy: -0.8, cz: 3.2,
                width: 2.2, height: 0.75, depth: 1.1, yawRad: 0,
                corners: [
                    RoomPoint2D(x: 1.0, z: 2.65), RoomPoint2D(x: 3.2, z: 2.65),
                    RoomPoint2D(x: 3.2, z: 3.75), RoomPoint2D(x: 1.0, z: 3.75)
                ]
            ),
            // Open office desk bank
            RoomObjectBox(
                category: "table", cx: 7.4, cy: -0.8, cz: 3.2,
                width: 3.0, height: 0.75, depth: 1.3, yawRad: 0,
                corners: [
                    RoomPoint2D(x: 5.9, z: 2.55), RoomPoint2D(x: 8.9, z: 2.55),
                    RoomPoint2D(x: 8.9, z: 3.85), RoomPoint2D(x: 5.9, z: 3.85)
                ]
            )
        ]

        // Realistic serpentine survey walk path across both rooms (18 points)
        let walkCoords: [(Double, Double)] = [
            (0.9, 1.0), (2.2, 1.0), (3.4, 1.2),
            (3.4, 2.5), (1.2, 2.2), (0.9, 4.5),
            (2.2, 5.4), (3.5, 5.2), (4.2, 3.2),
            (5.3, 1.2), (7.2, 1.2), (9.0, 1.3),
            (9.1, 2.8), (9.0, 5.0), (7.4, 5.3),
            (5.6, 5.2), (5.5, 3.2), (7.0, 4.3)
        ]

        let baseTs = Date().timeIntervalSince1970 - 180
        var points: [SurveyPoint] = []
        for (idx, (wx, wz)) in walkCoords.enumerated() {
            let scan = generateLiveScan(scanId: 100 + idx, atX: wx, z: wz)
            let heading: Double
            if idx + 1 < walkCoords.count {
                let next = walkCoords[idx + 1]
                heading = atan2(next.1 - wz, next.0 - wx)
            } else {
                heading = 0
            }
            points.append(SurveyPoint(
                id: UUID(),
                timestamp: baseTs + Double(idx) * 6.0,
                x: wx, y: 0.2, z: wz,
                headingRad: heading,
                scanId: scan.scanId,
                aps: scan.aps
            ))
        }

        return SurveySessionExport(
            id: "demo_office_fl3",
            name: "Demo Office Floor 3 (Sample)",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            points: points,
            walls: walls,
            doors: doors,
            windows: windows,
            floors: [floorPoly],
            objects: objects,
            floorY: -1.2,
            mapRotationDeg: 0.0,
            calibration: nil,
            floorplanJpegBase64: nil
        )
    }
}
