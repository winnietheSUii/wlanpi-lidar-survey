import SwiftUI

// MARK: - Saved Maps Library Sheet (Local iPad + WLAN Pi R4)

struct SavedMapsSheet: View {
    @ObservedObject var client: WlanPiClient
    @ObservedObject var store: SurveyStore
    let onSelectMapView: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isLoadingRemote: Bool = false
    @State private var pdfReportURL: URL?

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

                        if let url = pdfReportURL {
                            ShareLink(item: url) {
                                Label("Share PDF Report for '\(store.surveyName)'", systemImage: "doc.richtext.fill")
                            }
                        } else if !store.points.isEmpty {
                            Button {
                                pdfReportURL = store.exportPDFReportURL()
                            } label: {
                                Label("Export Current Map as PDF Report", systemImage: "doc.text.magnifyingglass")
                            }
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
