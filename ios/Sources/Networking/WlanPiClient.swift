import Foundation
import Network

// MARK: - WLAN Pi Probe Client + Bonjour Discovery + Demo Mode

@MainActor
final class WlanPiClient: ObservableObject {
    @Published var hostAddress: String {
        didSet { UserDefaults.standard.set(hostAddress, forKey: "wlanpi_host") }
    }
    @Published var isDemoMode: Bool = false {
        didSet {
            UserDefaults.standard.set(isDemoMode, forKey: "wlanpi_demo_mode")
            if isDemoMode {
                consecutiveFailures = 0
                isConnected = true
                lastError = nil
                latencyMs = 12
                demoScanCounter += 1
                latestScan = DemoSurveyFactory.generateLiveScan(scanId: demoScanCounter)
            } else {
                isConnected = false
                latestScan = nil
            }
        }
    }
    @Published var isConnected: Bool = false
    @Published var isAutoSearching: Bool = false
    @Published var latestScan: ScanPayload?
    @Published var lastError: String?
    @Published var latencyMs: Int = 0
    @Published var discoveredHosts: [String] = []
    @Published var syncStatus: String?
    @Published var isSyncing: Bool = false
    @Published var remoteSurveys: [RemoteSurveyMeta] = []

    private var pollTask: Task<Void, Never>?
    private var browser: NWBrowser?
    private let session: URLSession
    private let syncSession: URLSession
    private var consecutiveFailures: Int = 0
    private var demoScanCounter: Int = 1000

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

        let savedDemo = UserDefaults.standard.bool(forKey: "wlanpi_demo_mode")
        if savedDemo {
            self.isDemoMode = true
        }

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
                if self.isDemoMode {
                    self.demoScanCounter += 1
                    self.latestScan = DemoSurveyFactory.generateLiveScan(scanId: self.demoScanCounter)
                    self.isConnected = true
                    self.latencyMs = Int.random(in: 8...18)
                    self.lastError = nil
                } else if !self.isSyncing {
                    await self.fetchScanOnce()
                }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
    }

    func fetchScanOnce() async {
        guard !isDemoMode else { return }
        let urlStr = "\(normalizedBaseURL(hostAddress))/api/scan"
        guard let url = URL(string: urlStr) else {
            isConnected = false
            lastError = "Invalid URL"
            return
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
        if isDemoMode { isDemoMode = false }
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
        if isDemoMode {
            syncStatus = "Demo Mode: Saved locally (Pi upload skipped)"
            return false
        }

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

    func fetchRemoteSurveys() async {
        guard !isDemoMode else { return }
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
        guard !isDemoMode else { return nil }
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
        guard !isDemoMode else { return }
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(normalizedBaseURL(hostAddress))/api/surveys/\(encoded)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        _ = try? await syncSession.data(for: req)
        await fetchRemoteSurveys()
    }
}
