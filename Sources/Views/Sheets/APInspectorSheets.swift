import SwiftUI

// MARK: - AP Deep Inspector, Client Row & RF Inspector Sheet (APs / Channels / Clients)

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
    @State private var selectedTab: Int = 0 // 0 = APs, 1 = Channels & CCI, 2 = Clients & Vendors
    @State private var inspectedAP: APRecord? = nil

    /// Falls back to APs from the loaded/saved survey when offline
    private var activeAPs: [APRecord] {
        if let live = client.latestScan?.aps, !live.isEmpty {
            return live
        }
        var bestByBSSID: [String: APRecord] = [:]
        for pt in store.points {
            for ap in pt.aps {
                if let cur = bestByBSSID[ap.bssid] {
                    if ap.rssiDbm > cur.rssiDbm { bestByBSSID[ap.bssid] = ap }
                } else {
                    bestByBSSID[ap.bssid] = ap
                }
            }
        }
        return bestByBSSID.values.sorted { $0.rssiDbm > $1.rssiDbm }
    }

    private var filteredAPs: [APRecord] {
        activeAPs.filter { ap in
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
        activeAPs
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
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        kpiPill(title: "APs", value: "\(activeAPs.count)", color: .blue)
                        kpiPill(title: "QBSS Clients (AP)", value: "\(client.latestScan?.qbssTotalClients ?? qbssReportingAPs.compactMap(\.qbssStations).reduce(0, +))", color: .green)
                        kpiPill(
                            title: "Sniffed (Mon)",
                            value: client.latestScan?.monitor?.active == true ? "\(client.latestScan?.monitor?.uniqueClients10s ?? 0)" : "OFF",
                            color: client.latestScan?.monitor?.active == true ? .purple : .secondary
                        )
                    }
                    Picker("View", selection: $selectedTab) {
                        Text("APs (\(filteredAPs.count))").tag(0)
                        Text("Channels").tag(1)
                        Text("Clients").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                if selectedTab == 0 {
                    apListBody
                } else if selectedTab == 1 {
                    ChannelSpectrumView(aps: activeAPs)
                } else {
                    clientListBody
                }
            }
            .searchable(text: $search, prompt: selectedTab == 2 ? "Filter Client MAC, Vendor, AP" : "Filter SSID, BSSID, Vendor, Model")
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

            Section("APs Reporting QBSS Clients (\(qbssReportingAPs.count) APs • รวม \(client.latestScan?.qbssTotalClients ?? qbssReportingAPs.compactMap(\.qbssStations).reduce(0, +)) เครื่อง)") {
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
