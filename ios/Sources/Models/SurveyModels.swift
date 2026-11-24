import Foundation
import CoreGraphics

// MARK: - Data Models (WLAN Pi Hybrid Dual-Radio JSON Contract)

struct ClientRecord: Codable, Identifiable, Hashable, Sendable {
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

struct APRecord: Codable, Identifiable, Hashable, Sendable {
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

struct MonitorSummary: Codable, Sendable {
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

struct ScanPayload: Codable, Sendable {
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

struct SurveyPoint: Codable, Identifiable, Sendable {
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

struct RoomSurfaceSegment: Codable, Hashable, Sendable {
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

struct RoomPoint2D: Codable, Hashable, Sendable {
    let x: Double
    let z: Double
}

struct RoomObjectBox: Codable, Hashable, Sendable {
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
struct FloorplanCalibration: Codable, Equatable, Sendable {
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

struct SurveySessionExport: Codable, Sendable {
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

struct SavedLocalMapMeta: Identifiable, Sendable {
    let id: String
    let name: String
    let createdAt: String
    let pointCount: Int
    let wallCount: Int
    let fileURL: URL
}

struct EstimatedAP: Identifiable, Sendable {
    var id: String { bssid }
    let bssid: String
    let ssid: String
    let label: String
    let ch: Int
    let band: String
    let rssi: Double
    let x: Double
    let z: Double
    let sampleCount: Int
}

enum HeatmapMetric: String, CaseIterable, Identifiable, Sendable {
    case primaryRSSI = "Primary RSSI"
    case secondaryRSSI = "Secondary RSSI"
    case apOverlap = "AP Overlap"
    case qbssUtil = "Channel Util %"
    case monRetry = "Retry % (Mon)"

    var id: String { rawValue }
}

enum BandFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case ghz24 = "2.4GHz"
    case ghz5 = "5GHz"
    case ghz6 = "6GHz"

    var id: String { rawValue }
}

enum ViewLayoutMode: String, CaseIterable, Identifiable, Sendable {
    case split = "Split"
    case map = "2D Cisco"
    case view3D = "3D Room"
    case scan = "RoomScan"

    var id: String { rawValue }
}

enum CalibrationPickTarget: Equatable, Sendable {
    case none, pickA, pickB, reAnchor
}
