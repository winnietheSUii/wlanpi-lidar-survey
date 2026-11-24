import Foundation
import UIKit
import CoreGraphics

// MARK: - Executive PDF Survey Report Exporter

@MainActor
enum SurveyReportExporter {
    static func generatePDFReport(store: SurveyStore) -> URL? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter Portrait
        let margin: CGFloat = 36
        let contentW = pageRect.width - margin * 2

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        // Collect unique AP inventory (strongest reading per BSSID across the entire survey)
        var bestByBSSID: [String: APRecord] = [:]
        var allWarnings: Set<String> = []
        for pt in store.points {
            for ap in pt.aps {
                if store.selectedSSID != "ALL" && ap.ssid != store.selectedSSID { continue }
                if store.selectedBand != .all && ap.band != store.selectedBand.rawValue { continue }
                if let existing = bestByBSSID[ap.bssid] {
                    if ap.rssiDbm > existing.rssiDbm { bestByBSSID[ap.bssid] = ap }
                } else {
                    bestByBSSID[ap.bssid] = ap
                }
                for w in ap.healthWarnings ?? [] {
                    allWarnings.insert("[\(ap.displaySSID) Ch \(ap.channel)] \(w)")
                }
            }
        }
        let uniqueAPs = bestByBSSID.values.sorted { $0.rssiDbm > $1.rssiDbm }
        let stats = store.coverageStats

        let data = renderer.pdfData { ctx in
            // ===================== PAGE 1: Executive Summary & 2D RF Heatmap =====================
            ctx.beginPage()
            let cg = ctx.cgContext

            // Header Banner
            let headerRect = CGRect(x: 0, y: 0, width: pageRect.width, height: 74)
            cg.setFillColor(UIColor(red: 0.06, green: 0.13, blue: 0.24, alpha: 1.0).cgColor)
            cg.fill(headerRect)

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: UIColor(white: 0.85, alpha: 1.0)
            ]
            ("WiFi LiDAR Survey — Executive RF Report" as NSString).draw(at: CGPoint(x: margin, y: 16), withAttributes: titleAttrs)

            let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
            let subtitle = "\(store.surveyName)  •  Generated \(dateStr)  •  Metric: \(store.selectedMetric.rawValue)  •  Band: \(store.selectedBand.rawValue)  •  SSID: \(store.selectedSSID)"
            (subtitle as NSString).draw(in: CGRect(x: margin, y: 42, width: contentW, height: 22), withAttributes: subAttrs)

            // KPI Summary Row (4 cards)
            let kpiY: CGFloat = 90
            let kpiH: CGFloat = 58
            let kpiGap: CGFloat = 10
            let kpiW = (contentW - kpiGap * 3) / 4

            let targetLabel = store.selectedMetric == .qbssUtil ? "Target ≤ 50%" : (store.selectedMetric == .monRetry ? "Target ≤ 15%" : "Target ≥ -67 dBm")
            let passColor: UIColor = stats.passPct >= 80 ? UIColor(red: 0.08, green: 0.64, blue: 0.30, alpha: 1) : (stats.passPct >= 50 ? .systemOrange : .systemRed)
            let unit = (store.selectedMetric == .qbssUtil || store.selectedMetric == .monRetry) ? "%" : " dBm"

