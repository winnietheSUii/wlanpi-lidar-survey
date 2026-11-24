import Foundation
import SwiftUI
import PhotosUI
import RoomPlan
import ARKit
import SceneKit
import Network
import UIKit

// MARK: - Data Models (WLAN Pi Hybrid Dual-Radio JSON Contract)

struct ClientRecord: Codable, Identifiable, Hashable {
    var id: String { mac }
    let mac: String
    let vendor: String
    let isRandomMac: Bool?
    let type: String?
    let bssid: String?
    let apSsid: String?
    let channel: Int?
    let rssiDbm: Double?
    let frames: Int?
    let retryPct: Double?
    let ageSec: Double?

    enum CodingKeys: String, CodingKey {
        case mac, vendor, type, bssid, channel, frames
        case isRandomMac = "is_random_mac"
        case apSsid = "ap_ssid"
        case rssiDbm = "rssi_dbm"
        case retryPct = "retry_pct"
        case ageSec = "age_sec"
    }
}

struct APRecord: Codable, Identifiable, Hashable {
    var id: String { bssid }
    let bssid: String
    let ssid: String
    let rssiDbm: Double
    let freqMhz: Int
    let band: String
    let channel: Int
    let widthMhz: Int
    let wifiGen: String
    let security: String
    let vendor: String?
    let apModel: String?
    let apName: String?
    let streams: String?
    let maxPhyMbps: Int?
    let dot11k: Bool?
    let dot11v: Bool?
    let dot11r: Bool?
    let pmf: String?
    let ciphers: [String]?
    let akm: [String]?
    let bssColor: Int?
    let country: String?
    let beaconIntervalMs: Double?
    let dtimPeriod: Int?
    let basicRatesMbps: [Double]?
    let minBasicRateMbps: Double?
    let legacyRatesEnabled: Bool?
    let physicalApId: String?
    let coBssidCount: Int?
    let siblingSsids: [String]?
    let cciCount: Int?
    let aciWarning: Bool?
    let healthWarnings: [String]?
    let qbssUtilPct: Double?
    let qbssStations: Int?
    let txPowerDbm: Int?
    let lastSeenMs: Int?
    let monFrames: Int?
    let monRetryPct: Double?
    let monClients: Int?
    let monClientList: [ClientRecord]?
    let monNoiseDbm: Double?
    let monSnrDb: Double?

    enum CodingKeys: String, CodingKey {
        case bssid, ssid, band, channel, security, vendor, streams
        case dot11k, dot11v, dot11r, pmf, ciphers, akm, country
        case rssiDbm = "rssi_dbm"
        case freqMhz = "freq_mhz"
        case widthMhz = "width_mhz"
        case wifiGen = "wifi_gen"
        case apModel = "ap_model"
        case apName = "ap_name"
        case maxPhyMbps = "max_phy_mbps"
        case bssColor = "bss_color"
        case beaconIntervalMs = "beacon_interval_ms"
        case dtimPeriod = "dtim_period"
        case basicRatesMbps = "basic_rates_mbps"
        case minBasicRateMbps = "min_basic_rate_mbps"
        case legacyRatesEnabled = "legacy_rates_enabled"
        case physicalApId = "physical_ap_id"
        case coBssidCount = "co_bssid_count"
        case siblingSsids = "sibling_ssids"
        case cciCount = "cci_count"
        case aciWarning = "aci_warning"
        case healthWarnings = "health_warnings"
        case qbssUtilPct = "qbss_util_pct"
        case qbssStations = "qbss_stations"
        case txPowerDbm = "tx_power_dbm"
        case lastSeenMs = "last_seen_ms"
        case monFrames = "mon_frames"
        case monRetryPct = "mon_retry_pct"
        case monClients = "mon_clients"
        case monClientList = "mon_client_list"
        case monNoiseDbm = "mon_noise_dbm"
        case monSnrDb = "mon_snr_db"
    }

    var displaySSID: String {
        ssid.isEmpty ? "<Hidden>" : ssid
    }

    var displayLabel: String {
        if let n = apName, !n.isEmpty { return n }
        if let v = vendor, !v.isEmpty, v != "Private / Unknown", v != "Unknown" {
            return "\(v) \(displaySSID)"
        }
        return displaySSID
    }

    var roamingTags: [String] {
        var out: [String] = []
        if dot11k == true { out.append("11k") }
        if dot11v == true { out.append("11v") }
        if dot11r == true { out.append("11r") }
        return out
    }

    /// Compact copy for survey export/sync (cuts payload size ~65% for fast Bluetooth PAN upload)
    func compactForSurvey() -> APRecord {
        APRecord(
            bssid: bssid,
            ssid: ssid,
            rssiDbm: rssiDbm.isFinite ? rssiDbm : -95.0,
            freqMhz: freqMhz,
            band: band,
            channel: channel,
            widthMhz: widthMhz,
            wifiGen: wifiGen,
            security: security,
            vendor: vendor,
            apModel: apModel,
            apName: apName,
            streams: streams,
            maxPhyMbps: maxPhyMbps,
            dot11k: dot11k,
            dot11v: dot11v,
            dot11r: dot11r,
            pmf: pmf,
            ciphers: nil,
            akm: nil,
            bssColor: bssColor,
            country: country,
            beaconIntervalMs: nil,
            dtimPeriod: nil,
            basicRatesMbps: nil,
            minBasicRateMbps: nil,
            legacyRatesEnabled: nil,
            physicalApId: nil,
            coBssidCount: nil,
            siblingSsids: nil,
            cciCount: nil,
            aciWarning: nil,
            healthWarnings: nil,
            qbssUtilPct: qbssUtilPct,
            qbssStations: qbssStations,
            txPowerDbm: txPowerDbm,
            lastSeenMs: nil,
            monFrames: monFrames,
            monRetryPct: monRetryPct,
            monClients: monClients,
            monClientList: nil,
            monNoiseDbm: nil,
            monSnrDb: nil
        )
    }
}

struct MonitorSummary: Codable {
    let active: Bool?
    let interface: String?
    let currentChannel: Int?
    let totalFrames10s: Int?
    let retryPct10s: Double?
    let dataClients10s: Int?
    let probeClients10s: Int?
    let uniqueClients10s: Int?
    let probeRequests10s: Int?
    let clients: [ClientRecord]?

    enum CodingKeys: String, CodingKey {
        case active, interface, clients
        case currentChannel = "current_channel"
        case totalFrames10s = "total_frames_10s"
        case retryPct10s = "retry_pct_10s"
        case dataClients10s = "data_clients_10s"
        case probeClients10s = "probe_clients_10s"
        case uniqueClients10s = "unique_clients_10s"
        case probeRequests10s = "probe_requests_10s"
    }
}

struct ScanPayload: Codable {
    let scanId: Int
    let hostname: String
    let interface: String
    let timestampUnix: Double
    let timestampIso: String
    let scanDurationMs: Int
    let apCount: Int
    let qbssTotalClients: Int?
    let bandCounts: [String: Int]
    let strongestRssi: Double?
    let monitor: MonitorSummary?
    let aps: [APRecord]

    enum CodingKeys: String, CodingKey {
        case hostname, interface, aps, monitor
        case scanId = "scan_id"
        case timestampUnix = "timestamp_unix"
        case timestampIso = "timestamp_iso"
        case scanDurationMs = "scan_duration_ms"
        case apCount = "ap_count"
        case qbssTotalClients = "qbss_total_clients"
        case bandCounts = "band_counts"
        case strongestRssi = "strongest_rssi"
    }
}

struct SurveyPoint: Codable, Identifiable {
    let id: UUID
    let timestamp: Double
    let x: Double
    let y: Double
    let z: Double
    let headingRad: Double
    let scanId: Int
    let aps: [APRecord]

    enum CodingKeys: String, CodingKey {
        case id, timestamp, x, y, z, aps
        case headingRad = "heading_rad"
        case scanId = "scan_id"
    }
}

// MARK: - RoomPlan Architectural Geometry Models

struct RoomSurfaceSegment: Codable, Hashable {
    let kind: String // "wall", "door", "window", "opening"
    let x1: Double
    let z1: Double
    let x2: Double
    let z2: Double
    let yMin: Double
    let yMax: Double

    enum CodingKeys: String, CodingKey {
        case kind, x1, z1, x2, z2
        case yMin = "y_min"
        case yMax = "y_max"
    }
}

struct RoomPoint2D: Codable, Hashable {
    let x: Double
    let z: Double
}

struct RoomObjectBox: Codable, Hashable {
    let category: String
    let cx: Double
    let cy: Double
    let cz: Double
    let width: Double
    let height: Double
    let depth: Double
    let yawRad: Double
    let corners: [RoomPoint2D]

    enum CodingKeys: String, CodingKey {
        case category, cx, cy, cz, width, height, depth, corners
        case yawRad = "yaw_rad"
    }
}

/// 2D Similarity Transform aligning RoomPlan/ARKit world (x, z) meters <-> Floorplan image UV (0..1)
struct FloorplanCalibration: Codable {
    var imgWidth: Double
    var imgHeight: Double
    var scalePxPerMeter: Double
    var rotationRad: Double
    var offsetPxX: Double
    var offsetPxY: Double
    var isCalibrated: Bool

    var pointAWorldX: Double?
    var pointAWorldZ: Double?
    var pointAImgU: Double?
    var pointAImgV: Double?

    var pointBWorldX: Double?
    var pointBWorldZ: Double?
    var pointBImgU: Double?
    var pointBImgV: Double?

    static let empty = FloorplanCalibration(
        imgWidth: 1000, imgHeight: 1000,
        scalePxPerMeter: 50, rotationRad: 0,
        offsetPxX: 500, offsetPxY: 500,
        isCalibrated: false
    )

    func worldToNormalized(_ wx: Double, _ wz: Double) -> CGPoint {
        let c = cos(rotationRad)
        let s = sin(rotationRad)
        let px = scalePxPerMeter * (c * wx - s * wz) + offsetPxX
        let py = scalePxPerMeter * (s * wx + c * wz) + offsetPxY
        return CGPoint(x: px / max(1, imgWidth), y: py / max(1, imgHeight))
    }

    func normalizedToWorld(_ u: Double, _ v: Double) -> (Double, Double) {
        let px = u * imgWidth - offsetPxX
        let py = v * imgHeight - offsetPxY
        let invScale = 1.0 / max(0.001, scalePxPerMeter)
        let c = cos(-rotationRad)
        let s = sin(-rotationRad)
        return (invScale * (c * px - s * py), invScale * (s * px + c * py))
    }

    mutating func solveFromTwoPoints() -> Bool {
        guard let ax = pointAWorldX, let az = pointAWorldZ,
              let au = pointAImgU, let av = pointAImgV,
              let bx = pointBWorldX, let bz = pointBWorldZ,
              let bu = pointBImgU, let bv = pointBImgV else { return false }
        let dwx = bx - ax, dwz = bz - az
        let worldDist = hypot(dwx, dwz)
        guard worldDist >= 0.5 else { return false }

        let dpx = (bu - au) * imgWidth
        let dpy = (bv - av) * imgHeight
        let pxDist = hypot(dpx, dpy)
        guard pxDist >= 10.0 else { return false }

        let s = pxDist / worldDist
        let rot = atan2(dpy, dpx) - atan2(dwz, dwx)
        let c = cos(rot), sn = sin(rot)
        scalePxPerMeter = s
        rotationRad = rot
        offsetPxX = au * imgWidth - s * (c * ax - sn * az)
        offsetPxY = av * imgHeight - s * (sn * ax + c * az)
        isCalibrated = true
        return true
    }

    mutating func reAnchor(worldX wx: Double, worldZ wz: Double, toImgU u: Double, imgV v: Double) {
        let c = cos(rotationRad), sn = sin(rotationRad)
        offsetPxX = u * imgWidth - scalePxPerMeter * (c * wx - sn * wz)
        offsetPxY = v * imgHeight - scalePxPerMeter * (sn * wx + c * wz)
        isCalibrated = true
    }
}

struct SurveySessionExport: Codable {
    let id: String
    let name: String
    let createdAt: String
    let points: [SurveyPoint]
    let walls: [RoomSurfaceSegment]
    let doors: [RoomSurfaceSegment]
    let windows: [RoomSurfaceSegment]
    let floors: [[RoomPoint2D]]
    let objects: [RoomObjectBox]
    let floorY: Double
    let mapRotationDeg: Double
    let calibration: FloorplanCalibration?
    let floorplanJpegBase64: String?

    enum CodingKeys: String, CodingKey {
        case id, name, points, walls, doors, windows, floors, objects, calibration
        case createdAt = "created_at"
        case floorY = "floor_y"
        case mapRotationDeg = "map_rotation_deg"
        case floorplanJpegBase64 = "floorplan_jpeg_b64"
    }
}

enum HeatmapMetric: String, CaseIterable, Identifiable {
    case primaryRSSI = "Primary RSSI"
    case secondaryRSSI = "Secondary RSSI"
    case apOverlap = "AP Overlap"
    case qbssUtil = "Channel Util %"
    case monRetry = "Retry % (Mon)"

    var id: String { rawValue }
}

enum BandFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case ghz24 = "2.4GHz"
    case ghz5 = "5GHz"
    case ghz6 = "6GHz"

    var id: String { rawValue }
}

enum ViewLayoutMode: String, CaseIterable, Identifiable {
    case split = "Split"
    case map = "2D Cisco"
    case view3D = "3D Room"
    case scan = "RoomScan"

    var id: String { rawValue }
}

enum CalibrationPickTarget {
    case none, pickA, pickB, reAnchor
}

// MARK: - Cisco Prime 2D Thermal & Cisco DNA 3D Color Engine

struct CiscoColors {
    /// Classic Cisco Prime Infrastructure Thermal Rainbow (-35 dBm Deep Red -> -90 dBm Indigo)
    private static let primeStops: [(dbm: Double, r: Double, g: Double, b: Double)] = [
        (-35, 0.50, 0.00, 0.00), // Deep Crimson
        (-42, 0.88, 0.14, 0.14), // Bright Red
        (-50, 0.98, 0.45, 0.09), // Vivid Orange
        (-57, 0.98, 0.80, 0.08), // Warm Yellow
        (-64, 0.09, 0.83, 0.31), // Emerald Green
        (-72, 0.02, 0.76, 0.91), // Bright Cyan
        (-81, 0.11, 0.31, 0.85), // Royal Blue
        (-90, 0.12, 0.04, 0.36)  // Deep Indigo
    ]

    static func primeThermalRGB(forRSSI dbm: Double) -> (r: Double, g: Double, b: Double) {
        if dbm >= primeStops[0].dbm { return (primeStops[0].r, primeStops[0].g, primeStops[0].b) }
        guard let last = primeStops.last else { return (0.12, 0.04, 0.36) }
        if dbm <= last.dbm { return (last.r, last.g, last.b) }
        for i in 0..<(primeStops.count - 1) {
            let a = primeStops[i], b = primeStops[i + 1]
            if dbm <= a.dbm && dbm >= b.dbm {
                let t = (a.dbm - dbm) / (a.dbm - b.dbm)
                return (a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
            }
        }
        return (last.r, last.g, last.b)
    }

    static func bandInfo(forRSSI dbm: Double) -> (r: Double, g: Double, b: Double, band: Int) {
        let (r, g, b) = primeThermalRGB(forRSSI: dbm)
        let band: Int
        if dbm >= -50 { band = 5 }
        else if dbm >= -60 { band = 4 }
        else if dbm >= -67 { band = 3 }
        else if dbm >= -72 { band = 2 }
        else if dbm >= -80 { band = 1 }
        else { band = 0 }
        return (r, g, b, band)
    }

    static func bandInfo(forBadPct pct: Double, maxPct: Double) -> (r: Double, g: Double, b: Double, band: Int) {
        let eq = -35.0 - max(0.0, min(1.0, pct / maxPct)) * 55.0
        return bandInfo(forRSSI: eq)
    }

    static func color(forRSSI dbm: Double) -> Color {
        if dbm >= -55 { return Color(red: 0.08, green: 0.72, blue: 0.32) }
        if dbm >= -67 { return Color(red: 0.52, green: 0.82, blue: 0.12) }
        if dbm >= -75 { return Color(red: 0.96, green: 0.72, blue: 0.08) }
        if dbm >= -82 { return Color(red: 0.98, green: 0.45, blue: 0.09) }
        return Color(red: 0.90, green: 0.22, blue: 0.21)
    }

    static func uiColor(forRSSI dbm: Double) -> UIColor {
        let c = primeThermalRGB(forRSSI: dbm)
        return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1.0)
    }

    static func pointInPolygon(x: Double, z: Double, poly: [RoomPoint2D]) -> Bool {
        guard poly.count >= 3 else { return false }
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let xi = poly[i].x, zi = poly[i].z
            let xj = poly[j].x, zj = poly[j].z
            let intersect = ((zi > z) != (zj > z)) && (x < (xj - xi) * (z - zi) / ((zj - zi) + 1e-12) + xi)
            if intersect { inside.toggle() }
            j = i
        }
        return inside
    }
}

// MARK: - WLAN Pi Probe Client + Bonjour Discovery

@MainActor
final class WlanPiClient: ObservableObject {
    @Published var hostAddress: String {
        didSet { UserDefaults.standard.set(hostAddress, forKey: "wlanpi_host") }
    }
    @Published var isConnected: Bool = false
    @Published var isAutoSearching: Bool = false
    @Published var latestScan: ScanPayload?
    @Published var lastError: String?
    @Published var latencyMs: Int = 0
    @Published var discoveredHosts: [String] = []
    @Published var syncStatus: String?
    @Published var isSyncing: Bool = false

    private var pollTask: Task<Void, Never>?
    private var browser: NWBrowser?
    private let session: URLSession
    private let syncSession: URLSession
    private var consecutiveFailures: Int = 0

