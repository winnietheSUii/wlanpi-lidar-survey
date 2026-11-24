import SwiftUI

// MARK: - Main Dashboard View

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
        .sheet(isPresented: $showSettings) {
            SettingsSheet(client: client, store: store) {
                if layoutMode == .split || layoutMode == .scan {
                    layoutMode = .map
                }
            }
        }
        .sheet(isPresented: $showCalibration) { FloorplanCalibrationSheet(store: store) }
        .sheet(isPresented: $showSavedMaps) {
            SavedMapsSheet(client: client, store: store) {
                if layoutMode == .split || layoutMode == .scan {
                    layoutMode = .map
                }
            }
        }
        .sheet(item: $store.inspectedPoint) { pt in
            SurveyPointInspectorSheet(point: pt, store: store)
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
                    Circle().fill(client.isConnected ? (client.isDemoMode ? Color.cyan : Color.green) : Color.red).frame(width: 9, height: 9)
                    Text(client.isDemoMode ? "DEMO" : (client.isConnected ? "WLAN Pi" : "Offline")).font(.caption.bold())
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
                .background(client.isDemoMode ? Color.cyan.opacity(0.20) : Color.white.opacity(0.12)).cornerRadius(8)
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

                if !store.roomScanFinalized && !store.walls.isEmpty && store.roomPlanSupported {
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
                    store.isAutoWalkEnabled
                        ? (store.autoWalkWaitingForFreshScan ? "Waiting RF..." : "Auto (\(String(format: "%.1fm", store.autoWalkSpacingMeters)))")
                        : "Auto-Walk",
                    systemImage: store.isAutoWalkEnabled ? "figure.walk.circle.fill" : "figure.walk.circle"
                )
                .font(.subheadline.bold())
                .padding(.horizontal, 11).padding(.vertical, 10)
                .background(store.isAutoWalkEnabled ? (store.autoWalkWaitingForFreshScan ? Color.orange : Color.green) : Color.white.opacity(0.12))
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
                store.undoLastPoint()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 12).padding(.vertical, 11)
                    .background(!store.points.isEmpty ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
                    .foregroundColor(!store.points.isEmpty ? .white : .gray)
                    .cornerRadius(10)
            }
            .disabled(store.points.isEmpty)
            .accessibilityLabel("Undo Last Survey Point")

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