            drawKPICard(cg: cg, rect: CGRect(x: margin, y: kpiY, width: kpiW, height: kpiH),
                        title: "COVERAGE PASS", value: "\(stats.passPct)%", sub: targetLabel, accent: passColor)
            drawKPICard(cg: cg, rect: CGRect(x: margin + (kpiW + kpiGap), y: kpiY, width: kpiW, height: kpiH),
                        title: "AVG / MIN", value: String(format: "%.0f / %.0f%@", stats.avg, stats.min, unit), sub: String(format: "Peak %.0f%@", stats.max, unit), accent: .systemBlue)
            drawKPICard(cg: cg, rect: CGRect(x: margin + (kpiW + kpiGap) * 2, y: kpiY, width: kpiW, height: kpiH),
                        title: "SAMPLES / APS", value: "\(store.points.count) pts", sub: "\(uniqueAPs.count) BSSIDs heard", accent: .systemIndigo)
            let dimVal = stats.roomW > 0.3 ? String(format: "%.1f × %.1f m", stats.roomW, stats.roomD) : "N/A"
            drawKPICard(cg: cg, rect: CGRect(x: margin + (kpiW + kpiGap) * 3, y: kpiY, width: kpiW, height: kpiH),
                        title: "ROOMPLAN AREA", value: dimVal, sub: "\(store.walls.count) walls • \(store.doors.count) doors", accent: .darkGray)

            // 2D Heatmap Box
            let mapY: CGFloat = kpiY + kpiH + 18
            let mapH: CGFloat = 460
            let mapRect = CGRect(x: margin, y: mapY, width: contentW, height: mapH)
            draw2DHeatmapSnapshot(cg: cg, in: mapRect, store: store)

            // Thermal Legend Bar
            let legY = mapY + mapH + 14
            drawThermalLegend(cg: cg, in: CGRect(x: margin, y: legY, width: contentW, height: 34), cutoff: store.rssiCutoffDbm)

            // Footer
            drawFooter(pageNum: 1, totalPages: 2, pageRect: pageRect, margin: margin)

            // ===================== PAGE 2: AP Inventory & RF Health Audit =====================
            ctx.beginPage()