    static let presetHosts: [(label: String, host: String)] = [
        ("Bluetooth PAN (Wireless)", "10.43.0.1:8090"),
        ("mDNS Auto", "wlanpi-9a0.local:8090"),
        ("iPad LAN Direct", "10.42.0.1:8090"),
        ("USB-C OTG", "198.18.42.1:8090"),
        ("PC ICS LAN", "192.168.137.169:8090")
    ]

    init() {
        let saved = UserDefaults.standard.string(forKey: "wlanpi_host") ?? "10.43.0.1:8090"
        self.hostAddress = saved
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5.0
        cfg.timeoutIntervalForResource = 8.0
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)

        // Dedicated long-timeout session for large survey uploads/downloads over Bluetooth PAN
        let syncCfg = URLSessionConfiguration.ephemeral
        syncCfg.timeoutIntervalForRequest = 30.0
        syncCfg.timeoutIntervalForResource = 90.0
        syncCfg.waitsForConnectivity = false
        self.syncSession = URLSession(configuration: syncCfg)

        startBonjourDiscovery()
        startPolling()
    }

    deinit {
        pollTask?.cancel()
        browser?.cancel()
    }

    private func normalizedBaseURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return "http://\(trimmed)"
    }

    func startBonjourDiscovery() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjour(type: "_wifisurvey._tcp", domain: nil), using: params)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            var found: [String] = []
            for res in results {
                if case let .service(name, _, _, _) = res.endpoint { found.append(name) }
            }
            Task { @MainActor [weak self] in self?.discoveredHosts = found }
        }
        b.start(queue: DispatchQueue.global(qos: .utility))
        self.browser = b
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                if !self.isSyncing {
                    await self.fetchScanOnce()
                }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
    }

    func fetchScanOnce() async {
        let urlStr = "\(normalizedBaseURL(hostAddress))/api/scan"
        guard let url = URL(string: urlStr) else {
            isConnected = false; lastError = "Invalid URL"; return
        }
        let t0 = Date()
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                consecutiveFailures += 1
                if consecutiveFailures >= 3 { isConnected = false }
                lastError = "HTTP error"
                return
            }
            let decoded = try JSONDecoder().decode(ScanPayload.self, from: data)
            latestScan = decoded
            consecutiveFailures = 0
            isConnected = true
            lastError = nil
            latencyMs = Int(Date().timeIntervalSince(t0) * 1000)
        } catch {
            consecutiveFailures += 1
            if consecutiveFailures >= 3 { isConnected = false }
            lastError = error.localizedDescription
        }
    }

    func autoFindProbe() {
        guard !isAutoSearching else { return }
        isAutoSearching = true
        syncStatus = "Searching WLAN Pi..."
        let candidates = ["10.43.0.1:8090", "wlanpi-9a0.local:8090", "10.42.0.1:8090", "198.18.42.1:8090", "192.168.137.169:8090", hostAddress]
        Task {
            for cand in candidates {
                guard let url = URL(string: "\(normalizedBaseURL(cand))/api/health") else { continue }
                do {
                    let (_, resp) = try await session.data(from: url)
                    if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                        self.hostAddress = cand
                        self.isAutoSearching = false
                        self.syncStatus = "Connected to \(cand)"
                        await self.fetchScanOnce()
                        return
                    }
                } catch { continue }
            }
            self.isAutoSearching = false
            self.syncStatus = "Probe not found"
        }
    }

    @discardableResult
    func uploadSurvey(_ payload: SurveySessionExport) async -> Bool {
        // Compact AP snapshots so Bluetooth PAN upload is ~3x smaller & faster
        let compactPoints = payload.points.map { pt in
            SurveyPoint(
                id: pt.id,
                timestamp: pt.timestamp.isFinite ? pt.timestamp : Date().timeIntervalSince1970,
                x: pt.x.isFinite ? pt.x : 0,
                y: pt.y.isFinite ? pt.y : 0,
                z: pt.z.isFinite ? pt.z : 0,
                headingRad: pt.headingRad.isFinite ? pt.headingRad : 0,
                scanId: pt.scanId,
                aps: pt.aps.map { $0.compactForSurvey() }
            )
        }
        let compactPayload = SurveySessionExport(
            id: payload.id,
            name: payload.name,
            createdAt: payload.createdAt,
            points: compactPoints,
            walls: payload.walls,
            doors: payload.doors,
            windows: payload.windows,
            floors: payload.floors,
            objects: payload.objects,
            floorY: payload.floorY.isFinite ? payload.floorY : -1.2,
            mapRotationDeg: payload.mapRotationDeg.isFinite ? payload.mapRotationDeg : 0,
            calibration: payload.calibration,
            floorplanJpegBase64: payload.floorplanJpegBase64
        )

        let bodyData: Data
        do {
            bodyData = try JSONEncoder().encode(compactPayload)
        } catch {
            syncStatus = "Encode error: \(error.localizedDescription)"
            return false
        }
        let sizeKB = max(1, bodyData.count / 1024)

        isSyncing = true
        defer { isSyncing = false }

        // Try current host first, then auto-fallback to Bluetooth PAN / LAN / OTG presets
        var candidates: [String] = [hostAddress]
        for fallback in ["10.43.0.1:8090", "wlanpi-9a0.local:8090", "10.42.0.1:8090", "198.18.42.1:8090", "192.168.137.169:8090"] {
            if !candidates.contains(fallback) { candidates.append(fallback) }
        }

        var lastErr = "Host unreachable"
        for (idx, host) in candidates.enumerated() {
            // Only try fallback hosts if primary failed, and quickly check /api/health on fallbacks first
            if idx > 0 {
                guard let hUrl = URL(string: "\(normalizedBaseURL(host))/api/health") else { continue }
                let okHealth = (try? await session.data(from: hUrl)).flatMap { ($0.1 as? HTTPURLResponse)?.statusCode == 200 } ?? false
                if !okHealth { continue }
            }
            guard let url = URL(string: "\(normalizedBaseURL(host))/api/surveys") else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 60.0
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = bodyData
            syncStatus = "Uploading \(sizeKB) KB to \(host)..."
            do {
                let (respData, resp) = try await syncSession.data(for: req)
                if let http = resp as? HTTPURLResponse {
                    if (200...299).contains(http.statusCode) {
                        if host != hostAddress { self.hostAddress = host }
                        self.isConnected = true
                        self.consecutiveFailures = 0
                        syncStatus = "Synced '\(payload.name)' (\(sizeKB) KB) to Pi!"
                        await fetchRemoteSurveys()
                        return true
                    } else {
                        let msg = String(data: respData, encoding: .utf8) ?? ""
                        lastErr = "HTTP \(http.statusCode) \(msg.prefix(60))"
                        // Server replied with HTTP error; don't retry other hosts
                        break
                    }
                }
            } catch {
                lastErr = error.localizedDescription
            }
        }
        syncStatus = "Sync failed (\(sizeKB) KB): \(lastErr)"
        return false
    }

    struct RemoteSurveyMeta: Codable, Identifiable {
        let id: String
        let name: String
        let createdAt: String?
        let pointCount: Int
        let wallCount: Int

        enum CodingKeys: String, CodingKey {
            case id, name
            case createdAt = "created_at"
            case pointCount = "point_count"
            case wallCount = "wall_count"
        }
    }

    private struct RemoteSurveyListWrapper: Codable {
        let surveys: [RemoteSurveyMeta]
    }

    @Published var remoteSurveys: [RemoteSurveyMeta] = []

    func fetchRemoteSurveys() async {
        guard let url = URL(string: "\(normalizedBaseURL(hostAddress))/api/surveys") else { return }
        do {
            let (data, resp) = try await syncSession.data(from: url)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                let decoded = try JSONDecoder().decode(RemoteSurveyListWrapper.self, from: data)
                self.remoteSurveys = decoded.surveys
            }
        } catch {}
    }

    func downloadRemoteSurvey(id: String) async -> SurveySessionExport? {
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(normalizedBaseURL(hostAddress))/api/surveys/\(encoded)") else { return nil }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let (data, resp) = try await syncSession.data(from: url)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                return try JSONDecoder().decode(SurveySessionExport.self, from: data)
            }
        } catch {}
        return nil
    }

    func deleteRemoteSurvey(id: String) async {
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(normalizedBaseURL(hostAddress))/api/surveys/\(encoded)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        _ = try? await syncSession.data(for: req)
        await fetchRemoteSurveys()
    }
}

struct SavedLocalMapMeta: Identifiable {
    let id: String
    let name: String
    let createdAt: String
    let pointCount: Int
    let wallCount: Int
    let fileURL: URL
}

// MARK: - RoomPlan + Cisco Survey Store

@MainActor
final class SurveyStore: ObservableObject {
    @Published var surveyName: String
    @Published var surveyId: String
    @Published var points: [SurveyPoint] = []

    // Clean RoomPlan Architectural Geometry (ZERO noisy dots, ZERO double walls!)
    @Published var walls: [RoomSurfaceSegment] = []
    @Published var doors: [RoomSurfaceSegment] = []
    @Published var windows: [RoomSurfaceSegment] = []
    @Published var openings: [RoomSurfaceSegment] = []
    @Published var floorPolygons: [[RoomPoint2D]] = []
    @Published var objects: [RoomObjectBox] = []
    @Published var floorY: Double = -1.2
    @Published var roomPlanInstruction: String = "Slowly pan camera along walls to map room"
    @Published var roomPlanSupported: Bool = RoomCaptureSession.isSupported
    @Published var roomScanFinalized: Bool = false

    // Calibration & Display
    @Published var floorplanImage: UIImage?
    @Published var calibration: FloorplanCalibration = .empty
    @Published var pickTarget: CalibrationPickTarget = .none
    @Published var showRoomWallsOnFloorplan: Bool = true
    @Published var mapRotationDeg: Double = 0.0
    @Published var hasAutoAligned: Bool = false
    @Published var ciscoLightTheme: Bool = true
    @Published var showEstimatedAPs: Bool = true
    @Published var clipHeatmapToRoom: Bool = false
    @Published var rssiCutoffDbm: Double = -85.0

    // 3D Viewer Options (Cisco DNA 3D Wireless Analyzer Domes!)
    @Published var useCisco3DDomes: Bool = true
    @Published var elevate3DHeatmap: Bool = true
    @Published var show3DWalls: Bool = true
    @Published var show3DObjects: Bool = true
    @Published var scene3DRevision: Int = 0

    // Live Camera Pose
    @Published var cameraX: Double = 0
    @Published var cameraY: Double = 0
    @Published var cameraZ: Double = 0
    @Published var cameraYaw: Double = 0
    @Published var trackingStatus: String = "Scanning Room..."

    // Survey Controls
    @Published var isAutoWalkEnabled: Bool = false
    @Published var autoWalkSpacingMeters: Double = 1.0
    @Published var selectedSSID: String = "ALL"
    @Published var selectedBand: BandFilter = .all
    @Published var selectedMetric: HeatmapMetric = .primaryRSSI

    // Saved Maps Library & Toast Feedback
    @Published var savedLocalMaps: [SavedLocalMapMeta] = []
    @Published var isViewingSavedMap: Bool = false
    @Published var toastMessage: String?

    var onRestartRoomScan: (() -> Void)?
    var onFinalizeRoomScan: (() -> Void)?

    private var lastAutoWalkPos: SIMD2<Double>?

    private var savedMapsDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("SavedMaps", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() {
        let ts = Int(Date().timeIntervalSince1970)
        self.surveyId = "survey_\(ts)"
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        self.surveyName = "Room Survey \(fmt.string(from: Date()))"
        refreshSavedMaps()
    }

    func showToast(_ msg: String) {
        self.toastMessage = msg
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if self.toastMessage == msg {
                self.toastMessage = nil
            }
        }
    }

