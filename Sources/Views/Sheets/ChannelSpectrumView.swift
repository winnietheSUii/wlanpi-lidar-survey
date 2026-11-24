import SwiftUI

// MARK: - 2.4 / 5 / 6 GHz Channel Overlap & CCI Spectrum Analyzer View

struct ChannelSpectrumView: View {
    let aps: [APRecord]
    @State private var band: String = "5GHz"

    private let bands = ["2.4GHz", "5GHz", "6GHz"]

    private var bandAPs: [APRecord] {
        aps.filter { $0.band == band }.sorted { $0.rssiDbm > $1.rssiDbm }
    }

    private struct ChannelStat: Identifiable {
        var id: Int { channel }
        let channel: Int
        let aps: [APRecord]
        let strongestRssi: Double
        let avgUtil: Double?
        let widths: [Int]
    }

    private var channelStats: [ChannelStat] {
        let grouped = Dictionary(grouping: bandAPs, by: { $0.channel })
        return grouped.map { ch, list in
            let strong = list.map(\.rssiDbm).max() ?? -95
            let utils = list.compactMap(\.qbssUtilPct)
            let avgU = utils.isEmpty ? nil : utils.reduce(0, +) / Double(utils.count)
            let widths = Array(Set(list.map(\.widthMhz))).sorted()
            return ChannelStat(channel: ch, aps: list, strongestRssi: strong, avgUtil: avgU, widths: widths)
        }.sorted { $0.channel < $1.channel }
    }

    private var recommendedChannel: Int? {
        let candidates: [Int]
        switch band {
        case "2.4GHz": candidates = [1, 6, 11]
        case "5GHz": candidates = [36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112, 116, 132, 136, 140, 149, 153, 157, 161]
        default: candidates = [5, 21, 37, 53, 69, 85, 101, 117, 133, 149, 165, 181, 197, 213] // 6 GHz PSC
        }
        let occupied = Dictionary(grouping: bandAPs, by: { $0.channel })
        return candidates.min { a, b in
            let countA = occupied[a]?.count ?? 0
            let countB = occupied[b]?.count ?? 0
            if countA != countB { return countA < countB }
            let rssiA = occupied[a]?.map(\.rssiDbm).max() ?? -100
            let rssiB = occupied[b]?.map(\.rssiDbm).max() ?? -100
            return rssiA < rssiB
        }
    }

    private var freqRangeMhz: (min: Double, max: Double, ticks: [(freq: Double, label: String)]) {
        switch band {
        case "2.4GHz":
            return (2400, 2486, [
                (2412, "1"), (2422, "3"), (2437, "6"), (2452, "9"), (2462, "11"), (2472, "13")
            ])
        case "5GHz":
            return (5160, 5865, [
                (5180, "36"), (5240, "48"), (5320, "64"), (5500, "100"),
                (5600, "120"), (5700, "140"), (5745, "149"), (5825, "165")
            ])
        default:
            return (5940, 7125, [
                (5975, "5"), (6135, "37"), (6295, "69"), (6455, "101"),
                (6615, "133"), (6775, "165"), (6935, "197")
            ])
        }
    }

    private let palette: [Color] = [
        .blue, .green, .orange, .purple, .pink, .cyan, .red, .yellow, .mint, .indigo
    ]