            // Page 2 Header
            let p2TitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15, weight: .bold),
                .foregroundColor: UIColor(red: 0.06, green: 0.13, blue: 0.24, alpha: 1.0)
            ]
            ("Detected Access Point Inventory (\(uniqueAPs.count) BSSIDs)" as NSString).draw(at: CGPoint(x: margin, y: 34), withAttributes: p2TitleAttrs)

            // Table Header
            var curY: CGFloat = 62
            let cols: [(title: String, w: CGFloat)] = [
                ("SSID", 118), ("BSSID", 104), ("Band / Ch", 78),
                ("Peak", 50), ("Gen", 52), ("Security", 78), ("Util / STA", 60)
            ]
            cg.setFillColor(UIColor(red: 0.92, green: 0.94, blue: 0.97, alpha: 1.0).cgColor)
            cg.fill(CGRect(x: margin, y: curY, width: contentW, height: 22))
            let thAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .bold),
                .foregroundColor: UIColor.darkGray
            ]
            var colX = margin + 4
            for col in cols {
                (col.title as NSString).draw(at: CGPoint(x: colX, y: curY + 5), withAttributes: thAttrs)
                colX += col.w
            }
            curY += 24

            let rowFont = UIFont.systemFont(ofSize: 8.5, weight: .regular)
            let monoFont = UIFont.monospacedSystemFont(ofSize: 8, weight: .medium)
            let maxRows = min(uniqueAPs.count, 22)

            for i in 0..<maxRows {
                let ap = uniqueAPs[i]
                if i % 2 == 1 {
                    cg.setFillColor(UIColor(white: 0.97, alpha: 1.0).cgColor)
                    cg.fill(CGRect(x: margin, y: curY, width: contentW, height: 19))
                }
                var x = margin + 4
                let rowVals: [(String, UIFont, UIColor)] = [
                    (String(ap.displaySSID.prefix(20)), UIFont.systemFont(ofSize: 8.5, weight: .semibold), .black),
                    (ap.bssid, monoFont, .darkGray),
                    ("\(ap.band) Ch\(ap.channel) (\(ap.widthMhz)M)", rowFont, .black),
                    (String(format: "%.0f dBm", ap.rssiDbm), monoFont, CiscoColors.uiColor(forRSSI: ap.rssiDbm)),
                    (ap.wifiGen, rowFont, .darkGray),
                    (String(ap.security.prefix(14)), rowFont, (ap.security == "Open" || ap.security == "WEP") ? .systemRed : .black),
                    ("\(ap.qbssUtilPct.map { String(format: "%.0f%%", $0) } ?? "-") / \(ap.qbssStations.map { "\($0)" } ?? "-")", monoFont, .darkGray)
                ]
                for (idx, item) in rowVals.enumerated() {
                    let attrs: [NSAttributedString.Key: Any] = [.font: item.1, .foregroundColor: item.2]
                    (item.0 as NSString).draw(in: CGRect(x: x, y: curY + 4, width: cols[idx].w - 4, height: 14), withAttributes: attrs)
                    x += cols[idx].w
                }
                curY += 19
            }

            if uniqueAPs.count > maxRows {
                let moreAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.italicSystemFont(ofSize: 8.5), .foregroundColor: UIColor.gray]
                ("+ \(uniqueAPs.count - maxRows) additional BSSIDs omitted for brevity" as NSString).draw(at: CGPoint(x: margin, y: curY + 4), withAttributes: moreAttrs)
                curY += 20
            }

            // RF Health Audit Section
            curY = max(curY + 18, 520)
            ("RF Health Audit & Recommendations" as NSString).draw(at: CGPoint(x: margin, y: curY), withAttributes: p2TitleAttrs)
            curY += 24

            let sortedWarnings = allWarnings.sorted()
            if sortedWarnings.isEmpty {
                let okAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
                    .foregroundColor: UIColor(red: 0.08, green: 0.62, blue: 0.28, alpha: 1.0)
                ]
                ("✓ No critical RF configuration warnings detected across surveyed APs." as NSString).draw(at: CGPoint(x: margin, y: curY), withAttributes: okAttrs)
            } else {
                let warnAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 9.5, weight: .medium),
                    .foregroundColor: UIColor(red: 0.72, green: 0.34, blue: 0.02, alpha: 1.0)
                ]
                for w in sortedWarnings.prefix(10) {
                    if curY > pageRect.height - 60 { break }
                    ("• \(w)" as NSString).draw(in: CGRect(x: margin, y: curY, width: contentW, height: 16), withAttributes: warnAttrs)
                    curY += 17
                }
            }

            drawFooter(pageNum: 2, totalPages: 2, pageRect: pageRect, margin: margin)
        }

        let safeName = store.surveyId.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName.isEmpty ? "survey" : safeName)_report.pdf")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - PDF Drawing Helpers

    private static func drawKPICard(cg: CGContext, rect: CGRect, title: String, value: String, sub: String, accent: UIColor) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 6)
        cg.setFillColor(UIColor(red: 0.965, green: 0.975, blue: 0.99, alpha: 1.0).cgColor)
        cg.addPath(path.cgPath)
        cg.fillPath()
        cg.setStrokeColor(UIColor(white: 0.85, alpha: 1.0).cgColor)
        cg.setLineWidth(0.8)
        cg.addPath(path.cgPath)
        cg.strokePath()

        let tAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 7.5, weight: .bold), .foregroundColor: UIColor.gray]
        let vAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 13.5, weight: .heavy), .foregroundColor: accent]
        let sAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8, weight: .regular), .foregroundColor: UIColor.darkGray]

        (title as NSString).draw(at: CGPoint(x: rect.minX + 8, y: rect.minY + 7), withAttributes: tAttrs)
        (value as NSString).draw(in: CGRect(x: rect.minX + 8, y: rect.minY + 20, width: rect.width - 14, height: 18), withAttributes: vAttrs)
        (sub as NSString).draw(in: CGRect(x: rect.minX + 8, y: rect.minY + 40, width: rect.width - 14, height: 14), withAttributes: sAttrs)
    }

    private static func draw2DHeatmapSnapshot(cg: CGContext, in rect: CGRect, store: SurveyStore) {
        cg.saveGState()
        let border = UIBezierPath(roundedRect: rect, cornerRadius: 6)
        cg.setFillColor(UIColor(red: 0.955, green: 0.968, blue: 0.985, alpha: 1.0).cgColor)
        cg.addPath(border.cgPath)
        cg.fillPath()
        cg.addPath(border.cgPath)
        cg.clip()

        let samples: [HeatmapSample] = store.points.compactMap { pt in
            guard let v = store.metricValue(for: pt) else { return nil }
            return HeatmapSample(x: pt.x, z: pt.z, val: v)
        }

        if let img = store.floorplanImage, store.calibration.isCalibrated {
            // Fit floorplan inside rect
            let pad: CGFloat = 14
            let avail = rect.insetBy(dx: pad, dy: pad)
            let imgAsp = img.size.width / max(1, img.size.height)
            let boxAsp = avail.width / max(1, avail.height)
            let drawW = imgAsp > boxAsp ? avail.width : avail.height * imgAsp
            let drawH = imgAsp > boxAsp ? avail.width / imgAsp : avail.height
            let drawRect = CGRect(x: avail.midX - drawW * 0.5, y: avail.midY - drawH * 0.5, width: drawW, height: drawH)
            img.draw(in: drawRect)

            if !samples.isEmpty {
                let bmpW = 300
                let bmpH = max(120, Int(Double(bmpW) * Double(drawH / max(1, drawW))))
                let spec = HeatmapRenderSpec(
                    mode: .calibrated(calibration: store.calibration),
                    widthPx: bmpW, heightPx: bmpH,
                    samples: samples, metric: store.selectedMetric,
                    rssiCutoffDbm: store.rssiCutoffDbm,
                    floorPolygons: [], clipToRoom: false
                )
                if let cgImg = CiscoHeatmapRenderer.renderContourImage(spec: spec) {
                    UIImage(cgImage: cgImg).draw(in: drawRect)
                }
            }

            let cal = store.calibration
            func toPt(_ wx: Double, _ wz: Double) -> CGPoint {
                let uv = cal.worldToNormalized(wx, wz)
                return CGPoint(x: drawRect.minX + uv.x * drawRect.width, y: drawRect.minY + uv.y * drawRect.height)
            }
            if store.showRoomWallsOnFloorplan { drawSurfacesPDF(cg: cg, store: store, toPt: toPt) }
            drawPointsAndAPsPDF(cg: cg, store: store, samples: samples, toPt: toPt)
        } else {
            // RoomPlan CAD map
            let rot = store.mapRotationDeg * .pi / 180.0
            let cr = cos(rot), sr = sin(rot)
            func rotW(_ x: Double, _ z: Double) -> (Double, Double) { (x * cr - z * sr, x * sr + z * cr) }

            var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
            var minZ = Double.greatestFiniteMagnitude, maxZ = -Double.greatestFiniteMagnitude
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
            if minX > maxX { minX = -5; maxX = 5; minZ = -5; maxZ = 5 }

            let spanX = max(4.0, maxX - minX)
            let spanZ = max(4.0, maxZ - minZ)
            let scale = min((rect.width - 36) / spanX, (rect.height - 36) / spanZ)
            let ox = rect.midX - ((minX + maxX) * 0.5) * scale
            let oz = rect.midY - ((minZ + maxZ) * 0.5) * scale

            func toPt(_ wx: Double, _ wz: Double) -> CGPoint {
                let p = rotW(wx, wz)
                return CGPoint(x: p.0 * scale + ox, y: p.1 * scale + oz)
            }

            // Floor polygons
            for poly in store.floorPolygons where poly.count >= 3 {
                cg.beginPath()
                for (i, pt) in poly.enumerated() {
                    let sp = toPt(pt.x, pt.z)
                    if i == 0 { cg.move(to: sp) } else { cg.addLine(to: sp) }
                }
                cg.closePath()
                cg.setFillColor(UIColor.white.cgColor)
                cg.fillPath()
            }

            // High-res contour heatmap
            if let bounds = CiscoHeatmapRenderer.stableRoomPlanBounds(samples: samples, walls: store.walls, rotationDeg: store.mapRotationDeg) {
                let bmpW = 300
                let bmpH = max(120, Int(Double(bmpW) * (bounds.height / max(0.1, bounds.width))))
                let spec = HeatmapRenderSpec(
                    mode: .roomPlan(bounds: bounds, rotationDeg: store.mapRotationDeg),
                    widthPx: bmpW, heightPx: bmpH,
                    samples: samples, metric: store.selectedMetric,
                    rssiCutoffDbm: store.rssiCutoffDbm,
                    floorPolygons: store.floorPolygons, clipToRoom: store.clipHeatmapToRoom
                )
                if let cgImg = CiscoHeatmapRenderer.renderContourImage(spec: spec) {
                    let tl = CGPoint(x: bounds.minRX * scale + ox, y: bounds.minRZ * scale + oz)
                    let br = CGPoint(x: bounds.maxRX * scale + ox, y: bounds.maxRZ * scale + oz)
                    let hmRect = CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)
                    UIImage(cgImage: cgImg).draw(in: hmRect)
                }
            }

            drawSurfacesPDF(cg: cg, store: store, toPt: toPt)
            drawPointsAndAPsPDF(cg: cg, store: store, samples: samples, toPt: toPt)
        }

        cg.restoreGState()

        cg.setStrokeColor(UIColor(white: 0.78, alpha: 1.0).cgColor)
        cg.setLineWidth(1.0)
        cg.addPath(border.cgPath)
        cg.strokePath()
    }

    private static func drawSurfacesPDF(cg: CGContext, store: SurveyStore, toPt: (Double, Double) -> CGPoint) {
        if !store.walls.isEmpty {
            cg.setStrokeColor(UIColor(red: 0.11, green: 0.16, blue: 0.24, alpha: 1).cgColor)
            cg.setLineWidth(3.2)
            cg.setLineCap(.round)
            for w in store.walls {
                cg.move(to: toPt(w.x1, w.z1))
                cg.addLine(to: toPt(w.x2, w.z2))
            }
            cg.strokePath()
        }
        if !store.windows.isEmpty {
            cg.setStrokeColor(UIColor(red: 0.08, green: 0.62, blue: 0.95, alpha: 1).cgColor)
            cg.setLineWidth(3.2)
            for w in store.windows {
                cg.move(to: toPt(w.x1, w.z1))
                cg.addLine(to: toPt(w.x2, w.z2))
            }
            cg.strokePath()
        }
        if !store.doors.isEmpty {
            cg.setStrokeColor(UIColor(red: 0.10, green: 0.72, blue: 0.45, alpha: 1).cgColor)
            cg.setLineWidth(2.8)
            cg.setLineDash(phase: 0, lengths: [5, 3])
            for d in store.doors {
                cg.move(to: toPt(d.x1, d.z1))
                cg.addLine(to: toPt(d.x2, d.z2))
            }
            cg.strokePath()
            cg.setLineDash(phase: 0, lengths: [])
        }
    }

    private static func drawPointsAndAPsPDF(cg: CGContext, store: SurveyStore, samples: [HeatmapSample], toPt: (Double, Double) -> CGPoint) {
        if store.points.count > 1 {
            cg.setStrokeColor(UIColor(red: 0.04, green: 0.46, blue: 0.85, alpha: 0.65).cgColor)
            cg.setLineWidth(1.4)
            cg.setLineDash(phase: 0, lengths: [4, 3])
            for (i, pt) in store.points.enumerated() {
                let sp = toPt(pt.x, pt.z)
                if i == 0 { cg.move(to: sp) } else { cg.addLine(to: sp) }
            }
            cg.strokePath()
            cg.setLineDash(phase: 0, lengths: [])
        }

        for s in samples {
            let p = toPt(s.x, s.z)
            let c = store.bandInfoForCurrentMetric(s.val)
            let col = UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9))
            cg.setStrokeColor(col.cgColor)
            cg.setLineWidth(2.0)
            cg.strokeEllipse(in: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9))
        }

        if store.showEstimatedAPs {
            for ap in store.estimatedAPs {
                let p = toPt(ap.x, ap.z)
                cg.setFillColor(UIColor(red: 0.25, green: 0.30, blue: 0.38, alpha: 1).cgColor)
                cg.fillEllipse(in: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
                cg.setStrokeColor(UIColor.white.cgColor)
                cg.setLineWidth(1.5)
                cg.strokeEllipse(in: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))

                let tag = "\(ap.label.prefix(14)) (Ch\(ap.ch))"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 7.5, weight: .bold),
                    .foregroundColor: UIColor.black
                ]
                let sz = (tag as NSString).size(withAttributes: attrs)
                let box = CGRect(x: p.x + 8, y: p.y - sz.height * 0.5 - 2, width: sz.width + 8, height: sz.height + 4)
                cg.setFillColor(UIColor.white.withAlphaComponent(0.92).cgColor)
                cg.fill(box)
                cg.setStrokeColor(UIColor.black.cgColor)
                cg.setLineWidth(0.7)
                cg.stroke(box)
                (tag as NSString).draw(at: CGPoint(x: box.minX + 4, y: box.minY + 2), withAttributes: attrs)
            }
        }
    }

    private static func drawThermalLegend(cg: CGContext, in rect: CGRect, cutoff: Double) {
        let lblAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8.5, weight: .bold), .foregroundColor: UIColor.darkGray]
        ("Cisco Prime Thermal Scale (Cutoff \(Int(cutoff)) dBm)" as NSString).draw(at: CGPoint(x: rect.minX, y: rect.minY), withAttributes: lblAttrs)

        let barRect = CGRect(x: rect.minX, y: rect.minY + 14, width: rect.width, height: 10)
        let steps = 60
        let segW = barRect.width / CGFloat(steps)
        for i in 0..<steps {
            let dbm = -35.0 - (Double(i) / Double(steps - 1)) * 55.0
            let c = CiscoColors.primeThermalRGB(forRSSI: dbm)
            cg.setFillColor(UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1).cgColor)
            cg.fill(CGRect(x: barRect.minX + CGFloat(i) * segW, y: barRect.minY, width: segW + 0.5, height: barRect.height))
        }
        cg.setStrokeColor(UIColor.darkGray.cgColor)
        cg.setLineWidth(0.6)
        cg.stroke(barRect)

        let tickAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 7.5, weight: .semibold), .foregroundColor: UIColor.gray]
        let ticks = ["-35 dBm", "-50 dBm", "-67 dBm (Target)", "-80 dBm", "-90 dBm"]
        for (i, t) in ticks.enumerated() {
            let frac = CGFloat(i) / CGFloat(ticks.count - 1)
            let x = barRect.minX + frac * (barRect.width - 60)
            (t as NSString).draw(at: CGPoint(x: x, y: barRect.maxY + 2), withAttributes: tickAttrs)
        }
    }

    private static func drawFooter(pageNum: Int, totalPages: Int, pageRect: CGRect, margin: CGFloat) {
        let fAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.gray]
        ("Generated by WiFi LiDAR Survey + WLAN Pi R4 Probe" as NSString).draw(at: CGPoint(x: margin, y: pageRect.height - 26), withAttributes: fAttrs)
        let pStr = "Page \(pageNum) of \(totalPages)" as NSString
        let sz = pStr.size(withAttributes: fAttrs)
        pStr.draw(at: CGPoint(x: pageRect.width - margin - sz.width, y: pageRect.height - 26), withAttributes: fAttrs)
    }
}