    func refreshSavedMaps() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: savedMapsDir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else {
            savedLocalMaps = []
            return
        }
        let sorted = files.filter { $0.pathExtension == "json" }.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }
        var items: [SavedLocalMapMeta] = []
        let dec = JSONDecoder()
        for url in sorted {
            if let data = try? Data(contentsOf: url),
               let payload = try? dec.decode(SurveySessionExport.self, from: data) {
                items.append(SavedLocalMapMeta(
                    id: payload.id,
                    name: payload.name,
                    createdAt: payload.createdAt,
                    pointCount: payload.points.count,
                    wallCount: payload.walls.count,
                    fileURL: url
                ))
            }
        }
        self.savedLocalMaps = items
    }

    func saveCurrentMapLocally(customName: String? = nil) -> SurveySessionExport? {
        if let n = customName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            self.surveyName = n
        }
        let payload = buildExportPayload()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        guard let data = try? enc.encode(payload) else { return nil }
        let safeId = payload.id.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        let fileURL = savedMapsDir.appendingPathComponent("\(safeId.isEmpty ? "map" : safeId).json")
        do {
            try data.write(to: fileURL)
            refreshSavedMaps()
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            return payload
        } catch {
            return nil
        }
    }

    func loadSavedMap(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(SurveySessionExport.self, from: data) else {
            showToast("Failed to load saved map")
            return
        }
        applyLoadedSurvey(payload)
    }

    func applyLoadedSurvey(_ payload: SurveySessionExport) {
        self.isViewingSavedMap = true
        self.isAutoWalkEnabled = false
        self.surveyId = payload.id
        self.surveyName = payload.name
        self.points = payload.points
        self.walls = payload.walls
        self.doors = payload.doors
        self.windows = payload.windows
        self.openings = []
        self.floorPolygons = payload.floors
        self.objects = payload.objects
        self.floorY = payload.floorY
        self.mapRotationDeg = payload.mapRotationDeg
        self.hasAutoAligned = true
        if let cal = payload.calibration {
            self.calibration = cal
        } else {
            self.calibration = .empty
        }
        if let b64 = payload.floorplanJpegBase64, let d = Data(base64Encoded: b64), let img = UIImage(data: d) {
            self.floorplanImage = img
        } else {
            self.floorplanImage = nil
        }
        self.scene3DRevision += 1
        showToast("Loaded '\(payload.name)' (\(payload.points.count) pts)")
    }

    func deleteLocalMap(id: String) {
        if let meta = savedLocalMaps.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: meta.fileURL)
            refreshSavedMaps()
        }
    }

    func updateRoomPlan(_ room: CapturedRoom) {
        guard !isViewingSavedMap else { return }
        func extractSurfaces(_ list: [CapturedRoom.Surface], kind: String) -> [RoomSurfaceSegment] {
            list.compactMap { s in
                let halfW = s.dimensions.x * 0.5
                let halfH = s.dimensions.y * 0.5
                if halfW < 0.08 { return nil }
                let p1 = s.transform * SIMD4<Float>(-halfW, 0, 0, 1)
                let p2 = s.transform * SIMD4<Float>(+halfW, 0, 0, 1)
                let cy = Double(s.transform.columns.3.y)
                return RoomSurfaceSegment(
                    kind: kind,
                    x1: Double(p1.x), z1: Double(p1.z),
                    x2: Double(p2.x), z2: Double(p2.z),
                    yMin: cy - Double(halfH),
                    yMax: cy + Double(halfH)
                )
            }
        }

        let newWalls = extractSurfaces(room.walls, kind: "wall")
        let newDoors = extractSurfaces(room.doors, kind: "door")
        let newWindows = extractSurfaces(room.windows, kind: "window")
        let newOpenings = extractSurfaces(room.openings, kind: "opening")

        // Extract floor polygons & exact floorY
        var newFloors: [[RoomPoint2D]] = []
        var detectedFloorY: Double? = nil
        for fl in room.floors {
            let corners = fl.polygonCorners
            if corners.count >= 3 {
                var poly: [RoomPoint2D] = []
                for c in corners {
                    let wp = fl.transform * SIMD4<Float>(c.x, c.y, c.z, 1)
                    poly.append(RoomPoint2D(x: Double(wp.x), z: Double(wp.z)))
                    detectedFloorY = Double(wp.y)
                }
                newFloors.append(poly)
            } else if fl.dimensions.x > 0.3 && fl.dimensions.y > 0.3 {
                let hx = fl.dimensions.x * 0.5
                let hy = fl.dimensions.y * 0.5
                let localCorners = [
                    SIMD4<Float>(-hx, -hy, 0, 1), SIMD4<Float>(hx, -hy, 0, 1),
                    SIMD4<Float>(hx, hy, 0, 1), SIMD4<Float>(-hx, hy, 0, 1)
                ]
                var poly: [RoomPoint2D] = []
                for lc in localCorners {
                    let wp = fl.transform * lc
                    poly.append(RoomPoint2D(x: Double(wp.x), z: Double(wp.z)))
                    detectedFloorY = Double(wp.y)
                }
                newFloors.append(poly)
            }
        }
        if detectedFloorY == nil, let firstWall = newWalls.first {
            detectedFloorY = firstWall.yMin
        }

        // Extract architectural furniture objects cleanly
        let newObjects: [RoomObjectBox] = room.objects.map { obj in
            let hx = obj.dimensions.x * 0.5
            let hz = obj.dimensions.z * 0.5
            let localRect = [
                SIMD4<Float>(-hx, 0, -hz, 1), SIMD4<Float>(hx, 0, -hz, 1),
                SIMD4<Float>(hx, 0, hz, 1), SIMD4<Float>(-hx, 0, hz, 1)
            ]
            let corners = localRect.map { lc -> RoomPoint2D in
                let wp = obj.transform * lc
                return RoomPoint2D(x: Double(wp.x), z: Double(wp.z))
            }
            let pos = obj.transform.columns.3
            let yaw = atan2(Double(obj.transform.columns.0.z), Double(obj.transform.columns.0.x))
            return RoomObjectBox(
                category: "\(obj.category)",
                cx: Double(pos.x), cy: Double(pos.y), cz: Double(pos.z),
                width: Double(obj.dimensions.x),
                height: Double(obj.dimensions.y),
                depth: Double(obj.dimensions.z),
                yawRad: yaw,
                corners: corners
            )
        }

        self.walls = newWalls
        self.doors = newDoors
        self.windows = newWindows
        self.openings = newOpenings
        self.floorPolygons = newFloors
        self.objects = newObjects
        if let fy = detectedFloorY { self.floorY = fy }

        // Automatically snap the first dominant architectural wall straight horizontal!
        if !hasAutoAligned && !newWalls.isEmpty {
            autoStraightenWalls()
            hasAutoAligned = true
        }
        self.scene3DRevision += 1
    }

    func updatePose(x: Double, y: Double, z: Double, yaw: Double, tracking: String, latestScan: ScanPayload?) {
        cameraX = x; cameraY = y; cameraZ = z; cameraYaw = yaw; trackingStatus = tracking
        guard !isViewingSavedMap, isAutoWalkEnabled, let scan = latestScan, !scan.aps.isEmpty else { return }
        let cur = SIMD2<Double>(x, z)
        if let prev = lastAutoWalkPos {
            if simd_distance(cur, prev) >= autoWalkSpacingMeters {
                recordPoint(from: scan)
                lastAutoWalkPos = cur
            }
        } else {
            recordPoint(from: scan)
            lastAutoWalkPos = cur
        }
    }

    func autoStraightenWalls() {
        if let longest = walls.max(by: { hypot($0.x2 - $0.x1, $0.z2 - $0.z1) < hypot($1.x2 - $1.x1, $1.z2 - $1.z1) }) {
            let angDeg = atan2(longest.z2 - longest.z1, longest.x2 - longest.x1) * 180.0 / .pi
            mapRotationDeg = -angDeg
        } else {
            mapRotationDeg = -(cameraYaw * 180.0 / .pi) - 90.0
        }
    }

    func setFloorplanImage(_ img: UIImage) {
        floorplanImage = img
        var cal = FloorplanCalibration.empty
        cal.imgWidth = Double(img.size.width)
        cal.imgHeight = Double(img.size.height)
        cal.offsetPxX = cal.imgWidth * 0.5
        cal.offsetPxY = cal.imgHeight * 0.5
        cal.scalePxPerMeter = max(20.0, min(cal.imgWidth, cal.imgHeight) / 20.0)
        calibration = cal
        pickTarget = .pickA
        scene3DRevision += 1
    }

    func handleFloorplanTap(normalizedU u: Double, normalizedV v: Double) {
        switch pickTarget {
        case .pickA:
            calibration.pointAImgU = u; calibration.pointAImgV = v
            calibration.pointAWorldX = cameraX; calibration.pointAWorldZ = cameraZ
            _ = calibration.solveFromTwoPoints()
            pickTarget = .pickB
            scene3DRevision += 1
        case .pickB:
            calibration.pointBImgU = u; calibration.pointBImgV = v
            calibration.pointBWorldX = cameraX; calibration.pointBWorldZ = cameraZ
            if calibration.solveFromTwoPoints() { pickTarget = .none }
            scene3DRevision += 1
        case .reAnchor:
            calibration.reAnchor(worldX: cameraX, worldZ: cameraZ, toImgU: u, imgV: v)
            pickTarget = .none
            scene3DRevision += 1
        case .none:
            break
        }
    }

    func recordPoint(from scan: ScanPayload) {
        let pt = SurveyPoint(
            id: UUID(),
            timestamp: Date().timeIntervalSince1970,
            x: cameraX, y: cameraY, z: cameraZ,
            headingRad: cameraYaw,
            scanId: scan.scanId,
            aps: scan.aps
        )
        points.append(pt)
        lastAutoWalkPos = SIMD2<Double>(cameraX, cameraZ)
        scene3DRevision += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func bandInfoForCurrentMetric(_ v: Double) -> (r: Double, g: Double, b: Double, band: Int) {
        switch selectedMetric {
        case .qbssUtil: return CiscoColors.bandInfo(forBadPct: v, maxPct: 100.0)
        case .monRetry: return CiscoColors.bandInfo(forBadPct: v, maxPct: 40.0)
        default: return CiscoColors.bandInfo(forRSSI: v)
        }
    }

    func colorForCurrentMetricUI(_ v: Double) -> UIColor {
        let c = bandInfoForCurrentMetric(v)
        return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1.0)
    }

    func metricValue(for pt: SurveyPoint) -> Double? {
        let filtered = pt.aps.filter { ap in
            (selectedSSID == "ALL" || ap.ssid == selectedSSID) &&
            (selectedBand == .all || ap.band == selectedBand.rawValue)
        }.sorted { $0.rssiDbm > $1.rssiDbm }
        guard !filtered.isEmpty else { return nil }
        switch selectedMetric {
        case .primaryRSSI: return filtered[0].rssiDbm
        case .secondaryRSSI: return filtered.count > 1 ? filtered[1].rssiDbm : -95.0
        case .apOverlap: return -90.0 + min(60.0, Double(filtered.count) * 10.0)
        case .qbssUtil:
            let utils = filtered.compactMap { $0.qbssUtilPct }
            return utils.isEmpty ? nil : utils.reduce(0, +) / Double(utils.count)
        case .monRetry:
            let retries = filtered.compactMap { $0.monRetryPct }
            return retries.isEmpty ? nil : retries.reduce(0, +) / Double(retries.count)
        }
    }

    /// Cisco-style Coverage Health Summary (vs -67 dBm Voice/Data Target)
    var coverageStats: (passPct: Int, avg: Double, min: Double, max: Double, roomW: Double, roomD: Double) {
        let vals = points.compactMap { metricValue(for: $0) }
        let avg = vals.isEmpty ? 0 : vals.reduce(0, +) / Double(vals.count)
        let mn = vals.min() ?? 0
        let mx = vals.max() ?? 0
        let passCount: Int
        if selectedMetric == .qbssUtil {
            passCount = vals.filter { $0 <= 50.0 }.count
        } else if selectedMetric == .monRetry {
            passCount = vals.filter { $0 <= 15.0 }.count
        } else {
            passCount = vals.filter { $0 >= -67.0 }.count
        }
        let passPct = vals.isEmpty ? 0 : Int((Double(passCount) * 100.0 / Double(vals.count)).rounded())

        var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
        var minZ = Double.greatestFiniteMagnitude, maxZ = -Double.greatestFiniteMagnitude
        for w in walls {
            minX = min(minX, min(w.x1, w.x2)); maxX = max(maxX, max(w.x1, w.x2))
            minZ = min(minZ, min(w.z1, w.z2)); maxZ = max(maxZ, max(w.z1, w.z2))
        }
        let rw = walls.isEmpty ? 0 : max(0, maxX - minX)
        let rd = walls.isEmpty ? 0 : max(0, maxZ - minZ)
        return (passPct, avg, mn, mx, rw, rd)
    }

    struct EstimatedAP {
        let bssid: String
        let ssid: String
        let label: String
        let ch: Int
        let band: String
        let rssi: Double
        let x: Double
        let z: Double
    }

    /// Estimate AP positions at the strongest surveyed measurement point for each strong BSSID
    var estimatedAPs: [EstimatedAP] {
        var bestByBSSID: [String: EstimatedAP] = [:]
        for pt in points {
            for ap in pt.aps {
                if selectedSSID != "ALL" && ap.ssid != selectedSSID { continue }
                if selectedBand != .all && ap.band != selectedBand.rawValue { continue }
                if ap.rssiDbm < -74.0 { continue }
                if let cur = bestByBSSID[ap.bssid] {
                    if ap.rssiDbm > cur.rssi {
                        bestByBSSID[ap.bssid] = EstimatedAP(bssid: ap.bssid, ssid: ap.displaySSID, label: ap.displayLabel, ch: ap.channel, band: ap.band, rssi: ap.rssiDbm, x: pt.x, z: pt.z)
                    }
                } else {
                    bestByBSSID[ap.bssid] = EstimatedAP(bssid: ap.bssid, ssid: ap.displaySSID, label: ap.displayLabel, ch: ap.channel, band: ap.band, rssi: ap.rssiDbm, x: pt.x, z: pt.z)
                }
            }
        }
        // Spatially merge multi-SSID virtual BSSIDs on the same physical AP (>0.75m apart)
        var dedup: [EstimatedAP] = []
        for ap in bestByBSSID.values.sorted(by: { $0.rssi > $1.rssi }) {
            if !dedup.contains(where: { hypot($0.x - ap.x, $0.z - ap.z) < 0.75 }) {
                dedup.append(ap)
            }
            if dedup.count >= 8 { break }
        }
        return dedup
    }

    func clearSurvey() {
        isViewingSavedMap = false
        isAutoWalkEnabled = false
        points.removeAll()
        walls.removeAll()
        doors.removeAll()
        windows.removeAll()
        openings.removeAll()
        floorPolygons.removeAll()
        objects.removeAll()
        floorplanImage = nil
        calibration = .empty
        pickTarget = .none
        lastAutoWalkPos = nil
        hasAutoAligned = false
        roomScanFinalized = false
        let ts = Int(Date().timeIntervalSince1970)
        surveyId = "survey_\(ts)"
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        surveyName = "Room Survey \(fmt.string(from: Date()))"
        onRestartRoomScan?()
        scene3DRevision += 1
        showToast("Map reset — ready to scan!")
    }

    func buildExportPayload() -> SurveySessionExport {
        var fpB64: String? = nil
        if let img = floorplanImage, calibration.isCalibrated {
            let maxDim: CGFloat = 1000
            let sc = min(1.0, maxDim / max(img.size.width, img.size.height))
            let sz = CGSize(width: img.size.width * sc, height: img.size.height * sc)
            let resized = UIGraphicsImageRenderer(size: sz).image { _ in img.draw(in: CGRect(origin: .zero, size: sz)) }
            fpB64 = resized.jpegData(compressionQuality: 0.65)?.base64EncodedString()
        }
        return SurveySessionExport(
            id: surveyId,
            name: surveyName,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            points: points,
            walls: walls,
            doors: doors,
            windows: windows,
            floors: floorPolygons,
            objects: objects,
            floorY: floorY,
            mapRotationDeg: mapRotationDeg,
            calibration: calibration.isCalibrated ? calibration : nil,
            floorplanJpegBase64: fpB64
        )
    }

    func exportJSONFileURL() -> URL? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(buildExportPayload()) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(surveyId).json")
        try? data.write(to: url)
        return url
    }
}

// MARK: - Apple RoomPlan Capture View Container (Live Architectural Room Scan + Pose Tracking)

struct RoomPlanCaptureContainer: UIViewRepresentable {
    @ObservedObject var store: SurveyStore
    @ObservedObject var client: WlanPiClient

    func makeUIView(context: Context) -> RoomCaptureView {
        let rcv = RoomCaptureView(frame: .zero)
        rcv.captureSession.delegate = context.coordinator
        context.coordinator.roomCaptureView = rcv

        store.onRestartRoomScan = { [weak coord = context.coordinator] in
            coord?.restartSession()
        }
        store.onFinalizeRoomScan = { [weak coord = context.coordinator] in
            coord?.finalizeScanKeepAR()
        }

        if RoomCaptureSession.isSupported {
            var cfg = RoomCaptureSession.Configuration()
            cfg.isCoachingEnabled = true
            rcv.captureSession.run(configuration: cfg)
            context.coordinator.startPoseTimer()
        }
        return rcv
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store, client: client)
    }

    final class Coordinator: NSObject, RoomCaptureSessionDelegate {
        let store: SurveyStore
        let client: WlanPiClient
        weak var roomCaptureView: RoomCaptureView?
        private var poseTimer: Timer?

        init(store: SurveyStore, client: WlanPiClient) {
            self.store = store
            self.client = client
        }

        deinit {
            poseTimer?.invalidate()
        }

        func startPoseTimer() {
            poseTimer?.invalidate()
            // Poll live ARFrame from RoomCaptureSession.arSession safely without replacing its internal delegate!
            poseTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                guard let self = self,
                      let session = self.roomCaptureView?.captureSession,
                      let frame = session.arSession.currentFrame else { return }
                let t = frame.camera.transform
                let pos = t.columns.3
                let yaw = atan2(Double(-t.columns.2.z), Double(-t.columns.2.x))
                let track: String
                switch frame.camera.trackingState {
                case .normal: track = "RoomPlan Tracking OK"
                case .notAvailable: track = "Unavailable"
                case .limited(let r):
                    switch r {
                    case .initializing: track = "Initializing..."
                    case .excessiveMotion: track = "Slow down"
                    case .insufficientFeatures: track = "Low light/texture"
                    case .relocalizing: track = "Relocalizing..."
                    @unknown default: track = "Limited"
                    }
                }
                Task { @MainActor in
                    self.store.updatePose(
                        x: Double(pos.x), y: Double(pos.y), z: Double(pos.z),
                        yaw: yaw, tracking: track,
                        latestScan: self.client.latestScan
                    )
                }
            }
        }

        func restartSession() {
            guard let rcv = roomCaptureView, RoomCaptureSession.isSupported else { return }
            rcv.captureSession.stop()
            var cfg = RoomCaptureSession.Configuration()
            cfg.isCoachingEnabled = true
            rcv.captureSession.run(configuration: cfg)
            startPoseTimer()
        }

        func finalizeScanKeepAR() {
            // Stop RoomPlan geometry refinement while keeping ARSession tracking alive so user can continue walking!
            roomCaptureView?.captureSession.stop(pauseARSession: false)
            Task { @MainActor in
                self.store.roomScanFinalized = true
                self.store.roomPlanInstruction = "Room locked! Continue walking to measure RF"
            }
        }

        func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
            Task { @MainActor in
                self.store.updateRoomPlan(room)
            }
        }

        func captureSession(_ session: RoomCaptureSession, didAdd room: CapturedRoom) {
            Task { @MainActor in
                self.store.updateRoomPlan(room)
            }
        }

        func captureSession(_ session: RoomCaptureSession, didChange room: CapturedRoom) {
            Task { @MainActor in
                self.store.updateRoomPlan(room)
            }
        }

        func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
            let text: String
            switch instruction {
            case .moveCloseToWall: text = "Move closer to wall"
            case .moveAwayFromWall: text = "Step back slightly from wall"
            case .slowDown: text = "Pan slowly for cleaner walls"
            case .turnOnLight: text = "More lighting helps RoomPlan"
            case .lowTexture: text = "Point at wall edges & corners"
            case .normal: text = "Good — keep scanning room walls"
            @unknown default: text = "Scanning room..."
            }
            Task { @MainActor in
                self.store.roomPlanInstruction = text
            }
        }
    }
}

// MARK: - Smooth High-Res Cisco Contour Bitmap Generator

