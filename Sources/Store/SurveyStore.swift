import Foundation
import RoomPlan
import simd
import UIKit

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
    @Published var autoWalkWaitingForFreshScan: Bool = false
    @Published var selectedSSID: String = "ALL"
    @Published var selectedBand: BandFilter = .all
    @Published var selectedMetric: HeatmapMetric = .primaryRSSI

    // Saved Maps Library, Point Inspection & Toast Feedback
    @Published var savedLocalMaps: [SavedLocalMapMeta] = []
    @Published var isViewingSavedMap: Bool = false
    @Published var inspectedPoint: SurveyPoint?
    @Published var toastMessage: String?

    var onRestartRoomScan: (() -> Void)?
    var onFinalizeRoomScan: (() -> Void)?

    private var lastAutoWalkPos: SIMD2<Double>?
    private var lastRecordedScanId: Int?
    private var lastRecordedScanTimestamp: Double = 0

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

    // MARK: - Local Map Persistence

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

    func loadDemoSurvey() {
        let demo = DemoSurveyFactory.sampleOfficeSurvey()
        applyLoadedSurvey(demo)
        if let last = demo.points.last {
            cameraX = last.x
            cameraY = last.y
            cameraZ = last.z
            cameraYaw = last.headingRad
        }
        trackingStatus = "Demo Sample Loaded"
    }

    func applyLoadedSurvey(_ payload: SurveySessionExport) {
        self.isViewingSavedMap = true
        self.isAutoWalkEnabled = false
        self.autoWalkWaitingForFreshScan = false
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
        self.inspectedPoint = nil
        self.scene3DRevision += 1
        showToast("Loaded '\(payload.name)' (\(payload.points.count) pts)")
    }

    func deleteLocalMap(id: String) {
        if let meta = savedLocalMaps.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: meta.fileURL)
            refreshSavedMaps()
        }
    }

    // MARK: - RoomPlan & Pose Updates

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

        if !hasAutoAligned && !newWalls.isEmpty {
            autoStraightenWalls()
            hasAutoAligned = true
        }
        self.scene3DRevision += 1
    }

    func updatePose(x: Double, y: Double, z: Double, yaw: Double, tracking: String, latestScan: ScanPayload?) {
        cameraX = x
        cameraY = y
        cameraZ = z
        cameraYaw = yaw
        trackingStatus = tracking

        guard !isViewingSavedMap, isAutoWalkEnabled, let scan = latestScan, !scan.aps.isEmpty else {
            if autoWalkWaitingForFreshScan { autoWalkWaitingForFreshScan = false }
            return
        }

        let cur = SIMD2<Double>(x, z)
        let movedEnough: Bool
        if let prev = lastAutoWalkPos {
            movedEnough = simd_distance(cur, prev) >= autoWalkSpacingMeters
        } else {
            movedEnough = true
        }
        guard movedEnough else { return }

        // Stale-Scan Guard: don't stamp duplicate RF readings if the WLAN Pi hasn't delivered a fresh scan yet
        let isFreshScan: Bool
        if let lastId = lastRecordedScanId {
            isFreshScan = (scan.scanId != lastId) || (abs(scan.timestampUnix - lastRecordedScanTimestamp) > 0.5)
        } else {
            isFreshScan = true
        }

        if isFreshScan {
            autoWalkWaitingForFreshScan = false
            recordPoint(from: scan)
            lastAutoWalkPos = cur
        } else {
            autoWalkWaitingForFreshScan = true
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

    // MARK: - Floorplan Calibration

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

    // MARK: - Survey Point Recording & Editing

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
        lastRecordedScanId = scan.scanId
        lastRecordedScanTimestamp = scan.timestampUnix
        autoWalkWaitingForFreshScan = false
        scene3DRevision += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func undoLastPoint() {
        guard !points.isEmpty else { return }
        let removed = points.removeLast()
        if inspectedPoint?.id == removed.id { inspectedPoint = nil }
        if let last = points.last {
            lastAutoWalkPos = SIMD2<Double>(last.x, last.z)
        } else {
            lastAutoWalkPos = nil
        }
        lastRecordedScanId = nil
        autoWalkWaitingForFreshScan = false
        scene3DRevision += 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showToast("Undid last point (\(points.count) remaining)")
    }

    func deletePoint(id: UUID) {
        guard let idx = points.firstIndex(where: { $0.id == id }) else { return }
        points.remove(at: idx)
        if inspectedPoint?.id == id { inspectedPoint = nil }
        if let last = points.last {
            lastAutoWalkPos = SIMD2<Double>(last.x, last.z)
        } else {
            lastAutoWalkPos = nil
        }
        scene3DRevision += 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showToast("Deleted survey point (\(points.count) remaining)")
    }

    // MARK: - Metrics, Stats & RSSI-Weighted Centroid AP Estimation

    func bandInfoForCurrentMetric(_ v: Double) -> (r: Double, g: Double, b: Double, band: Int) {
        CiscoColors.bandInfo(forMetric: selectedMetric, value: v)
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

    /// Estimates physical AP positions using an RSSI-weighted centroid over the top 5 strongest observations per BSSID.
    var estimatedAPs: [EstimatedAP] {
        struct Obs {
            let ap: APRecord
            let x: Double
            let z: Double
        }

        var obsByBSSID: [String: [Obs]] = [:]
        for pt in points {
            for ap in pt.aps {
                if selectedSSID != "ALL" && ap.ssid != selectedSSID { continue }
                if selectedBand != .all && ap.band != selectedBand.rawValue { continue }
                if ap.rssiDbm < -74.0 { continue }
                obsByBSSID[ap.bssid, default: []].append(Obs(ap: ap, x: pt.x, z: pt.z))
            }
        }

        var candidates: [EstimatedAP] = []
        for (_, list) in obsByBSSID {
            let top = list.sorted { $0.ap.rssiDbm > $1.ap.rssiDbm }.prefix(5)
            guard let peak = top.first else { continue }
            let maxRssi = peak.ap.rssiDbm

            var sumW = 0.0
            var sumX = 0.0
            var sumZ = 0.0
            for o in top {
                // Linear power/amplitude weighting (15 dB drop = 10x smaller weight)
                let w = pow(10.0, (o.ap.rssiDbm - maxRssi) / 15.0)
                sumW += w
                sumX += w * o.x
                sumZ += w * o.z
            }
            let cx = sumW > 0 ? (sumX / sumW) : peak.x
            let cz = sumW > 0 ? (sumZ / sumW) : peak.z

            candidates.append(EstimatedAP(
                bssid: peak.ap.bssid,
                ssid: peak.ap.displaySSID,
                label: peak.ap.displayLabel,
                ch: peak.ap.channel,
                band: peak.ap.band,
                rssi: maxRssi,
                x: cx,
                z: cz,
                sampleCount: list.count
            ))
        }

        // Spatially merge multi-SSID virtual BSSIDs on the same physical AP (<0.75m apart)
        var dedup: [EstimatedAP] = []
        for ap in candidates.sorted(by: { $0.rssi > $1.rssi }) {
            if !dedup.contains(where: { hypot($0.x - ap.x, $0.z - ap.z) < 0.75 }) {
                dedup.append(ap)
            }
            if dedup.count >= 12 { break }
        }
        return dedup
    }

    // MARK: - Reset & Export

    func clearSurvey() {
        isViewingSavedMap = false
        isAutoWalkEnabled = false
        autoWalkWaitingForFreshScan = false
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
        inspectedPoint = nil
        lastAutoWalkPos = nil
        lastRecordedScanId = nil
        lastRecordedScanTimestamp = 0
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

    func exportPDFReportURL() -> URL? {
        SurveyReportExporter.generatePDFReport(store: self)
    }
}
