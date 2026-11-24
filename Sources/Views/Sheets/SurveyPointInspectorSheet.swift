import SwiftUI

// MARK: - Tap-to-Inspect Individual Survey Point Sheet

struct SurveyPointInspectorSheet: View {
    let point: SurveyPoint
    @ObservedObject var store: SurveyStore
    @Environment(\.dismiss) private var dismiss
    @State private var inspectedAP: APRecord?

    private var sortedAPs: [APRecord] {
        point.aps.sorted { $0.rssiDbm > $1.rssiDbm }
    }

    private var formattedTime: String {
        let dt = Date(timeIntervalSince1970: point.timestamp)
        return DateFormatter.localizedString(from: dt, dateStyle: .none, timeStyle: .medium)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Measurement Point") {
                    HStack {
                        Text("Position (X, Z)")
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "(%.2f m, %.2f m)", point.x, point.z))
                            .font(.system(.caption, design: .monospaced).bold())
                    }
                    HStack {
                        Text("Scan ID / Time")
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text("#\(point.scanId) • \(formattedTime)")
                            .font(.system(.caption, design: .monospaced))
                    }
                    if let mv = store.metricValue(for: point) {
                        HStack {
                            Text("Active Metric (\(store.selectedMetric.rawValue))")
                                .font(.caption).foregroundColor(.secondary)
                            Spacer()
                            let unit = (store.selectedMetric == .qbssUtil || store.selectedMetric == .monRetry) ? "%" : " dBm"
                            Text(String(format: "%.1f%@", mv, unit))
                                .font(.system(.caption, design: .monospaced).bold())
                                .foregroundColor(CiscoColors.color(forRSSI: mv))
                        }
                    }
                }

                Section("Heard Access Points (\(sortedAPs.count))") {
                    ForEach(sortedAPs) { ap in
                        Button {
                            inspectedAP = ap
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ap.displaySSID)
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                    Text("\(ap.bssid) • \(ap.band) Ch \(ap.channel) (\(ap.widthMhz) MHz)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    HStack(spacing: 6) {
                                        Text(ap.wifiGen)
                                        if let util = ap.qbssUtilPct {
                                            Text("• Util \(String(format: "%.0f%%", util))")
                                        }
                                        if let sta = ap.qbssStations {
                                            Text("• \(sta) STA")
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(String(format: "%.0f dBm", ap.rssiDbm))
                                    .font(.system(.subheadline, design: .monospaced).bold())
                                    .foregroundColor(CiscoColors.color(forRSSI: ap.rssiDbm))
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        store.deletePoint(id: point.id)
                        dismiss()
                    } label: {
                        Label("Delete This Survey Point", systemImage: "trash.fill")
                    }
                }
            }
            .navigationTitle("Point Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $inspectedAP) { ap in
                APDeepInspectorSheet(ap: ap, monitorActive: (ap.monFrames ?? 0) > 0) { ssid in
                    store.selectedSSID = ssid
                    dismiss()
                }
            }
        }
    }
}