@MainActor
struct CiscoHeatmapRenderer {
    /// Generates a smooth high-res Cisco Prime Infrastructure Thermal Rainbow CGImage with RSSI Cutoff!
    static func renderContourImage(
        widthPx: Int,
        heightPx: Int,
        samples: [(x: Double, z: Double, val: Double)],
        store: SurveyStore,
        pixelToWorld: (Double, Double) -> (Double, Double),
        floorPolygons: [[RoomPoint2D]],
        clipToRoom: Bool
    ) -> CGImage? {
        guard !samples.isEmpty, widthPx > 4, heightPx > 4 else { return nil }

        let count = widthPx * heightPx
        var rgba = [UInt8](repeating: 0, count: count * 4)

        let hasPolys = clipToRoom && !floorPolygons.isEmpty
        let cutoff = store.rssiCutoffDbm
        let isRSSIMetric = (store.selectedMetric == .primaryRSSI || store.selectedMetric == .secondaryRSSI)

        for py in 0..<heightPx {
            for px in 0..<widthPx {
                let (wx, wz) = pixelToWorld(Double(px) + 0.5, Double(py) + 0.5)

                if hasPolys {
                    var insideAny = false
                    for poly in floorPolygons {
                        if CiscoColors.pointInPolygon(x: wx, z: wz, poly: poly) {
                            insideAny = true; break
                        }
                    }
                    if !insideAny { continue }
                }

                var num = 0.0, den = 0.0, minD = Double.greatestFiniteMagnitude
                for s in samples {
                    let d = hypot(wx - s.x, wz - s.z)
                    if d < minD { minD = d }
                    let w = 1.0 / (d * d + 0.18)
                    num += w * s.val
                    den += w
                }
                guard den > 0 else { continue }

                var val = num / den
                if isRSSIMetric {
                    // Realistic radial path-loss bloom outside measured points (just like Cisco Prime!)
                    let decay = minD > 1.0 ? 2.6 * (minD - 1.0) : 0.0
                    val -= decay
                    if val < cutoff { continue }
                } else if !hasPolys && minD > 5.5 {
                    continue
                }

                let info = store.bandInfoForCurrentMetric(val)
                let edgeFade: Double = isRSSIMetric
                    ? min(1.0, (val - cutoff) / 4.0)
                    : (hasPolys ? 1.0 : max(0.0, min(1.0, (1.0 - minD / 5.5) * 1.4)))

                let o = (py * widthPx + px) * 4
                rgba[o]     = UInt8(max(0, min(255, Int(info.r * 255))))
                rgba[o + 1] = UInt8(max(0, min(255, Int(info.g * 255))))
                rgba[o + 2] = UInt8(max(0, min(255, Int(info.b * 255))))
                rgba[o + 3] = UInt8(max(0, min(255, Int(edgeFade * 175.0))))
            }
        }

        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(
            width: widthPx, height: heightPx,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: widthPx * 4,
            space: cs, bitmapInfo: bitmapInfo, provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}

// MARK: - Cisco DNA Center Style 2D CAD Floorplan & Heatmap View

struct CiscoFloorplanView: View {
    @ObservedObject var store: SurveyStore

    @State private var zoom: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0
    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero

    private func fittedImageRect(in size: CGSize, image: UIImage) -> CGRect {
        let pad: CGFloat = 20
        let availW = max(1, size.width - pad * 2)
        let availH = max(1, size.height - pad * 2)
        let imgAspect = image.size.width / max(1, image.size.height)
        let viewAspect = availW / availH
        let baseW = imgAspect > viewAspect ? availW : availH * imgAspect
        let baseH = imgAspect > viewAspect ? availW / imgAspect : availH
        let w = baseW * zoom, h = baseH * zoom
        return CGRect(x: (size.width - w) * 0.5 + pan.width, y: (size.height - h) * 0.5 + pan.height, width: w, height: h)
    }

    var body: some View {
        let bgCol = store.ciscoLightTheme ? Color(red: 0.955, green: 0.968, blue: 0.985) : Color(red: 0.05, green: 0.07, blue: 0.10)

        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                Canvas { ctx, size in
                    if let img = store.floorplanImage {
                        drawCalibratedCiscoMap(ctx: ctx, size: size, image: img)
                    } else {
                        drawRoomPlanCiscoMap(ctx: ctx, size: size)
                    }
                }
                .background(bgCol)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    guard store.pickTarget != .none, let img = store.floorplanImage else { return }
                    let rect = fittedImageRect(in: geo.size, image: img)
                    let u = Double((location.x - rect.minX) / max(1, rect.width))
                    let v = Double((location.y - rect.minY) / max(1, rect.height))
                    if u >= 0 && u <= 1 && v >= 0 && v <= 1 {
                        store.handleFloorplanTap(normalizedU: u, normalizedV: v)
                    }
                }
                .gesture(
                    MagnificationGesture()
                        .onChanged { val in zoom = max(0.35, min(6.0, lastZoom * val)) }
                        .onEnded { _ in lastZoom = zoom }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { val in
                            pan = CGSize(width: lastPan.width + val.translation.width, height: lastPan.height + val.translation.height)
                        }
                        .onEnded { _ in lastPan = pan }
                )

                // Top-left Cisco Coverage KPI Summary Card
                VStack(alignment: .leading, spacing: 6) {
                    ciscoStatsCard
                    if store.pickTarget != .none {
                        HStack(spacing: 8) {
                            Image(systemName: "scope").foregroundColor(.yellow)
                            Text(calibrationPromptText).font(.caption.bold()).foregroundColor(.white)
                            Button("Cancel") { store.pickTarget = .none }.font(.caption.bold()).foregroundColor(.yellow)
                        }
                        .padding(9)
                        .background(Color.blue.opacity(0.92))
                        .cornerRadius(8)
                    }
                    Spacer()
                }
                .padding(10)

                // Bottom Cisco Discrete Contour Legend + Tools
                HStack(alignment: .bottom, spacing: 8) {
                    ciscoDiscreteLegend

                    Spacer()

                    Button {
                        store.ciscoLightTheme.toggle()
                    } label: {
                        Image(systemName: store.ciscoLightTheme ? "moon.fill" : "sun.max.fill")
                            .font(.caption.bold())
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }

                    if store.floorplanImage == nil {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { store.autoStraightenWalls() }
                        } label: {
                            Label("Align", systemImage: "rotate.right")
                                .font(.caption.bold())
                                .padding(.horizontal, 9).padding(.vertical, 7)
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                        }
                    } else if store.calibration.isCalibrated {
                        Button { store.pickTarget = .reAnchor } label: {
                            Label("Re-Anchor", systemImage: "pin.fill")
                                .font(.caption.bold())
                                .padding(.horizontal, 9).padding(.vertical, 7)
                                .background(Color.orange)
                                .foregroundColor(.black)
                                .cornerRadius(8)
                        }
                    }

                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            zoom = 1.0; lastZoom = 1.0; pan = .zero; lastPan = .zero
                        }
                    } label: {
                        Label("Fit", systemImage: "viewfinder")
                            .font(.caption.bold())
                            .padding(.horizontal, 9).padding(.vertical, 7)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }
                }
                .padding(10)
            }
        }
    }

    private var ciscoStatsCard: some View {
        let st = store.coverageStats
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.selectedMetric == .qbssUtil ? "Target ≤ 50% Util" : (store.selectedMetric == .monRetry ? "Target ≤ 15% Retry" : "Cisco Target ≥ -67 dBm"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    Text(store.points.isEmpty ? "No Samples" : "Pass \(st.passPct)%")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundColor(st.passPct >= 80 ? .green : (st.passPct >= 50 ? .orange : .red))
                    if !store.points.isEmpty {
                        Text(String(format: "Avg %.0f | Min %.0f", st.avg, st.min))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                }
            }
            if st.roomW > 0.5 {
                Divider().frame(height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("RoomPlan Size").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                    Text(String(format: "%.1f × %.1f m", st.roomW, st.roomD))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .cornerRadius(9)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    private var ciscoDiscreteLegend: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Cisco Prime Thermal").font(.system(size: 9, weight: .bold))
                Spacer()
                Menu {
                    Button("Cutoff -75 dBm") { store.rssiCutoffDbm = -75 }
                    Button("Cutoff -80 dBm") { store.rssiCutoffDbm = -80 }
                    Button("Cutoff -85 dBm") { store.rssiCutoffDbm = -85 }
                    Button("No Cutoff (-95)") { store.rssiCutoffDbm = -95 }
                } label: {
                    Text("Cut \(Int(store.rssiCutoffDbm))")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            HStack(spacing: 4) {
                Text("-35").font(.system(size: 8, weight: .bold, design: .monospaced))
                LinearGradient(
                    colors: [
                        Color(red: 0.50, green: 0.00, blue: 0.00),
                        Color(red: 0.88, green: 0.14, blue: 0.14),
                        Color(red: 0.98, green: 0.45, blue: 0.09),
                        Color(red: 0.98, green: 0.80, blue: 0.08),
                        Color(red: 0.09, green: 0.83, blue: 0.31),
                        Color(red: 0.02, green: 0.76, blue: 0.91),
                        Color(red: 0.11, green: 0.31, blue: 0.85),
                        Color(red: 0.12, green: 0.04, blue: 0.36)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 145, height: 11)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.primary.opacity(0.4), lineWidth: 0.8))
                .cornerRadius(2)
                Text("-90").font(.system(size: 8, weight: .bold, design: .monospaced))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }

    private var calibrationPromptText: String {
        switch store.pickTarget {
        case .pickA: return "Step 1/2: Stand at Point A, then TAP Point A on floorplan"
        case .pickB: return "Step 2/2: Walk ≥2m to Point B, then TAP Point B on floorplan"
        case .reAnchor: return "Drift Fix: TAP your real current spot on the floorplan"
        case .none: return ""
        }
    }

    // MARK: RoomPlan Architectural Cisco CAD Map

    private func drawRoomPlanCiscoMap(ctx: GraphicsContext, size: CGSize) {
        let isLight = store.ciscoLightTheme
        let rot = store.mapRotationDeg * .pi / 180.0
        let cr = cos(rot), sr = sin(rot)
        func rotW(_ x: Double, _ z: Double) -> (Double, Double) { (x * cr - z * sr, x * sr + z * cr) }
        func invRotW(_ rx: Double, _ rz: Double) -> (Double, Double) { (rx * cr + rz * sr, -rx * sr + rz * cr) }

        let camR = rotW(store.cameraX, store.cameraZ)
        var minX = camR.0 - 4.0, maxX = camR.0 + 4.0
        var minZ = camR.1 - 4.0, maxZ = camR.1 + 4.0
        for pt in store.points {
            let p = rotW(pt.x, pt.z)
            minX = min(minX, p.0 - 2.0); maxX = max(maxX, p.0 + 2.0)
            minZ = min(minZ, p.1 - 2.0); maxZ = max(maxZ, p.1 + 2.0)
        }
        for w in store.walls {
            let p1 = rotW(w.x1, w.z1), p2 = rotW(w.x2, w.z2)
            minX = min(minX, min(p1.0, p2.0) - 1.2); maxX = max(maxX, max(p1.0, p2.0) + 1.2)
            minZ = min(minZ, min(p1.1, p2.1) - 1.2); maxZ = max(maxZ, max(p1.1, p2.1) + 1.2)
        }

        let spanX = max(5.0, maxX - minX)
        let spanZ = max(5.0, maxZ - minZ)
        let scale = min((size.width - 50) / spanX, (size.height - 80) / spanZ) * zoom
        let ox = size.width * 0.5 + pan.width - ((minX + maxX) * 0.5) * scale
        let oz = size.height * 0.5 + pan.height - ((minZ + maxZ) * 0.5) * scale

        func toScreen(_ wx: Double, _ wz: Double) -> CGPoint {
            let p = rotW(wx, wz)
            return CGPoint(x: p.0 * scale + ox, y: p.1 * scale + oz)
        }

        // 1. Clean 1m architectural CAD grid
        let visMinX = Int(floor((0 - ox) / scale)), visMaxX = Int(ceil((size.width - ox) / scale))
        let visMinZ = Int(floor((0 - oz) / scale)), visMaxZ = Int(ceil((size.height - oz) / scale))
        var grid = Path()
        if visMaxX - visMinX < 100 {
            for gx in visMinX...visMaxX {
                let sx = Double(gx) * scale + ox
                grid.move(to: CGPoint(x: sx, y: 0)); grid.addLine(to: CGPoint(x: sx, y: size.height))
            }
        }
        if visMaxZ - visMinZ < 100 {
            for gz in visMinZ...visMaxZ {
                let sz = Double(gz) * scale + oz
                grid.move(to: CGPoint(x: 0, y: sz)); grid.addLine(to: CGPoint(x: size.width, y: sz))
            }
        }
        ctx.stroke(grid, with: .color(isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.07)), lineWidth: 1)

        // 2. RoomPlan Floor Polygon base fill (crisp white room interior on light CAD)
        for poly in store.floorPolygons where poly.count >= 3 {
            var fp = Path()
            for (i, pt) in poly.enumerated() {
                let sp = toScreen(pt.x, pt.z)
                if i == 0 { fp.move(to: sp) } else { fp.addLine(to: sp) }
            }
            fp.closeSubpath()
            ctx.fill(fp, with: .color(isLight ? .white : Color(red: 0.09, green: 0.12, blue: 0.17)))
        }

        // 3. High-Res Smooth Cisco Stepped-Contour Heatmap CGImage
        let samples: [(x: Double, z: Double, val: Double)] = store.points.compactMap { pt in
            guard let v = store.metricValue(for: pt) else { return nil }
            return (pt.x, pt.z, v)
        }
        if !samples.isEmpty {
            let bmpW = 160
            let bmpH = max(80, Int(Double(bmpW) * Double(size.height / max(1, size.width))))
            let sxRatio = Double(size.width) / Double(bmpW)
            let syRatio = Double(size.height) / Double(bmpH)
            if let cgImg = CiscoHeatmapRenderer.renderContourImage(
                widthPx: bmpW, heightPx: bmpH,
                samples: samples, store: store,
                pixelToWorld: { px, py in
                    let rx = (px * sxRatio - ox) / scale
                    let rz = (py * syRatio - oz) / scale
                    return invRotW(rx, rz)
                },
                floorPolygons: store.floorPolygons,
                clipToRoom: store.clipHeatmapToRoom
            ) {
                ctx.draw(Image(decorative: cgImg, scale: 1.0), in: CGRect(origin: .zero, size: size))
            }
        }

        // 4. RoomPlan Architectural Furniture Outlines (clean CAD boxes, NOT noisy dots!)
        for obj in store.objects where obj.corners.count == 4 {
            var op = Path()
            for (i, c) in obj.corners.enumerated() {
                let sp = toScreen(c.x, c.z)
                if i == 0 { op.move(to: sp) } else { op.addLine(to: sp) }
            }
            op.closeSubpath()
            ctx.fill(op, with: .color(isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.08)))
            ctx.stroke(op, with: .color(isLight ? Color(red: 0.45, green: 0.52, blue: 0.60) : Color.white.opacity(0.35)), lineWidth: 1.2)
        }

        // 5. RoomPlan Crisp Architectural Walls, Windows & Doors
        drawRoomSurfaces(ctx: ctx, toScreen: toScreen, isLight: isLight)

        // 6. Walk Path, Estimated Cisco AP Icons, Measured dBm Pills & Live Position
        drawSurveyOverlays(ctx: ctx, samples: samples, toScreen: toScreen, headingRad: store.cameraYaw + rot, isLight: isLight, scale: scale)
    }

    // MARK: Calibrated Imported Floorplan Cisco Map

    private func drawCalibratedCiscoMap(ctx: GraphicsContext, size: CGSize, image: UIImage) {
        let rect = fittedImageRect(in: size, image: image)
        ctx.draw(Image(uiImage: image), in: rect)

        let cal = store.calibration
        func toScreen(_ wx: Double, _ wz: Double) -> CGPoint {
            let uv = cal.worldToNormalized(wx, wz)
            return CGPoint(x: rect.minX + uv.x * rect.width, y: rect.minY + uv.y * rect.height)
        }

        if let au = cal.pointAImgU, let av = cal.pointAImgV {
            drawAnchorBadge(ctx: ctx, at: CGPoint(x: rect.minX + au * rect.width, y: rect.minY + av * rect.height), label: "A", color: .yellow)
        }
        if let bu = cal.pointBImgU, let bv = cal.pointBImgV {
            drawAnchorBadge(ctx: ctx, at: CGPoint(x: rect.minX + bu * rect.width, y: rect.minY + bv * rect.height), label: "B", color: .green)
        }
        guard cal.isCalibrated else { return }

        let samples: [(x: Double, z: Double, val: Double)] = store.points.compactMap { pt in
            guard let v = store.metricValue(for: pt) else { return nil }
            return (pt.x, pt.z, v)
        }
        if !samples.isEmpty {
            let bmpW = 160
            let bmpH = max(80, Int(Double(bmpW) * Double(rect.height / max(1, rect.width))))
            if let cgImg = CiscoHeatmapRenderer.renderContourImage(
                widthPx: bmpW, heightPx: bmpH,
                samples: samples, store: store,
                pixelToWorld: { px, py in
                    cal.normalizedToWorld(px / Double(bmpW), py / Double(bmpH))
                },
                floorPolygons: [],
                clipToRoom: false
            ) {
                ctx.draw(Image(decorative: cgImg, scale: 1.0), in: rect)
            }
        }

        if store.showRoomWallsOnFloorplan {
            drawRoomSurfaces(ctx: ctx, toScreen: toScreen, isLight: true)
        }
        drawSurveyOverlays(ctx: ctx, samples: samples, toScreen: toScreen, headingRad: store.cameraYaw + cal.rotationRad, isLight: true, scale: 50)
    }

    private func drawRoomSurfaces(ctx: GraphicsContext, toScreen: (Double, Double) -> CGPoint, isLight: Bool) {
        // Solid Architectural Walls
        if !store.walls.isEmpty {
            var wp = Path()
            for w in store.walls {
                wp.move(to: toScreen(w.x1, w.z1))
                wp.addLine(to: toScreen(w.x2, w.z2))
            }
            ctx.stroke(
                wp,
                with: .color(isLight ? Color(red: 0.11, green: 0.16, blue: 0.24) : Color(red: 0.90, green: 0.94, blue: 0.98)),
                style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round)
            )
        }
        // Windows (Cisco architectural sky-blue glass lines)
        if !store.windows.isEmpty {
            var winP = Path()
            for w in store.windows {
                winP.move(to: toScreen(w.x1, w.z1)); winP.addLine(to: toScreen(w.x2, w.z2))
            }
            ctx.stroke(winP, with: .color(Color(red: 0.08, green: 0.62, blue: 0.95)), style: StrokeStyle(lineWidth: 4.5, lineCap: .butt))
        }
        // Doors (emerald architectural door breaks)
        if !store.doors.isEmpty {
            var doorP = Path()
            for d in store.doors {
                doorP.move(to: toScreen(d.x1, d.z1)); doorP.addLine(to: toScreen(d.x2, d.z2))
            }
            ctx.stroke(doorP, with: .color(Color(red: 0.10, green: 0.72, blue: 0.45)), style: StrokeStyle(lineWidth: 4.0, lineCap: .round, dash: [6, 4]))
        }
    }

    private func drawAnchorBadge(ctx: GraphicsContext, at p: CGPoint, label: String, color: Color) {
        let r = CGRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22)
        ctx.fill(Path(ellipseIn: r), with: .color(color))
        ctx.stroke(Path(ellipseIn: r), with: .color(.black), lineWidth: 2)
        ctx.draw(Text(label).font(.system(size: 12, weight: .black)).foregroundColor(.black), at: p)
    }

    private func drawSurveyOverlays(
        ctx: GraphicsContext,
        samples: [(x: Double, z: Double, val: Double)],
        toScreen: (Double, Double) -> CGPoint,
        headingRad: Double,
        isLight: Bool,
        scale: Double
    ) {
        // Walk path
        if store.points.count > 1 {
            var walk = Path()
            for (i, pt) in store.points.enumerated() {
                let sp = toScreen(pt.x, pt.z)
                if i == 0 { walk.move(to: sp) } else { walk.addLine(to: sp) }
            }
            ctx.stroke(walk, with: .color(Color(red: 0.04, green: 0.46, blue: 0.85).opacity(0.75)), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
        }

        // Survey Point Pins with clean Cisco-style dBm callout pills
        for s in samples {
            let p = toScreen(s.x, s.z)
            let c = store.bandInfoForCurrentMetric(s.val)
            let fillCol = Color(red: c.r, green: c.g, blue: c.b)

            let outer = Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14))
            ctx.fill(outer, with: .color(.white))
            ctx.stroke(outer, with: .color(fillCol), lineWidth: 3)

            let inner = Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
            ctx.fill(inner, with: .color(fillCol))

            if scale > 20 {
                let lbl = (store.selectedMetric == .qbssUtil || store.selectedMetric == .monRetry)
                    ? String(format: "%.0f%%", s.val)
                    : String(format: "%.0f", s.val)
                let pillRect = CGRect(x: p.x - 15, y: p.y - 24, width: 30, height: 14)
                ctx.fill(Path(roundedRect: pillRect, cornerRadius: 4), with: .color(isLight ? .white.opacity(0.92) : .black.opacity(0.82)))
                ctx.stroke(Path(roundedRect: pillRect, cornerRadius: 4), with: .color(fillCol), lineWidth: 1)
                ctx.draw(
                    Text(lbl).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(isLight ? .black : .white),
                    at: CGPoint(x: p.x, y: p.y - 17)
                )
            }
        }

        // Classic Cisco Prime Target Crosshair AP Icons + Crisp White Bordered Callout Tags
        if store.showEstimatedAPs {
            for ap in store.estimatedAPs {
                let p = toScreen(ap.x, ap.z)
                let outer = Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18))
                ctx.fill(outer, with: .color(Color(red: 0.28, green: 0.33, blue: 0.41)))
                ctx.stroke(outer, with: .color(.white), lineWidth: 2)
                let innerRing = Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
                ctx.stroke(innerRing, with: .color(.white), lineWidth: 1.2)
                var cross = Path()
                cross.move(to: CGPoint(x: p.x - 11, y: p.y)); cross.addLine(to: CGPoint(x: p.x + 11, y: p.y))
                cross.move(to: CGPoint(x: p.x, y: p.y - 11)); cross.addLine(to: CGPoint(x: p.x, y: p.y + 11))
                ctx.stroke(cross, with: .color(.white), lineWidth: 1.1)

                let tag = "\(ap.label.prefix(16)) (Ch\(ap.ch))"
                let tagW = CGFloat(max(78, tag.count * 6 + 12))
                let tagRect = CGRect(x: p.x + 13, y: p.y - 9, width: tagW, height: 18)
                ctx.fill(Path(tagRect), with: .color(.white))
                ctx.stroke(Path(tagRect), with: .color(.black), lineWidth: 1.2)
                ctx.draw(
                    Text(tag).font(.system(size: 9, weight: .bold)).foregroundColor(.black),
                    at: CGPoint(x: tagRect.midX, y: tagRect.midY)
                )
            }
        }

        // Live Surveyor Position + Heading Cone
        let camPt = toScreen(store.cameraX, store.cameraZ)
        var cone = Path()
        let coneLen: CGFloat = 28, spread = 0.45
        cone.move(to: camPt)
        cone.addLine(to: CGPoint(x: camPt.x + cos(headingRad - spread) * coneLen, y: camPt.y + sin(headingRad - spread) * coneLen))
        cone.addLine(to: CGPoint(x: camPt.x + cos(headingRad + spread) * coneLen, y: camPt.y + sin(headingRad + spread) * coneLen))
        cone.closeSubpath()
        ctx.fill(cone, with: .color(Color(red: 0.02, green: 0.56, blue: 0.96).opacity(0.35)))

        let meDot = Path(ellipseIn: CGRect(x: camPt.x - 7, y: camPt.y - 7, width: 14, height: 14))
        ctx.fill(meDot, with: .color(Color(red: 0.02, green: 0.56, blue: 0.96)))
        ctx.stroke(meDot, with: .color(.white), lineWidth: 2.5)
    }
}

