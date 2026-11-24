import SwiftUI

// MARK: - Probe Connection, Demo Mode, Survey Options & Export Sheet

struct SettingsSheet: View {
    @ObservedObject var client: WlanPiClient
    @ObservedObject var store: SurveyStore
    let onLoadDemoMap: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var shareJSONURL: URL?
    @State private var sharePDFURL: URL?

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
                        Button {
                            client.isDemoMode = false
                            client.hostAddress = preset.host
                        } label: {
                            HStack {
                                Text(preset.label); Spacer()
                                Text(preset.host).font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                                if !client.isDemoMode && client.hostAddress == preset.host {
                                    Image(systemName: "checkmark").foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                    HStack {
                        Text("Status"); Spacer()
                        Text(client.isDemoMode ? "Demo Probe Active (\(client.latencyMs)ms)" : (client.isConnected ? "Connected (\(client.latencyMs)ms)" : (client.lastError ?? "Disconnected")))
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

                Section("Simulator & Demo Mode") {
                    Toggle(isOn: $client.isDemoMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Demo / Mock WLAN Pi Probe")
                            Text("Simulates live multi-band enterprise APs & Monitor Mode without hardware")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    Button {
                        client.isDemoMode = true
                        store.loadDemoSurvey()
                        onLoadDemoMap()
                        dismiss()
                    } label: {
                        Label("Load Sample Office Survey (18 pts + RoomPlan)", systemImage: "sparkles.rectangle.stack.fill")
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

                    if let pdfURL = sharePDFURL {
                        ShareLink(item: pdfURL) {
                            Label("Share Executive PDF Report", systemImage: "doc.richtext.fill")
                                .foregroundColor(.blue)
                        }
                    } else {
                        Button { sharePDFURL = store.exportPDFReportURL() } label: {
                            Label("Generate Executive PDF Report", systemImage: "doc.text.magnifyingglass")
                        }.disabled(store.points.isEmpty)
                    }

                    if let url = shareJSONURL {
                        ShareLink(item: url) { Label("Share Survey JSON (\(store.points.count) pts)", systemImage: "square.and.arrow.up") }
                    } else {
                        Button { shareJSONURL = store.exportJSONFileURL() } label: {
                            Label("Prepare JSON Export", systemImage: "doc.badge.arrow.up")
                        }.disabled(store.points.isEmpty)
                    }

                    Button(role: .destructive) {
                        store.clearSurvey()
                        shareJSONURL = nil
                        sharePDFURL = nil
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