    var body: some View {
        List {
            Section {
                Picker("Band", selection: $band) {
                    ForEach(bands, id: \.self) { b in
                        let c = aps.filter { $0.band == b }.count
                        Text("\(b) (\(c))").tag(b)
                    }
                }
                .pickerStyle(.segmented)

                spectrumCanvas
                    .frame(height: 190)
                    .padding(.vertical, 4)

                if let best = recommendedChannel {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.green)
                        Text("Least congested \(band) channel:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Ch \(best)")
                            .font(.system(.caption, design: .monospaced).bold())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.green.opacity(0.18))
                            .foregroundColor(.green)
                            .cornerRadius(6)
                    }
                }
            } header: {
                Text("Channel Overlap & Width Spectrum (\(band))")
            }

            Section("Occupied Channels & CCI (\(channelStats.count))") {
                if channelStats.isEmpty {
                    Text("No APs detected on \(band) in the current scan.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(channelStats) { st in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text("Ch \(st.channel)")
                                        .font(.system(.subheadline, design: .monospaced).bold())
                                    Text(st.widths.map { "\($0)MHz" }.joined(separator: "/"))
                                        .font(.caption2)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.15))
                                        .cornerRadius(4)
                                    if st.aps.count >= 3 {
                                        Text("CCI High")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Color.orange.opacity(0.2))
                                            .foregroundColor(.orange)
                                            .cornerRadius(4)
                                    }
                                }
                                Text(st.aps.map(\.displaySSID).prefix(3).joined(separator: " • "))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(st.aps.count) AP\(st.aps.count == 1 ? "" : "s")")
                                    .font(.caption.bold())
                                    .foregroundColor(st.aps.count >= 3 ? .orange : .primary)
                                HStack(spacing: 5) {
                                    Text(String(format: "%.0f dBm", st.strongestRssi))
                                        .foregroundColor(CiscoColors.color(forRSSI: st.strongestRssi))
                                    if let u = st.avgUtil {
                                        Text(String(format: "• %.0f%%", u))
                                            .foregroundColor(u > 50 ? .red : .secondary)
                                    }
                                }
                                .font(.system(.caption2, design: .monospaced))
                            }
                        }
                    }
                }
            }
        }
    }

    private var spectrumCanvas: some View {
        let range = freqRangeMhz
        let minDbm: Double = -95
        let maxDbm: Double = -30

        return Canvas { ctx, size in
            let padL: CGFloat = 32
            let padR: CGFloat = 10
            let padT: CGFloat = 14
            let padB: CGFloat = 24
            let plotW = max(1, size.width - padL - padR)
            let plotH = max(1, size.height - padT - padB)

            func xForFreq(_ f: Double) -> CGFloat {
                let t = (f - range.min) / max(1, range.max - range.min)
                return padL + CGFloat(t) * plotW
            }
            func yForDbm(_ d: Double) -> CGFloat {
                let clamped = max(minDbm, min(maxDbm, d))
                let t = (clamped - minDbm) / (maxDbm - minDbm)
                return padT + plotH * CGFloat(1.0 - t)
            }

            // Horizontal RSSI grid lines
            for dbm in [-40.0, -55.0, -67.0, -80.0, -90.0] {
                let y = yForDbm(dbm)
                var line = Path()
                line.move(to: CGPoint(x: padL, y: y))
                line.addLine(to: CGPoint(x: size.width - padR, y: y))
                let isTarget = (dbm == -67.0)
                ctx.stroke(
                    line,
                    with: .color(isTarget ? Color.green.opacity(0.45) : Color.secondary.opacity(0.22)),
                    style: StrokeStyle(lineWidth: isTarget ? 1.2 : 0.7, dash: isTarget ? [4, 3] : [])
                )
                ctx.draw(
                    Text("\(Int(dbm))")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(isTarget ? .green : .secondary),
                    at: CGPoint(x: 15, y: y)
                )
            }

            // Channel tick labels along bottom
            for tick in range.ticks {
                let x = xForFreq(tick.freq)
                var vLine = Path()
                vLine.move(to: CGPoint(x: x, y: padT))
                vLine.addLine(to: CGPoint(x: x, y: padT + plotH))
                ctx.stroke(vLine, with: .color(Color.secondary.opacity(0.12)), lineWidth: 0.7)
                ctx.draw(
                    Text(tick.label)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary),
                    at: CGPoint(x: x, y: padT + plotH + 11)
                )
            }

            // Draw each AP channel lobe (trapezoid spanning its channel width in MHz)
            for (idx, ap) in bandAPs.enumerated() {
                let halfW = Double(max(20, ap.widthMhz)) * 0.5
                let centerF = Double(ap.freqMhz)
                let xL = xForFreq(centerF - halfW)
                let xR = xForFreq(centerF + halfW)
                let shoulder = max(4.0, (xR - xL) * 0.16)
                let yBase = padT + plotH
                let yPeak = yForDbm(ap.rssiDbm)

                var lobe = Path()
                lobe.move(to: CGPoint(x: xL, y: yBase))
                lobe.addLine(to: CGPoint(x: xL + shoulder, y: yPeak))
                lobe.addLine(to: CGPoint(x: xR - shoulder, y: yPeak))
                lobe.addLine(to: CGPoint(x: xR, y: yBase))
                lobe.closeSubpath()

                let col = palette[idx % palette.count]
                ctx.fill(lobe, with: .color(col.opacity(0.18)))
                ctx.stroke(lobe, with: .color(col.opacity(0.9)), lineWidth: 1.6)

                if idx < 6 {
                    let lbl = String(ap.displaySSID.prefix(11))
                    ctx.draw(
                        Text(lbl)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(col),
                        at: CGPoint(x: (xL + xR) * 0.5, y: max(padT + 6, yPeak - 7))
                    )
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }
}