// MARK: - Interactive 3D Architectural RoomPlan + Cisco RF SceneKit View

struct RoomPlan3DSceneView: UIViewRepresentable {
    @ObservedObject var store: SurveyStore
    let cameraResetToken: Int

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = store.ciscoLightTheme
            ? UIColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1.0)
            : UIColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 1.0)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X

        let scene = SCNScene()
        view.scene = scene

        let camNode = SCNNode()
        camNode.name = "mainCam"
        camNode.camera = SCNCamera()
        camNode.camera?.zNear = 0.05
        camNode.camera?.zFar = 200.0
        camNode.position = SCNVector3(0, 9, 11)
        camNode.eulerAngles = SCNVector3(-0.70, 0, 0)
        scene.rootNode.addChildNode(camNode)
        view.pointOfView = camNode

        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light?.type = .ambient
        amb.light?.intensity = 750
        scene.rootNode.addChildNode(amb)

        let dir = SCNNode()
        dir.light = SCNLight()
        dir.light?.type = .directional
        dir.light?.intensity = 850
        dir.eulerAngles = SCNVector3(-0.9, 0.5, 0)
        scene.rootNode.addChildNode(dir)

        let worldRoot = SCNNode()
        worldRoot.name = "worldRoot"
        scene.rootNode.addChildNode(worldRoot)

        let meNode = buildLiveMarkerNode()
        meNode.name = "liveMe"
        scene.rootNode.addChildNode(meNode)

        context.coordinator.lastResetToken = cameraResetToken
        rebuildSceneContent(in: worldRoot, store: store)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.backgroundColor = store.ciscoLightTheme
            ? UIColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1.0)
            : UIColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 1.0)
        guard let scene = uiView.scene else { return }

        if let me = scene.rootNode.childNode(withName: "liveMe", recursively: false) {
            me.position = SCNVector3(Float(store.cameraX), Float(store.floorY + 0.35), Float(store.cameraZ))
            me.eulerAngles = SCNVector3(0, Float(-store.cameraYaw + .pi * 0.5), 0)
        }

        let key = "\(store.scene3DRevision)-\(store.selectedSSID)-\(store.selectedBand.rawValue)-\(store.selectedMetric.rawValue)-\(store.useCisco3DDomes)-\(store.elevate3DHeatmap)-\(store.show3DWalls)-\(store.show3DObjects)-\(store.ciscoLightTheme)-\(store.clipHeatmapToRoom)"
        if context.coordinator.lastBuildKey != key {
            context.coordinator.lastBuildKey = key
            if let root = scene.rootNode.childNode(withName: "worldRoot", recursively: false) {
                rebuildSceneContent(in: root, store: store)
            }
        }

        if context.coordinator.lastResetToken != cameraResetToken {
            context.coordinator.lastResetToken = cameraResetToken
            if let cam = scene.rootNode.childNode(withName: "mainCam", recursively: false) {
                let cx = Float(store.cameraX), cz = Float(store.cameraZ), fy = Float(store.floorY)
                cam.position = SCNVector3(cx, fy + 9.0, cz + 10.0)
                cam.look(at: SCNVector3(cx, fy, cz))
                uiView.pointOfView = cam
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        var lastBuildKey: String = ""
        var lastResetToken: Int = 0
    }

    private func buildLiveMarkerNode() -> SCNNode {
        let parent = SCNNode()
        let sphere = SCNSphere(radius: 0.16)
        sphere.firstMaterial?.diffuse.contents = UIColor.systemBlue
        sphere.firstMaterial?.emission.contents = UIColor.systemBlue.withAlphaComponent(0.5)
        parent.addChildNode(SCNNode(geometry: sphere))
        let cone = SCNCone(topRadius: 0.0, bottomRadius: 0.15, height: 0.42)
        cone.firstMaterial?.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.75)
        let cNode = SCNNode(geometry: cone)
        cNode.eulerAngles = SCNVector3(Float.pi * 0.5, 0, 0)
        cNode.position = SCNVector3(0, 0, -0.3)
        parent.addChildNode(cNode)
        return parent
    }

    private func rebuildSceneContent(in root: SCNNode, store: SurveyStore) {
        root.childNodes.forEach { $0.removeFromParentNode() }
        let fy = Float(store.floorY)
        let isLight = store.ciscoLightTheme

        var minX = store.cameraX - 5.0, maxX = store.cameraX + 5.0
        var minZ = store.cameraZ - 5.0, maxZ = store.cameraZ + 5.0
        for pt in store.points {
            minX = min(minX, pt.x - 3.0); maxX = max(maxX, pt.x + 3.0)
            minZ = min(minZ, pt.z - 3.0); maxZ = max(maxZ, pt.z + 3.0)
        }
        for w in store.walls {
            minX = min(minX, min(w.x1, w.x2) - 1.5); maxX = max(maxX, max(w.x1, w.x2) + 1.5)
            minZ = min(minZ, min(w.z1, w.z2) - 1.5); maxZ = max(maxZ, max(w.z1, w.z2) + 1.5)
        }

        // 1. Floor Grid or Calibrated Real Floorplan
        if let fpImg = store.floorplanImage, store.calibration.isCalibrated {
            let cal = store.calibration
            let c00 = cal.normalizedToWorld(0, 0), c10 = cal.normalizedToWorld(1, 0), c01 = cal.normalizedToWorld(0, 1)
            let wM = hypot(c10.0 - c00.0, c10.1 - c00.1)
            let hM = hypot(c01.0 - c00.0, c01.1 - c00.1)
            let center = cal.normalizedToWorld(0.5, 0.5)
            let plane = SCNPlane(width: CGFloat(wM), height: CGFloat(hM))
            plane.firstMaterial?.diffuse.contents = fpImg
            plane.firstMaterial?.lightingModel = .constant
            plane.firstMaterial?.isDoubleSided = true
            let n = SCNNode(geometry: plane)
            n.position = SCNVector3(Float(center.0), fy - 0.02, Float(center.1))
            n.eulerAngles = SCNVector3(-Float.pi * 0.5, Float(cal.rotationRad), 0)
            root.addChildNode(n)
        } else {
            root.addChildNode(buildFloorGrid(minX: minX, maxX: maxX, minZ: minZ, maxZ: maxZ, y: fy - 0.02, isLight: isLight))
        }

        // 2. Clean Matte-Gray 3D RoomPlan Architectural Walls (Cisco DNA 3D style!)
        if store.show3DWalls {
            let wallMat = SCNMaterial()
            wallMat.diffuse.contents = isLight
                ? UIColor(red: 0.72, green: 0.75, blue: 0.79, alpha: 0.96)
                : UIColor(red: 0.58, green: 0.78, blue: 0.96, alpha: 0.42)
            wallMat.roughness.contents = 0.85
            wallMat.isDoubleSided = true

            let borderMat = SCNMaterial()
            borderMat.diffuse.contents = isLight ? UIColor(red: 0.36, green: 0.40, blue: 0.46, alpha: 1.0) : UIColor.cyan

            for w in store.walls {
                let len = hypot(w.x2 - w.x1, w.z2 - w.z1)
                if len < 0.2 { continue }
                let h = max(1.8, min(3.5, w.yMax - w.yMin))
                let box = SCNBox(width: CGFloat(len), height: CGFloat(h), length: 0.08, chamferRadius: 0)
                box.materials = [wallMat]
                let node = SCNNode(geometry: box)
                let mx = Float((w.x1 + w.x2) * 0.5), mz = Float((w.z1 + w.z2) * 0.5)
                let yaw = Float(-atan2(w.z2 - w.z1, w.x2 - w.x1))
                node.position = SCNVector3(mx, fy + Float(h * 0.5), mz)
                node.eulerAngles = SCNVector3(0, yaw, 0)
                root.addChildNode(node)

                // Architectural top trim cap for crisp CAD look
                let cap = SCNBox(width: CGFloat(len), height: 0.05, length: 0.10, chamferRadius: 0)
                cap.materials = [borderMat]
                let capN = SCNNode(geometry: cap)
                capN.position = SCNVector3(mx, fy + Float(h), mz)
                capN.eulerAngles = SCNVector3(0, yaw, 0)
                root.addChildNode(capN)
            }

            // Windows (translucent sky blue)
            let winMat = SCNMaterial()
            winMat.diffuse.contents = UIColor(red: 0.15, green: 0.68, blue: 0.98, alpha: 0.55)
            for win in store.windows {
                let len = hypot(win.x2 - win.x1, win.z2 - win.z1)
                let h = max(0.6, win.yMax - win.yMin)
                let box = SCNBox(width: CGFloat(len), height: CGFloat(h), length: 0.11, chamferRadius: 0)
                box.materials = [winMat]
                let node = SCNNode(geometry: box)
                node.position = SCNVector3(Float((win.x1 + win.x2) * 0.5), Float((win.yMin + win.yMax) * 0.5), Float((win.z1 + win.z2) * 0.5))
                node.eulerAngles = SCNVector3(0, Float(-atan2(win.z2 - win.z1, win.x2 - win.x1)), 0)
                root.addChildNode(node)
            }

            // Doors (emerald architectural door frame)
            let doorMat = SCNMaterial()
            doorMat.diffuse.contents = UIColor(red: 0.12, green: 0.72, blue: 0.45, alpha: 0.55)
            for d in store.doors {
                let len = hypot(d.x2 - d.x1, d.z2 - d.z1)
                let h = max(1.8, d.yMax - d.yMin)
                let box = SCNBox(width: CGFloat(len), height: CGFloat(h), length: 0.11, chamferRadius: 0)
                box.materials = [doorMat]
                let node = SCNNode(geometry: box)
                node.position = SCNVector3(Float((d.x1 + d.x2) * 0.5), fy + Float(h * 0.5), Float((d.z1 + d.z2) * 0.5))
                node.eulerAngles = SCNVector3(0, Float(-atan2(d.z2 - d.z1, d.x2 - d.x1)), 0)
                root.addChildNode(node)
            }
        }

        // 3. Clean 3D RoomPlan Furniture Boxes
        if store.show3DObjects {
            let objMat = SCNMaterial()
            objMat.diffuse.contents = isLight
                ? UIColor(red: 0.70, green: 0.75, blue: 0.82, alpha: 0.65)
                : UIColor(red: 0.45, green: 0.52, blue: 0.62, alpha: 0.5)
            for obj in store.objects {
                let b = SCNBox(width: CGFloat(max(0.15, obj.width)), height: CGFloat(max(0.15, obj.height)), length: CGFloat(max(0.15, obj.depth)), chamferRadius: 0.03)
                b.materials = [objMat]
                let n = SCNNode(geometry: b)
                n.position = SCNVector3(Float(obj.cx), Float(obj.cy), Float(obj.cz))
                n.eulerAngles = SCNVector3(0, Float(-obj.yawRad), 0)
                root.addChildNode(n)
            }
        }

        // 4. Cisco DNA Center 3D Wireless Analyzer (Red Floor + Volumetric Green/Amber Domes + Teardrop Score Pins!)
        let samples: [(x: Double, y: Double, z: Double, val: Double)] = store.points.compactMap { pt in
            guard let v = store.metricValue(for: pt) else { return nil }
            return (pt.x, pt.y, pt.z, v)
        }
        if !samples.isEmpty {
            if store.useCisco3DDomes {
                // Red Dead-Zone Floor Base (< -75 dBm) just like Cisco DNA 3D Analyzer!
                let slabW = CGFloat(max(4.0, maxX - minX))
                let slabD = CGFloat(max(4.0, maxZ - minZ))
                let slab = SCNBox(width: slabW, height: 0.04, length: slabD, chamferRadius: 0)
                slab.firstMaterial?.diffuse.contents = UIColor(red: 0.90, green: 0.17, blue: 0.17, alpha: 0.95)
                slab.firstMaterial?.lightingModel = .constant
                let slabN = SCNNode(geometry: slab)
                slabN.position = SCNVector3(Float((minX + maxX) * 0.5), fy + 0.01, Float((minZ + maxZ) * 0.5))
                root.addChildNode(slabN)

                // Volumetric 3D Coverage Domes per AP (or per measured cluster)
                let domeTargets: [(x: Double, z: Double, rssi: Double, label: String)] = {
                    let aps = store.estimatedAPs
                    if !aps.isEmpty {
                        return aps.map { ($0.x, $0.z, $0.rssi, "\($0.label.prefix(14))-Ch\($0.ch)") }
                    }
                    return samples.prefix(6).enumerated().map { ($0.element.x, $0.element.z, $0.element.val, "Pt-\($0.offset + 1)") }
                }()

                for ap in domeTargets {
                    // Inner Emerald Green Dome (>= -65 dBm)
                    if ap.rssi >= -65.0 {
                        let rG = max(1.1, min(3.2, (ap.rssi + 73.0) * 0.14))
                        let hG = min(2.0, rG * 0.78)
                        let gDome = buildHemisphereNode(
                            radiusXZ: Float(rG), heightY: Float(hG),
                            color: UIColor(red: 0.07, green: 0.60, blue: 0.18, alpha: 0.88),
                            renderOrder: 5
                        )
                        gDome.position = SCNVector3(Float(ap.x), fy + 0.03, Float(ap.z))
                        root.addChildNode(gDome)
                    }

                    // Outer Warm Amber-Orange Dome (-65 .. -75 dBm)
                    if ap.rssi >= -75.0 {
                        let rA = max(1.9, min(4.6, (ap.rssi + 84.0) * 0.16))
                        let hA = min(2.5, rA * 0.65)
                        let aDome = buildHemisphereNode(
                            radiusXZ: Float(rA), heightY: Float(hA),
                            color: UIColor(red: 0.96, green: 0.65, blue: 0.14, alpha: 0.48),
                            renderOrder: 10
                        )
                        aDome.position = SCNVector3(Float(ap.x), fy + 0.03, Float(ap.z))
                        root.addChildNode(aDome)
                    }

                    // White AP tile on floor/ceiling
                    let apTile = SCNBox(width: 0.28, height: 0.06, length: 0.28, chamferRadius: 0.02)
                    apTile.firstMaterial?.diffuse.contents = UIColor.white
                    let tileN = SCNNode(geometry: apTile)
                    tileN.position = SCNVector3(Float(ap.x), fy + 0.08, Float(ap.z))
                    root.addChildNode(tileN)

                    // Floating Cisco DNA Teardrop Health Score Pin (10 green / 6 orange) + Label!
                    let score = ap.rssi >= -58 ? 10 : (ap.rssi >= -65 ? 9 : (ap.rssi >= -72 ? 7 : 6))
                    let pinNode = buildBillboardPinNode(score: score, title: ap.label)
                    pinNode.position = SCNVector3(Float(ap.x), fy + 2.55, Float(ap.z))
                    root.addChildNode(pinNode)
                }
            } else {
                if let hmNode = buildCisco3DHeatmap(samples: samples, minX: minX, maxX: maxX, minZ: minZ, maxZ: maxZ, floorY: fy + 0.05, store: store) {
                    root.addChildNode(hmNode)
                }
            }
        }
    }

    private func buildHemisphereNode(radiusXZ: Float, heightY: Float, color: UIColor, renderOrder: Int) -> SCNNode {
        let segsU = 28, segsV = 12
        var verts: [SCNVector3] = []
        var norms: [SCNVector3] = []
        var indices: [UInt32] = []

        for iv in 0...segsV {
            let phi = Float(iv) / Float(segsV) * (Float.pi * 0.5)
            let cosP = cos(phi), sinP = sin(phi)
            for iu in 0...segsU {
                let th = Float(iu) / Float(segsU) * (Float.pi * 2.0)
                let cosT = cos(th), sinT = sin(th)
                let vx = cosP * cosT * radiusXZ
                let vy = sinP * heightY
                let vz = cosP * sinT * radiusXZ
                verts.append(SCNVector3(vx, vy, vz))
                norms.append(SCNVector3(cosP * cosT, sinP, cosP * sinT))
            }
        }
        let stride = segsU + 1
        for iv in 0..<segsV {
            for iu in 0..<segsU {
                let i0 = UInt32(iv * stride + iu)
                let i1 = i0 + 1
                let i2 = UInt32((iv + 1) * stride + iu)
                let i3 = i2 + 1
                indices.append(contentsOf: [i0, i1, i2, i1, i3, i2])
            }
        }
        let geom = SCNGeometry(
            sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.isDoubleSided = true
        mat.writesToDepthBuffer = (renderOrder < 8)
        mat.transparencyMode = .aOne
        geom.materials = [mat]
        let node = SCNNode(geometry: geom)
        node.renderingOrder = renderOrder
        return node
    }

    private func buildBillboardPinNode(score: Int, title: String) -> SCNNode {
        let imgSize = CGSize(width: 280, height: 84)
        let renderer = UIGraphicsImageRenderer(size: imgSize)
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            let pinColor = score >= 8
                ? UIColor(red: 0.09, green: 0.64, blue: 0.29, alpha: 1.0)
                : UIColor(red: 0.96, green: 0.62, blue: 0.05, alpha: 1.0)

            // Draw Cisco DNA teardrop pin on left
            let cx: CGFloat = 34, cy: CGFloat = 34
            cg.setFillColor(pinColor.cgColor)
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(3.0)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: cx, y: 76))
            path.addCurve(to: CGPoint(x: cx, y: 10), controlPoint1: CGPoint(x: cx - 32, y: 48), controlPoint2: CGPoint(x: cx - 30, y: 10))
            path.addCurve(to: CGPoint(x: cx, y: 76), controlPoint1: CGPoint(x: cx + 30, y: 10), controlPoint2: CGPoint(x: cx + 32, y: 48))
            path.close()
            cg.addPath(path.cgPath)
            cg.drawPath(using: .fillStroke)

            // Score text inside pin
            let sAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let sStr = "\(score)" as NSString
            let sSz = sStr.size(withAttributes: sAttrs)
            sStr.draw(at: CGPoint(x: cx - sSz.width * 0.5, y: cy - sSz.height * 0.5), withAttributes: sAttrs)

            // AP Name label cleanly next to pin
            let lAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Georgia-Bold", size: 18) ?? UIFont.boldSystemFont(ofSize: 18),
                .foregroundColor: UIColor(red: 0.12, green: 0.16, blue: 0.23, alpha: 1.0)
            ]
            (title as NSString).draw(at: CGPoint(x: 68, y: 22), withAttributes: lAttrs)
        }

        let plane = SCNPlane(width: 2.3, height: 0.70)
        plane.firstMaterial?.diffuse.contents = img
        plane.firstMaterial?.lightingModel = .constant
        plane.firstMaterial?.isDoubleSided = true
        let node = SCNNode(geometry: plane)
        let bb = SCNBillboardConstraint()
        bb.freeAxes = [.X, .Y]
        node.constraints = [bb]
        node.renderingOrder = 20
        return node
    }

    private func buildFloorGrid(minX: Double, maxX: Double, minZ: Double, maxZ: Double, y: Float, isLight: Bool) -> SCNNode {
        var verts: [SCNVector3] = [], indices: [UInt32] = []
        let x0 = Int(floor(minX)), x1 = Int(ceil(maxX)), z0 = Int(floor(minZ)), z1 = Int(ceil(maxZ))
        if x1 - x0 <= 120 {
            for gx in x0...x1 {
                let i = UInt32(verts.count)
                verts.append(SCNVector3(Float(gx), y, Float(z0))); verts.append(SCNVector3(Float(gx), y, Float(z1)))
                indices.append(i); indices.append(i + 1)
            }
        }
        if z1 - z0 <= 120 {
            for gz in z0...z1 {
                let i = UInt32(verts.count)
                verts.append(SCNVector3(Float(x0), y, Float(gz))); verts.append(SCNVector3(Float(x1), y, Float(gz)))
                indices.append(i); indices.append(i + 1)
            }
        }
        let geom = SCNGeometry(sources: [SCNGeometrySource(vertices: verts)], elements: [SCNGeometryElement(indices: indices, primitiveType: .line)])
        geom.firstMaterial?.diffuse.contents = isLight ? UIColor.black.withAlphaComponent(0.10) : UIColor.white.withAlphaComponent(0.14)
        geom.firstMaterial?.lightingModel = .constant
        return SCNNode(geometry: geom)
    }

    private func buildCisco3DHeatmap(
        samples: [(x: Double, y: Double, z: Double, val: Double)],
        minX: Double, maxX: Double, minZ: Double, maxZ: Double,
        floorY: Float,
        store: SurveyStore
    ) -> SCNNode? {
        let cols = 48, rows = 48
        let dx = (maxX - minX) / Double(cols - 1)
        let dz = (maxZ - minZ) / Double(rows - 1)
        let hasPolys = store.clipHeatmapToRoom && !store.floorPolygons.isEmpty
        let radiusM = 6.0, radiusM2 = radiusM * radiusM

        var verts: [SCNVector3] = []
        var colors: [SIMD4<Float>] = []
        var valid = [Bool](repeating: false, count: cols * rows)

        for r in 0..<rows {
            let wz = minZ + Double(r) * dz
            for c in 0..<cols {
                let wx = minX + Double(c) * dx
                var ok = true
                if hasPolys {
                    ok = store.floorPolygons.contains { CiscoColors.pointInPolygon(x: wx, z: wz, poly: $0) }
                }
                if !ok {
                    verts.append(SCNVector3(Float(wx), floorY, Float(wz)))
                    colors.append(SIMD4<Float>(0, 0, 0, 0))
                    continue
                }
                var num = 0.0, den = 0.0, minD2 = Double.greatestFiniteMagnitude
                for s in samples {
                    let d2 = (wx - s.x) * (wx - s.x) + (wz - s.z) * (wz - s.z)
                    if d2 < minD2 { minD2 = d2 }
                    let w = 1.0 / (d2 + 0.16)
                    num += w * s.val; den += w
                }
                if (!hasPolys && minD2 > radiusM2) || den <= 0 {
                    verts.append(SCNVector3(Float(wx), floorY, Float(wz)))
                    colors.append(SIMD4<Float>(0, 0, 0, 0))
                    continue
                }
                let v = num / den
                let ci = store.bandInfoForCurrentMetric(v)
                let dist = sqrt(minD2)
                let alpha: Float = hasPolys ? 0.78 : Float(max(0.18, min(0.80, (1.0 - dist / radiusM) * 0.90)))
                var h: Float = 0
                if store.elevate3DHeatmap {
                    let norm = Double(ci.band) / 5.0
                    h = Float(norm * 1.25)
                }
                verts.append(SCNVector3(Float(wx), floorY + h, Float(wz)))
                colors.append(SIMD4<Float>(Float(ci.r), Float(ci.g), Float(ci.b), alpha))
                valid[r * cols + c] = true
            }
        }

        var indices: [UInt32] = []
        for r in 0..<(rows - 1) {
            for c in 0..<(cols - 1) {
                let i0 = r * cols + c, i1 = i0 + 1, i2 = i0 + cols, i3 = i2 + 1
                if valid[i0] && valid[i1] && valid[i2] { indices.append(contentsOf: [UInt32(i0), UInt32(i2), UInt32(i1)]) }
                if valid[i1] && valid[i2] && valid[i3] { indices.append(contentsOf: [UInt32(i1), UInt32(i2), UInt32(i3)]) }
            }
        }
        guard !indices.isEmpty else { return nil }

        let vSrc = SCNGeometrySource(vertices: verts)
        let colorData = colors.withUnsafeBytes { Data($0) }
        let cSrc = SCNGeometrySource(
            data: colorData, semantic: .color, vectorCount: colors.count,
            usesFloatComponents: true, componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
            dataStride: MemoryLayout<SIMD4<Float>>.stride
        )
        let geom = SCNGeometry(sources: [vSrc, cSrc], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.blendMode = .alpha
        mat.writesToDepthBuffer = false
        geom.materials = [mat]
        return SCNNode(geometry: geom)
    }

    private func buildLineCylinder(from a: SCNVector3, to b: SCNVector3, radius: CGFloat, color: UIColor) -> SCNNode {
        let dist = sqrt(pow(b.x - a.x, 2) + pow(b.y - a.y, 2) + pow(b.z - a.z, 2))
        let cyl = SCNCylinder(radius: radius, height: CGFloat(max(0.01, dist)))
        cyl.firstMaterial?.diffuse.contents = color
        cyl.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: cyl)
        node.position = SCNVector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, (a.z + b.z) * 0.5)
        node.look(at: b, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
        return node
    }
}

// MARK: - Sheets (Calibration, AP List, Settings)

struct FloorplanCalibrationSheet: View {
    @ObservedObject var store: SurveyStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section("1. Real Floorplan Image (Optional)") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(store.floorplanImage == nil ? "Import Floorplan from Photos" : "Replace Floorplan Image", systemImage: "photo.on.rectangle.angled")
                    }
                    .onChange(of: selectedPhoto) { _, newItem in
                        guard let item = newItem else { return }
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let uiImg = UIImage(data: data) {
                                store.setFloorplanImage(uiImg)
                            }
                        }
                    }

                    if store.floorplanImage != nil {
                        Button(role: .destructive) {
                            store.floorplanImage = nil
                            store.calibration = .empty
                            store.pickTarget = .none
                            store.scene3DRevision += 1
                        } label: {
                            Label("Remove Floorplan (Use RoomPlan Auto Floorplan)", systemImage: "xmark.circle")
                        }
                    }
                }

                if store.floorplanImage != nil {
                    Section("2. 2-Point Walk Calibration (Align to Real Room)") {
                        Text("Stand at Corner A → tap Point A on the 2D Map. Walk ≥2–5m to Corner B → tap Point B. Exact scale & rotation are solved automatically.")
                            .font(.caption).foregroundColor(.secondary)

                        Button {
                            store.pickTarget = .pickA
                            dismiss()
                        } label: {
                            Label("Start 2-Point Calibration (A → B)", systemImage: "scope")
                        }
                        .buttonStyle(.borderedProminent)

                        if store.calibration.isCalibrated {
                            HStack {
                                Text("Scale"); Spacer()
                                Text(String(format: "%.1f px/m", store.calibration.scalePxPerMeter)).foregroundColor(.green).font(.caption.monospaced())
                            }
                            Slider(value: $store.calibration.rotationRad, in: -.pi ... .pi) { Text("Rotation") }
                            Toggle("Overlay RoomPlan Walls", isOn: $store.showRoomWallsOnFloorplan)
                            Button { store.pickTarget = .reAnchor; dismiss() } label: {
                                Label("Fix Drift (Re-Anchor Here)", systemImage: "pin.fill")
                            }
                        }
                    }
                } else {
                    Section("RoomPlan Auto Floorplan Controls") {
                        Button { store.autoStraightenWalls(); dismiss() } label: {
                            Label("Auto-Align Longest Wall Straight", systemImage: "rotate.right")
                        }
                        VStack(alignment: .leading) {
                            Text(String(format: "Map Rotation: %.0f°", store.mapRotationDeg)).font(.caption)
                            Slider(value: $store.mapRotationDeg, in: -180...180, step: 1)
                        }
                        Toggle("Clip Heatmap Inside RoomPlan Floor", isOn: $store.clipHeatmapToRoom)
                        Toggle("Show Estimated Cisco AP Icons", isOn: $store.showEstimatedAPs)
                        Toggle("Cisco Light CAD Theme", isOn: $store.ciscoLightTheme)
                    }
                }
            }
            .navigationTitle("Floorplan & Calibrate")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct APDeepInspectorSheet: View {
    let ap: APRecord
    let monitorActive: Bool
    let onFilterSSID: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss

    private func kvRow(_ label: String, _ value: String, valueColor: Color = .primary) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }

    private func sourceNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle.fill").font(.caption2).foregroundColor(.blue)
            Text(text).font(.caption2).foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    var body: some View {
        NavigationStack {
            List {
                // Header Summary + Quick Filter
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ap.displaySSID).font(.title3.bold())
                                Text(ap.bssid).font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(String(format: "%.0f dBm", ap.rssiDbm))
                                    .font(.system(.title3, design: .monospaced).bold())
                                    .foregroundColor(CiscoColors.color(forRSSI: ap.rssiDbm))
                                Text("\(ap.band) • Ch \(ap.channel) (\(ap.widthMhz) MHz)")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        if !ap.ssid.isEmpty, let onFilter = onFilterSSID {
                            Button {
                                onFilter(ap.ssid)
                                dismiss()
                            } label: {
                                Label("Filter 2D/3D Heatmap to '\(ap.ssid)'", systemImage: "line.3.horizontal.decrease.circle.fill")
                                    .font(.caption.bold())
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                        }
                    }
                }

                // RF Health Audit
                Section("RF Health Audit") {
                    let warns = ap.healthWarnings ?? []
                    if warns.isEmpty {
                        Label("ไม่พบปัญหา Config พื้นฐาน (RF Config Healthy)", systemImage: "checkmark.seal.fill")
                            .font(.caption.bold())
                            .foregroundColor(.green)
                    } else {
                        ForEach(warns, id: \.self) { w in
                            Label(w, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }

                // Identity & Radio PHY
                Section("1. Identity & Radio PHY") {
                    kvRow("Vendor (OUI)", ap.vendor ?? "Unknown")
                    if let m = ap.apModel, !m.isEmpty { kvRow("AP Model / Spec", m) }
                    if let n = ap.apName, !n.isEmpty { kvRow("AP Name (Beacon)", n, valueColor: .blue) }
                    kvRow("Wi-Fi Generation", ap.wifiGen)
                    kvRow("Spatial Streams", (ap.streams ?? "").isEmpty ? "-" : (ap.streams ?? "-"))
                    if let phy = ap.maxPhyMbps {
                        kvRow("Max PHY Rate", "\(phy) Mbps", valueColor: .green)
                    }
                    kvRow("Frequency / Channel", "\(ap.freqMhz) MHz (Ch \(ap.channel) • \(ap.widthMhz) MHz)")
                    if let tx = ap.txPowerDbm { kvRow("AP TX Power (TPC)", "\(tx) dBm") }
                    if let cc = ap.country, !cc.isEmpty { kvRow("Country Code", cc) }
                    sourceNote("ที่มา: Vendor จาก MAC OUI (35,169 ยี่ห้อ) + จับคู่ Virtual BSSID • ชื่อ/รุ่นจาก Cisco Aironet IE (0x85) / WPS IE • Streams & Max PHY คำนวณจาก HT/VHT/HE MCS Set")
                }

                // Security & Fast Roaming
                Section("2. Security, Fast Roaming & Wi-Fi 6/7") {
                    kvRow("Security", ap.security, valueColor: (ap.security == "Open" || ap.security == "WEP") ? .red : .primary)
                    if let akm = ap.akm, !akm.isEmpty { kvRow("Auth (AKM)", akm.joined(separator: ", ")) }
                    if let cph = ap.ciphers, !cph.isEmpty { kvRow("Ciphers", cph.joined(separator: ", ")) }
                    let pmfVal = ap.pmf ?? "Disabled"
                    kvRow("PMF (802.11w)", pmfVal, valueColor: pmfVal == "Disabled" ? .secondary : .green)
                    kvRow("802.11k (Neighbor Report)", ap.dot11k == true ? "Enabled" : "Off", valueColor: ap.dot11k == true ? .green : .secondary)
                    kvRow("802.11v (BSS Transition)", ap.dot11v == true ? "Enabled" : "Off", valueColor: ap.dot11v == true ? .green : .secondary)
                    kvRow("802.11r (Fast Roam FT)", ap.dot11r == true ? "Enabled" : "Off", valueColor: ap.dot11r == true ? .green : .secondary)
                    if let bc = ap.bssColor {
                        kvRow("HE BSS Color", bc == 0 ? "0 (Disabled)" : "#\(bc)", valueColor: bc > 0 ? .cyan : .secondary)
                    }
                    sourceNote("ที่มา: อ่านจาก RSN IE (PMF/AKM), RM Capabilities (11k), Extended Capabilities (11v), Mobility Domain/FT (11r) และ HE Operation IE (BSS Color ช่วยลดคลื่นชนใน Wi-Fi 6/7)")
                }

                // Airtime, Rates & RF Environment
                Section("3. Airtime, Rates & RF Environment") {
                    if let util = ap.qbssUtilPct {
                        kvRow("QBSS Channel Util", String(format: "%.1f%%", util), valueColor: util > 60 ? .red : (util > 35 ? .orange : .green))
                    } else {
                        kvRow("QBSS Channel Util", "Not broadcast", valueColor: .secondary)
                    }
                    if let sta = ap.qbssStations {
                        kvRow("QBSS Stations (AP Reported)", "\(sta) clients", valueColor: sta > 0 ? .blue : .secondary)
                    } else {
                        kvRow("QBSS Stations (AP Reported)", "Not broadcast", valueColor: .secondary)
                    }
                    if let rates = ap.basicRatesMbps, !rates.isEmpty {
                        let rStr = rates.map { $0.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", $0) : String(format: "%.1f", $0) }.joined(separator: ", ") + " Mbps"
                        kvRow("Basic Rates", rStr, valueColor: ap.legacyRatesEnabled == true && ap.band == "2.4GHz" ? .orange : .primary)
                    }
                    if let bi = ap.beaconIntervalMs { kvRow("Beacon Interval", String(format: "%.1f ms", bi)) }
                    if let dtim = ap.dtimPeriod { kvRow("DTIM Period", "\(dtim)") }
                    let cci = ap.cciCount ?? 0
                    kvRow("Co-Channel APs (CCI)", "\(cci) other physical APs on Ch \(ap.channel)", valueColor: cci >= 3 ? .orange : .primary)
                    let coCount = ap.coBssidCount ?? 1
                    kvRow("SSIDs on Physical Radio", "\(coCount) BSSIDs", valueColor: coCount >= 4 ? .orange : .primary)
                    if let sibs = ap.siblingSsids, sibs.count > 1 {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sibling SSIDs (Same Radio):").font(.caption2).foregroundColor(.secondary)
                            Text(sibs.joined(separator: " • ")).font(.caption).foregroundColor(.primary)
                        }
                    }
                    sourceNote("ที่มา: QBSS จาก BSS Load IE (0x0B) ที่ตัว AP ประกาศเอง • Basic Rates จาก Supported Rates IE (* คืออัตราเร็วบังคับ) • CCI นับจำนวน Physical AP ที่ใช้ช่องสัญญาณเดียวกัน")
                }

                // Active Clients on This AP
                Section("4. Active Clients บน AP นี้ (มาจากไหน?)") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("1) QBSS Station Count = \(ap.qbssStations.map { "\($0) เครื่อง" } ?? "AP ไม่ส่งค่านี้")")
                            .font(.caption.bold())
                        Text("→ ตัว AP นับจำนวนเครื่องลูกที่เกาะอยู่จริงแล้วส่งตัวเลขมาใน Beacon (IE 0x0B) รู้จำนวนรวมแม่นยำ แต่ AP ไม่ได้ส่ง MAC เครื่องลูกมาใน Beacon")
                            .font(.caption2).foregroundColor(.secondary)

                        Text("2) Monitor Mode Sniffed = \(ap.monClients ?? 0) เครื่อง (Retry: \(ap.monRetryPct.map { String(format: "%.1f%%", $0) } ?? "-"))")
                            .font(.caption.bold()).padding(.top, 4)
                        Text("→ ดักจับ Data Frame จริงกลางอากาศผ่าน USB Monitor Adapter ทำให้รู้ MAC + ยี่ห้อ Client (OUI) + RSSI + Retry%")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)

                    if let monClients = ap.monClientList, !monClients.isEmpty {
                        ForEach(monClients) { c in
                            ClientRowView(clientRecord: c)
                        }
                    } else if !monitorActive {
                        Label("USB Monitor Adapter ไม่ได้เสียบอยู่ — เสียบตัวรับที่รองรับ Monitor Mode เพื่อดู MAC & ยี่ห้อของ Client รายเครื่อง", systemImage: "antenna.radiowaves.left.and.right.slash")
                            .font(.caption2).foregroundColor(.orange)
                    } else {
                        Text("ยังตรวจไม่พบ Data Frame จาก Client บนช่อง \(ap.channel) ใน 30 วินาทีล่าสุด")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("AP Deep Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct ClientRowView: View {
    let clientRecord: ClientRecord

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(clientRecord.mac)
                        .font(.system(.caption, design: .monospaced).bold())
                    if clientRecord.isRandomMac == true {
                        Text("Private/Random MAC")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    } else {
                        Text(clientRecord.vendor)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }
                HStack(spacing: 5) {
                    Text(clientRecord.type ?? "Client")
                        .foregroundColor((clientRecord.type ?? "").contains("Data") ? .green : .purple)
                    if let ssid = clientRecord.apSsid, !ssid.isEmpty {
                        Text("•"); Text("AP: \(ssid)")
                    }
                    if let ch = clientRecord.channel, ch > 0 {
                        Text("•"); Text("Ch \(ch)")
                    }
                }
                .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let rssi = clientRecord.rssiDbm {
                    Text(String(format: "%.0f dBm", rssi))
                        .font(.system(.caption, design: .monospaced).bold())
                        .foregroundColor(CiscoColors.color(forRSSI: rssi))
                }
                Text("\(clientRecord.frames ?? 0)f • \(String(format: "%.0f%%", clientRecord.retryPct ?? 0)) retry")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}

struct APListSheet: View {
    @ObservedObject var client: WlanPiClient
    @ObservedObject var store: SurveyStore
    @Environment(\.dismiss) private var dismiss
    @State private var search: String = ""
    @State private var selectedTab: Int = 0 // 0 = APs, 1 = Clients & Vendors
    @State private var inspectedAP: APRecord? = nil

    private var filteredAPs: [APRecord] {
        (client.latestScan?.aps ?? []).filter { ap in
            let bandOK = store.selectedBand == .all || ap.band == store.selectedBand.rawValue
            let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return bandOK && (
                q.isEmpty ||
                ap.displaySSID.lowercased().contains(q) ||
                ap.bssid.lowercased().contains(q) ||
                (ap.vendor ?? "").lowercased().contains(q) ||
                (ap.apModel ?? "").lowercased().contains(q)
            )
        }
    }

    private var qbssReportingAPs: [APRecord] {
        (client.latestScan?.aps ?? [])
            .filter { ($0.qbssStations ?? 0) > 0 }
            .sorted { ($0.qbssStations ?? 0) > ($1.qbssStations ?? 0) }
    }

    private var sniffedClients: [ClientRecord] {
        let all = client.latestScan?.monitor?.clients ?? []
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.mac.lowercased().contains(q) ||
            $0.vendor.lowercased().contains(q) ||
            ($0.apSsid ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Live KPI strip + Tab Picker
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        kpiPill(title: "APs", value: "\(client.latestScan?.apCount ?? 0)", color: .blue)
                        kpiPill(title: "QBSS Clients (AP)", value: "\(client.latestScan?.qbssTotalClients ?? 0)", color: .green)
                        kpiPill(
                            title: "Sniffed (Mon)",
                            value: client.latestScan?.monitor?.active == true ? "\(client.latestScan?.monitor?.uniqueClients10s ?? 0)" : "OFF",
                            color: client.latestScan?.monitor?.active == true ? .purple : .secondary
                        )
                    }
                    Picker("View", selection: $selectedTab) {
                        Text("AP Inspector (\(filteredAPs.count))").tag(0)
                        Text("Clients & Vendors").tag(1)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                if selectedTab == 0 {
                    apListBody
                } else {
                    clientListBody
                }
            }
            .searchable(text: $search, prompt: selectedTab == 0 ? "Filter SSID, BSSID, Vendor, Model" : "Filter Client MAC, Vendor, AP")
            .navigationTitle("RF & Client Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(item: $inspectedAP) { ap in
                APDeepInspectorSheet(
                    ap: ap,
                    monitorActive: client.latestScan?.monitor?.active == true
                ) { ssid in
                    store.selectedSSID = ssid
                    dismiss()
                }
            }
        }
    }

    private func kpiPill(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.headline, design: .monospaced).bold()).foregroundColor(color)
            Text(title).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }

    private var apListBody: some View {
        List {
            Section {
                Button { store.selectedSSID = "ALL"; dismiss() } label: {
                    HStack {
                        Text("Show All SSIDs on Heatmap").fontWeight(.semibold)
                        Spacer()
                        if store.selectedSSID == "ALL" { Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor) }
                    }
                }
            }
            Section("Live APs (\(filteredAPs.count)) — แตะแถวเพื่อ Filter • แตะ (i) เพื่อดูละเอียด") {
                ForEach(filteredAPs) { ap in
                    HStack(spacing: 10) {
                        Button {
                            if !ap.ssid.isEmpty { store.selectedSSID = ap.ssid; dismiss() }
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 5) {
                                        Text(ap.displaySSID).font(.headline).foregroundColor(.primary).lineLimit(1)
                                        if let model = ap.apModel, !model.isEmpty {
                                            Text(model)
                                                .font(.system(size: 10, weight: .semibold))
                                                .padding(.horizontal, 5).padding(.vertical, 2)
                                                .background(Color.blue.opacity(0.15))
                                                .foregroundColor(.blue)
                                                .cornerRadius(4)
                                                .lineLimit(1)
                                        }
                                        if let warns = ap.healthWarnings, !warns.isEmpty {
                                            Text("⚠️ \(warns.count)")
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 5).padding(.vertical, 1)
                                                .background(Color.orange.opacity(0.2))
                                                .foregroundColor(.orange)
                                                .cornerRadius(4)
                                        }
                                        if store.selectedSSID == ap.ssid && !ap.ssid.isEmpty {
                                            Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor).font(.caption)
                                        }
                                    }
                                    Text("\(ap.bssid) • \(ap.band) • Ch \(ap.channel) (\(ap.widthMhz)MHz)" + (ap.maxPhyMbps != nil ? " • \(ap.maxPhyMbps!)M" : ""))
                                        .font(.system(.caption2, design: .monospaced)).foregroundColor(.secondary)
                                    HStack(spacing: 5) {
                                        Text(ap.security)
                                        if !ap.roamingTags.isEmpty {
                                            Text("•"); Text(ap.roamingTags.joined(separator: "/")).foregroundColor(.green)
                                        }
                                        if let sta = ap.qbssStations {
                                            Text("•"); Text("\(sta) STA").foregroundColor(sta > 0 ? .blue : .secondary)
                                        }
                                        if let util = ap.qbssUtilPct {
                                            Text("•"); Text(String(format: "Util %.0f%%", util))
                                        }
                                        if let retry = ap.monRetryPct, (ap.monFrames ?? 0) > 0 {
                                            Text("•")
                                            Text(String(format: "Retry %.0f%%", retry))
                                                .foregroundColor(retry > 20 ? .red : .green)
                                        }
                                    }.font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer(minLength: 4)
                                VStack(alignment: .trailing) {
                                    Text(String(format: "%.0f dBm", ap.rssiDbm))
                                        .font(.system(.subheadline, design: .monospaced).bold())
                                        .foregroundColor(CiscoColors.color(forRSSI: ap.rssiDbm))
                                    Text("\(ap.freqMhz) MHz").font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            inspectedAP = ap
                        } label: {
                            Image(systemName: "info.circle.fill")
                                .font(.title3)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private var clientListBody: some View {
        List {
            Section("Active Clients เอามาจากไหน? & ดูยี่ห้อ Client ยังไง?") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("1. QBSS Clients (จาก AP Beacon — ใช้ได้ตลอดผ่าน wlan0)", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.bold()).foregroundColor(.green)
                    Text("ตัว AP องค์กร (Cisco, Ubiquiti, Huawei ฯลฯ) นับจำนวนเครื่องลูกที่เกาะอยู่จริงแล้วส่งมาใน Beacon IE 0x0B → แม่นยำทุกคลื่น แต่ AP จะส่งแค่ \"จำนวนรวม\" ไม่ส่ง MAC หรือยี่ห้อเครื่องลูกมาด้วย")
                        .font(.caption2).foregroundColor(.secondary)

                    Label("2. Sniffed Clients + Vendor (จาก USB Monitor Mode)", systemImage: "eye.fill")
                        .font(.caption.bold()).foregroundColor(.purple).padding(.top, 4)
                    Text("เมื่อเสียบ USB Wi-Fi Adapter ที่รองรับ Monitor Mode (เช่น wlan1) ตัว Pi จะดักจับ Data Frame & Probe Request กลางอากาศ แล้วเทียบ MAC 3 ไบต์แรกกับฐานข้อมูล OUI (35,169 ยี่ห้อ) → รู้ทันทีว่าเป็น Apple / Samsung / Intel / Espressif ฯลฯ พร้อมแยกแยะ Private / Random MAC (iOS/Android รุ่นใหม่) ให้ด้วย")
                        .font(.caption2).foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("APs Reporting QBSS Clients (\(qbssReportingAPs.count) APs • รวม \(client.latestScan?.qbssTotalClients ?? 0) เครื่อง)") {
                if qbssReportingAPs.isEmpty {
                    Text("ยังไม่พบ AP ที่รายงาน QBSS Station > 0 ในรอบสแกนนี้").font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(qbssReportingAPs) { ap in
                        Button {
                            inspectedAP = ap
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ap.displaySSID).font(.subheadline.bold()).foregroundColor(.primary)
                                    Text("\(ap.apModel ?? ap.wifiGen) • \(ap.band) Ch \(ap.channel) • Util \(String(format: "%.1f%%", ap.qbssUtilPct ?? 0))")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(ap.qbssStations ?? 0) STA")
                                    .font(.system(.subheadline, design: .monospaced).bold())
                                    .foregroundColor(.blue)
                                Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Sniffed Clients & Vendors (Monitor Mode 30s — \(sniffedClients.count))") {
                if client.latestScan?.monitor?.active != true {
                    Label("USB Monitor Mode ไม่ได้ทำงาน (ยังไม่ได้เสียบ USB Adapter ที่รองรับ Monitor Mode) — เสียบเมื่อไหร่ระบบจะ Auto-Attach และแสดง MAC + ยี่ห้อ Client ทันที", systemImage: "antenna.radiowaves.left.and.right.slash")
                        .font(.caption).foregroundColor(.orange)
                } else if sniffedClients.isEmpty {
                    Text("กำลังดักจับเฟรมบน \(client.latestScan?.monitor?.interface ?? "wlan1") (Ch \(client.latestScan?.monitor?.currentChannel ?? 0)) — ยังไม่พบ Client ใน 30 วินาทีล่าสุด")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(sniffedClients) { c in
                        ClientRowView(clientRecord: c)
                    }
                }
            }
        }
    }
}

struct SettingsSheet: View {
    @ObservedObject var client: WlanPiClient
    @ObservedObject var store: SurveyStore
    @Environment(\.dismiss) private var dismiss
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("WLAN Pi R4 Probe Connection") {
                    HStack {
                        TextField("host:port", text: $client.hostAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                        Button { client.autoFindProbe() } label: {
                            if client.isAutoSearching { ProgressView() }
                            else { Label("Auto-Find", systemImage: "magnifyingglass") }
                        }.buttonStyle(.borderedProminent)
                    }
                    ForEach(WlanPiClient.presetHosts, id: \.host) { preset in
                        Button { client.hostAddress = preset.host } label: {
                            HStack {
                                Text(preset.label); Spacer()
                                Text(preset.host).font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                                if client.hostAddress == preset.host { Image(systemName: "checkmark").foregroundColor(.accentColor) }
                            }
                        }
                    }
                    HStack {
                        Text("Status"); Spacer()
                        Text(client.isConnected ? "Connected (\(client.latencyMs)ms)" : (client.lastError ?? "Disconnected"))
                            .foregroundColor(client.isConnected ? .green : .red).font(.caption)
                    }
                    if let mon = client.latestScan?.monitor, mon.active == true {
                        HStack {
                            Text("Monitor (\(mon.interface ?? "wlan1"))"); Spacer()
                            Text(String(format: "%d f/10s • %.1f%% retry • %d STA", mon.totalFrames10s ?? 0, mon.retryPct10s ?? 0, mon.uniqueClients10s ?? 0))
                                .font(.caption).foregroundColor(.green)
                        }
                    }
                }

                Section("Survey & 3D Options") {
                    TextField("Survey Name", text: $store.surveyName)
                    Picker("Auto-Walk Spacing", selection: $store.autoWalkSpacingMeters) {
                        Text("0.5 m").tag(0.5); Text("1.0 m").tag(1.0); Text("1.5 m").tag(1.5); Text("2.0 m").tag(2.0)
                    }
                    Toggle("Cisco Light CAD Theme", isOn: $store.ciscoLightTheme)
                    Toggle("Clip Heatmap to RoomPlan Floor", isOn: $store.clipHeatmapToRoom)
                    Toggle("3D Heatmap Elevation Hills", isOn: $store.elevate3DHeatmap)
                    Toggle("Show 3D RoomPlan Walls", isOn: $store.show3DWalls)
                    Toggle("Show 3D RoomPlan Furniture", isOn: $store.show3DObjects)
                }

                Section("Sync & Export") {
                    Button {
                        Task { await client.uploadSurvey(store.buildExportPayload()) }
                    } label: {
                        HStack {
                            Label(client.isSyncing ? "Syncing to WLAN Pi..." : "Sync RoomPlan + RF Survey to WLAN Pi", systemImage: "arrow.up.to.line.circle.fill")
                            if client.isSyncing { Spacer(); ProgressView() }
                        }
                    }.disabled((store.points.isEmpty && store.walls.isEmpty) || client.isSyncing)

                    if let status = client.syncStatus {
                        Text(status).font(.caption).foregroundColor(status.contains("Synced") ? .green : .orange)
                    }

                    if let url = shareURL {
                        ShareLink(item: url) { Label("Share Survey JSON (\(store.points.count) pts)", systemImage: "square.and.arrow.up") }
                    } else {
                        Button { shareURL = store.exportJSONFileURL() } label: {
                            Label("Prepare JSON Export", systemImage: "doc.badge.arrow.up")
                        }.disabled(store.points.isEmpty)
                    }

                    Button(role: .destructive) {
                        store.clearSurvey(); shareURL = nil
                    } label: {
                        Label("Restart RoomPlan & Clear Survey", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Probe & Survey")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Saved Maps Library Sheet (Local iPad + WLAN Pi R4)

struct SavedMapsSheet: View {
    @ObservedObject var client: WlanPiClient
    @ObservedObject var store: SurveyStore
    let onSelectMapView: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isLoadingRemote: Bool = false

    var body: some View {
        NavigationStack {
            List {
                if store.isViewingSavedMap {
                    Section {
                        Button {
                            store.clearSurvey()
                            dismiss()
                        } label: {
                            Label("Back to Live RoomPlan Scan (New Survey)", systemImage: "camera.viewfinder")
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                        }
                    }
                }

                if let status = client.syncStatus {
                    Section {
                        HStack(spacing: 8) {
                            if client.isSyncing { ProgressView() }
                            Text(status)
                                .font(.caption.bold())
                                .foregroundColor(status.contains("Synced") ? .green : (status.contains("Uploading") ? .blue : .orange))
                        }
                    }
                }

                Section("Saved on iPad (Offline — \(store.savedLocalMaps.count))") {
                    if store.savedLocalMaps.isEmpty {
                        Text("No maps saved on iPad yet. Tap 'Save' on the main bar after scanning.")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(store.savedLocalMaps) { m in
                            HStack(spacing: 10) {
                                Button {
                                    store.loadSavedMap(from: m.fileURL)
                                    onSelectMapView()
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(m.name).font(.headline).foregroundColor(.primary)
                                        Text("\(m.pointCount) RF pts • \(m.wallCount) walls • \(m.createdAt.prefix(16).replacingOccurrences(of: "T", with: " "))")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Button {
                                    Task {
                                        if let data = try? Data(contentsOf: m.fileURL),
                                           let payload = try? JSONDecoder().decode(SurveySessionExport.self, from: data) {
                                            _ = await client.uploadSurvey(payload)
                                        }
                                    }
                                } label: {
                                    Label("Sync", systemImage: "arrow.up.circle.fill")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 8).padding(.vertical, 5)
                                        .background(Color.green.opacity(0.16))
                                        .foregroundColor(.green)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.borderless)
                                .disabled(client.isSyncing)

                                ShareLink(item: m.fileURL) {
                                    Image(systemName: "square.and.arrow.up")
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.borderless)

                                Button(role: .destructive) {
                                    store.deleteLocalMap(id: m.id)
                                } label: {
                                    Image(systemName: "trash").foregroundColor(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                Section("Saved on WLAN Pi R4 (\(client.remoteSurveys.count))") {
                    if client.remoteSurveys.isEmpty && !client.isConnected {
                        Text("Connect to WLAN Pi (Bluetooth PAN / LAN) to view maps stored on Pi.")
                            .font(.caption).foregroundColor(.secondary)
                    } else if client.remoteSurveys.isEmpty {
                        Text("No maps stored on WLAN Pi yet.").font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(client.remoteSurveys) { rm in
                            HStack {
                                Button {
                                    isLoadingRemote = true
                                    Task {
                                        if let full = await client.downloadRemoteSurvey(id: rm.id) {
                                            store.applyLoadedSurvey(full)
                                            onSelectMapView()
                                            dismiss()
                                        }
                                        isLoadingRemote = false
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(rm.name).font(.headline).foregroundColor(.primary)
                                        Text("\(rm.pointCount) RF pts • \(rm.wallCount) walls")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                                .disabled(isLoadingRemote)

                                Spacer()

                                Button(role: .destructive) {
                                    Task { await client.deleteRemoteSurvey(id: rm.id) }
                                } label: {
                                    Image(systemName: "trash").foregroundColor(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saved Maps")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.refreshSavedMaps()
                        Task { await client.fetchRemoteSurveys() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                store.refreshSavedMaps()
                Task { await client.fetchRemoteSurveys() }
            }
        }
    }
}

// MARK: - Main App & Dashboard View

@main
struct LidarTestApp: App {
    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var client = WlanPiClient()
    @StateObject private var store = SurveyStore()

    @State private var layoutMode: ViewLayoutMode = .split
    @State private var showAPSheet: Bool = false
    @State private var showSettings: Bool = false
    @State private var showCalibration: Bool = false
    @State private var showSavedMaps: Bool = false
    @State private var showSavePrompt: Bool = false
    @State private var showResetConfirm: Bool = false
    @State private var saveNameInput: String = ""
    @State private var camera3DResetToken: Int = 0

    private var currentBestAP: APRecord? {
        guard let scan = client.latestScan else { return nil }
        return scan.aps.first { ap in
            (store.selectedSSID == "ALL" || ap.ssid == store.selectedSSID) &&
            (store.selectedBand == .all || ap.band == store.selectedBand.rawValue)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                topStatusBar

                if store.isViewingSavedMap {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill").foregroundColor(.yellow)
                        Text("Viewing Saved Map: \(store.surveyName)")
                            .font(.caption.bold()).foregroundColor(.white).lineLimit(1)
                        Spacer()
                        Button {
                            store.clearSurvey()
                            layoutMode = .split
                        } label: {
                            Label("New Live Scan", systemImage: "camera.viewfinder")
                                .font(.caption2.bold())
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.green).foregroundColor(.black)
                                .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.blue.opacity(0.88))
                }

                GeometryReader { geo in
                    let isWide = geo.size.width > geo.size.height
                    let scanW: CGFloat = {
                        switch layoutMode {
                        case .split: return isWide ? geo.size.width * 0.38 : geo.size.width
                        case .scan: return geo.size.width
                        case .map, .view3D: return 2
                        }
                    }()
                    let scanH: CGFloat = {
                        switch layoutMode {
                        case .split: return isWide ? geo.size.height : geo.size.height * 0.36
                        case .scan: return geo.size.height
                        case .map, .view3D: return 2
                        }
                    }()

                    ZStack(alignment: .topLeading) {
                        // Single persistent Apple RoomCaptureView keeps RoomPlan & AR tracking alive across ALL tabs!
                        RoomPlanCaptureContainer(store: store, client: client)
                            .frame(width: scanW, height: scanH)
                            .clipped()
                            .opacity((layoutMode == .split || layoutMode == .scan) ? 1.0 : 0.01)

                        if layoutMode == .split || layoutMode == .scan {
                            roomScanHUD
                                .frame(width: scanW, height: scanH, alignment: .topLeading)
                        }

                        if layoutMode == .split {
                            if isWide {
                                mapPanel
                                    .frame(width: geo.size.width * 0.62, height: geo.size.height)
                                    .offset(x: geo.size.width * 0.38, y: 0)
                            } else {
                                mapPanel
                                    .frame(width: geo.size.width, height: geo.size.height * 0.64)
                                    .offset(x: 0, y: geo.size.height * 0.36)
                            }
                        } else if layoutMode == .map {
                            mapPanel.frame(width: geo.size.width, height: geo.size.height)
                        } else if layoutMode == .view3D {
                            view3DPanel.frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                }

                bottomControlBar
            }
            .background(Color(red: 0.07, green: 0.09, blue: 0.13))

            if let toast = store.toastMessage {
                Text(toast)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.black.opacity(0.86))
                    .overlay(Capsule().stroke(Color.green.opacity(0.7), lineWidth: 1))
                    .clipShape(Capsule())
                    .padding(.top, 56)
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showAPSheet) { APListSheet(client: client, store: store) }
        .sheet(isPresented: $showSettings) { SettingsSheet(client: client, store: store) }
        .sheet(isPresented: $showCalibration) { FloorplanCalibrationSheet(store: store) }
        .sheet(isPresented: $showSavedMaps) {
            SavedMapsSheet(client: client, store: store) {
                if layoutMode == .split || layoutMode == .scan {
                    layoutMode = .map
                }
            }
        }
        .alert("Save Survey Map", isPresented: $showSavePrompt) {
            TextField("Room / Floor Name", text: $saveNameInput)
            Button("Save (iPad + Pi)") {
                if let payload = store.saveCurrentMapLocally(customName: saveNameInput) {
                    store.showToast("Saved '\(payload.name)' to iPad — Syncing to Pi...")
                    Task {
                        let ok = await client.uploadSurvey(payload)
                        if ok {
                            store.showToast(client.syncStatus ?? "Synced '\(payload.name)' to WLAN Pi!")
                        } else {
                            store.showToast(client.syncStatus ?? "Saved on iPad (Pi sync failed)")
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves \(store.points.count) RF points & \(store.walls.count) RoomPlan walls to iPad and syncs to WLAN Pi.")
        }
        .alert("Reset Map & Survey?", isPresented: $showResetConfirm) {
            Button("Reset & Rescan", role: .destructive) {
                store.clearSurvey()
                if layoutMode == .map || layoutMode == .view3D {
                    layoutMode = .split
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the current RoomPlan walls and \(store.points.count) measured points (saved maps are kept safe).")
        }
    }

    private var topStatusBar: some View {
        HStack(spacing: 8) {
            Button { showSettings = true } label: {
                HStack(spacing: 6) {
                    Circle().fill(client.isConnected ? Color.green : Color.red).frame(width: 9, height: 9)
                    Text(client.isConnected ? "WLAN Pi" : "Offline").font(.caption.bold())
                    if let scan = client.latestScan, client.isConnected {
                        Text("• \(scan.apCount) APs").font(.caption2).foregroundColor(.white.opacity(0.75))
                        if let q = scan.qbssTotalClients, q > 0 {
                            Text("• \(q) STA").font(.caption2).foregroundColor(.cyan)
                        }
                        if scan.monitor?.active == true {
                            Text("• MON").font(.system(size: 10, weight: .black)).foregroundColor(.green)
                        }
                    }
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(Color.white.opacity(0.12)).cornerRadius(8)
            }.foregroundColor(.white)

            if let ap = currentBestAP {
                Button { showAPSheet = true } label: {
                    HStack(spacing: 5) {
                        Text(String(format: "%.0f dBm", ap.rssiDbm))
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundColor(CiscoColors.color(forRSSI: ap.rssiDbm))
                        Text("\(ap.displaySSID) (Ch \(ap.channel))").font(.caption).lineLimit(1)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(Color.white.opacity(0.08)).cornerRadius(8)
                }.foregroundColor(.white)
            }

            Spacer()

            Picker("Layout", selection: $layoutMode) {
                ForEach(ViewLayoutMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
            .colorScheme(.dark)

            Button { showSavedMaps = true } label: {
                Label("Maps (\(store.savedLocalMaps.count))", systemImage: "folder.fill")
                    .font(.caption.bold())
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .background(Color.white.opacity(0.12))
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }

            Button { showCalibration = true } label: {
                Label("Calibrate", systemImage: "map.fill")
                    .font(.caption.bold())
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .background(store.calibration.isCalibrated ? Color.green.opacity(0.28) : Color.white.opacity(0.12))
                    .foregroundColor(store.calibration.isCalibrated ? .green : .white)
                    .cornerRadius(8)
            }

            Button { showAPSheet = true } label: {
                Image(systemName: "wifi").padding(7).background(Color.white.opacity(0.12)).cornerRadius(8)
            }.foregroundColor(.white)

            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill").padding(7).background(Color.white.opacity(0.12)).cornerRadius(8)
            }.foregroundColor(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(red: 0.08, green: 0.11, blue: 0.16))
    }

    private var roomScanHUD: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RoomPlan: \(store.walls.count) Walls • \(store.doors.count) Doors • \(store.windows.count) Win")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                    Text(store.roomPlanInstruction)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                    Text(String(format: "Pos (%.2f, %.2f)m • %@", store.cameraX, store.cameraZ, store.trackingStatus))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.cyan)
                }
                .padding(8)
                .background(.black.opacity(0.72))
                .cornerRadius(8)

                Spacer()

                if !store.roomScanFinalized && !store.walls.isEmpty {
                    Button {
                        store.onFinalizeRoomScan?()
                    } label: {
                        Label("Lock Room", systemImage: "lock.fill")
                            .font(.caption2.bold())
                            .padding(.horizontal, 9).padding(.vertical, 7)
                            .background(Color.green)
                            .foregroundColor(.black)
                            .cornerRadius(8)
                    }
                }
            }
            Spacer()
        }
        .padding(8)
    }

    private var filterChips: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(HeatmapMetric.allCases) { m in Button(m.rawValue) { store.selectedMetric = m } }
            } label: {
                Label(store.selectedMetric.rawValue, systemImage: "waveform.path.ecg")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(7)
            }

            Menu {
                ForEach(BandFilter.allCases) { b in Button(b.rawValue) { store.selectedBand = b } }
            } label: {
                Label(store.selectedBand.rawValue, systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(7)
            }

            Button { showAPSheet = true } label: {
                Label(store.selectedSSID == "ALL" ? "All SSIDs" : store.selectedSSID, systemImage: "line.3.horizontal.decrease.circle")
                    .font(.caption2.bold()).lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(store.selectedSSID == "ALL" ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.accentColor))
                    .foregroundColor(store.selectedSSID == "ALL" ? .primary : .white)
                    .cornerRadius(7)
            }
        }
    }

    private var mapPanel: some View {
        ZStack(alignment: .topTrailing) {
            CiscoFloorplanView(store: store)
            filterChips.padding(10)
        }
    }

    private var view3DPanel: some View {
        ZStack {
            RoomPlan3DSceneView(store: store, cameraResetToken: camera3DResetToken)

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("3D RoomPlan + Cisco RF Heatmap")
                            .font(.caption.bold())
                        Text("Drag to orbit • Pinch to zoom • 2-finger pan")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)

                    Spacer()
                    filterChips
                }
                .padding(10)

                Spacer()

                HStack(spacing: 8) {
                    Button { store.useCisco3DDomes.toggle() } label: {
                        Label(store.useCisco3DDomes ? "Cisco 3D Domes" : "Thermal Sheet", systemImage: "globe.desk.fill")
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }

                    Button { store.show3DWalls.toggle() } label: {
                        Label(store.show3DWalls ? "Walls" : "No Walls", systemImage: "building.2.fill")
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }

                    Button { store.show3DObjects.toggle() } label: {
                        Label(store.show3DObjects ? "Furniture" : "No Furn", systemImage: "chair.lounge.fill")
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }

                    Spacer()

                    // Cisco DNA 3-Zone -65 / -75 dBm Legend
                    if store.useCisco3DDomes {
                        HStack(spacing: 4) {
                            Text("dBm").font(.system(size: 9)).foregroundColor(.secondary)
                            VStack(spacing: 1) {
                                HStack(spacing: 28) {
                                    Text("-65").font(.system(size: 9, weight: .bold, design: .monospaced))
                                    Text("-75").font(.system(size: 9, weight: .bold, design: .monospaced))
                                }
                                HStack(spacing: 0) {
                                    Color(red: 0.08, green: 0.64, blue: 0.25).frame(width: 56, height: 8)
                                    Color(red: 0.96, green: 0.65, blue: 0.14).frame(width: 28, height: 8)
                                    Color(red: 0.90, green: 0.17, blue: 0.17).frame(width: 30, height: 8)
                                }.cornerRadius(2)
                            }
                            Text("dBm").font(.system(size: 9)).foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                    }

                    Button { camera3DResetToken += 1 } label: {
                        Label("Reset", systemImage: "view.3d")
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }
                }
                .padding(10)
            }
        }
    }

    private var bottomControlBar: some View {
        HStack(spacing: 8) {
            Button { store.isAutoWalkEnabled.toggle() } label: {
                Label(
                    store.isAutoWalkEnabled ? "Auto (\(String(format: "%.1fm", store.autoWalkSpacingMeters)))" : "Auto-Walk",
                    systemImage: store.isAutoWalkEnabled ? "figure.walk.circle.fill" : "figure.walk.circle"
                )
                .font(.subheadline.bold())
                .padding(.horizontal, 11).padding(.vertical, 10)
                .background(store.isAutoWalkEnabled ? Color.green : Color.white.opacity(0.12))
                .foregroundColor(store.isAutoWalkEnabled ? .black : .white)
                .cornerRadius(10)
            }
            .disabled(store.isViewingSavedMap)

            Button {
                if let scan = client.latestScan { store.recordPoint(from: scan) }
            } label: {
                Label("Measure (\(store.points.count))", systemImage: "mappin.and.ellipse")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background((client.latestScan != nil && !store.isViewingSavedMap) ? Color(red: 0.02, green: 0.48, blue: 0.84) : Color.gray.opacity(0.4))
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(client.latestScan == nil || store.isViewingSavedMap)

            Button {
                saveNameInput = store.surveyName
                showSavePrompt = true
            } label: {
                Label("Save", systemImage: "square.and.arrow.down.fill")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background((!store.points.isEmpty || !store.walls.isEmpty) ? Color(red: 0.08, green: 0.64, blue: 0.32) : Color.white.opacity(0.10))
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(store.points.isEmpty && store.walls.isEmpty)

            Button {
                showResetConfirm = true
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 11).padding(.vertical, 10)
                    .background(Color.red.opacity(0.22))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.55), lineWidth: 1))
                    .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.45))
                    .cornerRadius(10)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color(red: 0.08, green: 0.11, blue: 0.16))
    }
}
