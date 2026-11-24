import SwiftUI
import UIKit

// MARK: - Cisco DNA Center Style 2D CAD Floorplan & Async-Cached Heatmap View

struct CiscoFloorplanView: View {
    @ObservedObject var store: SurveyStore
    @StateObject private var heatmapCache = HeatmapCacheController()

    @State private var zoom: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0
    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero

    private struct RoomProjection {
        let rotRad: Double
        let cr: Double
        let sr: Double
        let scale: Double
        let ox: Double
        let oz: Double

        func rotW(_ x: Double, _ z: Double) -> (Double, Double) {
            (x * cr - z * sr, x * sr + z * cr)
        }

        func toScreen(_ wx: Double, _ wz: Double) -> CGPoint {
            let p = rotW(wx, wz)
            return CGPoint(x: p.0 * scale + ox, y: p.1 * scale + oz)
        }

        func rotatedToScreen(_ rx: Double, _ rz: Double) -> CGPoint {
            CGPoint(x: rx * scale + ox, y: rz * scale + oz)
        }
    }

    private func computeRoomProjection(in size: CGSize) -> RoomProjection {
        let rot = store.mapRotationDeg * .pi / 180.0
        let cr = cos(rot), sr = sin(rot)
        func rotW(_ x: Double, _ z: Double) -> (Double, Double) { (x * cr - z * sr, x * sr + z * cr) }

        let camR = rotW(store.cameraX, store.cameraZ)
        var minX = camR.0 - 4.0, maxX = camR.0 + 4.0
        var minZ = camR.1 - 4.0, maxZ = camR.1 + 4.0
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

        let spanX = max(5.0, maxX - minX)
        let spanZ = max(5.0, maxZ - minZ)
        let scale = min((size.width - 50) / spanX, (size.height - 80) / spanZ) * zoom
        let ox = size.width * 0.5 + pan.width - ((minX + maxX) * 0.5) * scale
        let oz = size.height * 0.5 + pan.height - ((minZ + maxZ) * 0.5) * scale
        return RoomProjection(rotRad: rot, cr: cr, sr: sr, scale: scale, ox: ox, oz: oz)
    }

    private func fittedImageRect(in size: CGSize, image: UIImage) -> CGRect {
        let pad: CGFloat = 20
        let availW = max(1, size.width - pad * 2)
        let availH = max(1, size.height - pad * 2)
        let imgAspect = image.size.width / max(1, image.size.height)
        let viewAspect = availW / availH
        let baseW = imgAspect > viewAspect ? availW : availH * imgAspect
        let baseH = imgAspect > viewAspect ? availW / imgAspect : availH
        let w = baseW * zoom, h = baseH * zoom
        return CGRect(x: (size.width - w) * 0.5 + pan.width, y: (size.height - h) * 0.5 + pan.height, width: w, height: h)
    }

    private var currentSamples: [HeatmapSample] {
        store.points.compactMap { pt in
            guard let v = store.metricValue(for: pt) else { return nil }
            return HeatmapSample(x: pt.x, z: pt.z, val: v)
        }
    }

    private var currentHeatmapSpec: HeatmapRenderSpec? {
        let samples = currentSamples
        guard !samples.isEmpty else { return nil }

        if let img = store.floorplanImage {
            guard store.calibration.isCalibrated else { return nil }
            let bmpW = 200
            let aspect = img.size.height / max(1, img.size.width)
            let bmpH = max(90, min(320, Int(Double(bmpW) * Double(aspect))))
            return HeatmapRenderSpec(
                mode: .calibrated(calibration: store.calibration),
                widthPx: bmpW,
                heightPx: bmpH,
                samples: samples,
                metric: store.selectedMetric,
                rssiCutoffDbm: store.rssiCutoffDbm,
                floorPolygons: [],
                clipToRoom: false
            )
        } else {
            guard let bounds = CiscoHeatmapRenderer.stableRoomPlanBounds(
                samples: samples,
                walls: store.walls,
                rotationDeg: store.mapRotationDeg
            ) else { return nil }
            let bmpW = 200
            let aspect = bounds.height / max(0.1, bounds.width)
            let bmpH = max(90, min(320, Int(Double(bmpW) * aspect)))
            return HeatmapRenderSpec(
                mode: .roomPlan(bounds: bounds, rotationDeg: store.mapRotationDeg),
                widthPx: bmpW,
                heightPx: bmpH,
                samples: samples,
                metric: store.selectedMetric,
                rssiCutoffDbm: store.rssiCutoffDbm,
                floorPolygons: store.floorPolygons,
                clipToRoom: store.clipHeatmapToRoom
            )
        }
    }

    private func handleTap(at location: CGPoint, in size: CGSize) {
        // 1. Calibration picking mode
        if store.pickTarget != .none, let img = store.floorplanImage {
            let rect = fittedImageRect(in: size, image: img)
            let u = Double((location.x - rect.minX) / max(1, rect.width))
            let v = Double((location.y - rect.minY) / max(1, rect.height))
            if u >= 0 && u <= 1 && v >= 0 && v <= 1 {
                store.handleFloorplanTap(normalizedU: u, normalizedV: v)
            }
            return
        }

        // 2. Tap-to-inspect nearest survey point
        guard !store.points.isEmpty else { return }
        let toScreen: (Double, Double) -> CGPoint
        if let img = store.floorplanImage {
            guard store.calibration.isCalibrated else { return }
            let rect = fittedImageRect(in: size, image: img)
            let cal = store.calibration
            toScreen = { wx, wz in
                let uv = cal.worldToNormalized(wx, wz)
                return CGPoint(x: rect.minX + uv.x * rect.width, y: rect.minY + uv.y * rect.height)
            }
        } else {
            let proj = computeRoomProjection(in: size)
            toScreen = { proj.toScreen($0, $1) }
        }

        var bestPt: SurveyPoint?
        var bestDist: CGFloat = 26.0
        for pt in store.points {
            let sp = toScreen(pt.x, pt.z)
            let d = hypot(sp.x - location.x, sp.y - location.y)
            if d < bestDist {
                bestDist = d
                bestPt = pt
            }
        }
        if let hit = bestPt {
            store.inspectedPoint = hit
        }
    }

    var body: some View {
        let bgCol = store.ciscoLightTheme ? Color(red: 0.955, green: 0.968, blue: 0.985) : Color(red: 0.05, green: 0.07, blue: 0.10)
        let spec = currentHeatmapSpec

        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                Canvas { ctx, size in
                    if let img = store.floorplanImage {
                        drawCalibratedCiscoMap(ctx: ctx, size: size, image: img)
                    } else {
                        drawRoomPlanCiscoMap(ctx: ctx, size: size)
                    }
                }
                .background(bgCol)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    handleTap(at: location, in: geo.size)
                }
                .gesture(
                    MagnificationGesture()
                        .onChanged { val in zoom = max(0.35, min(6.0, lastZoom * val)) }
                        .onEnded { _ in lastZoom = zoom }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { val in
                            pan = CGSize(width: lastPan.width + val.translation.width, height: lastPan.height + val.translation.height)
                        }
                        .onEnded { _ in lastPan = pan }
                )

                // Top-left Cisco Coverage KPI Summary Card
                VStack(alignment: .leading, spacing: 6) {
                    ciscoStatsCard
                    if store.pickTarget != .none {
                        HStack(spacing: 8) {
                            Image(systemName: "scope").foregroundColor(.yellow)
                            Text(calibrationPromptText).font(.caption.bold()).foregroundColor(.white)
                            Button("Cancel") { store.pickTarget = .none }.font(.caption.bold()).foregroundColor(.yellow)
                        }
                        .padding(9)
                        .background(Color.blue.opacity(0.92))
                        .cornerRadius(8)
                    }
                    Spacer()
                }
                .padding(10)

                // Bottom Cisco Discrete Contour Legend + Tools
                HStack(alignment: .bottom, spacing: 8) {
                    ciscoDiscreteLegend

                    Spacer()

                    Button {
                        store.ciscoLightTheme.toggle()
                    } label: {
                        Image(systemName: store.ciscoLightTheme ? "moon.fill" : "sun.max.fill")
                            .font(.caption.bold())
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }

                    if store.floorplanImage == nil {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { store.autoStraightenWalls() }
                        } label: {
                            Label("Align", systemImage: "rotate.right")
                                .font(.caption.bold())
                                .padding(.horizontal, 9).padding(.vertical, 7)
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                        }
                    } else if store.calibration.isCalibrated {
                        Button { store.pickTarget = .reAnchor } label: {
                            Label("Re-Anchor", systemImage: "pin.fill")
                                .font(.caption.bold())
                                .padding(.horizontal, 9).padding(.vertical, 7)
                                .background(Color.orange)
                                .foregroundColor(.black)
                                .cornerRadius(8)
                        }
                    }

                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            zoom = 1.0; lastZoom = 1.0; pan = .zero; lastPan = .zero
                        }
                    } label: {
                        Label("Fit", systemImage: "viewfinder")
                            .font(.caption.bold())
                            .padding(.horizontal, 9).padding(.vertical, 7)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }
                }
                .padding(10)
            }
        }
        .onAppear {
            heatmapCache.update(spec: spec)
        }
        .onChange(of: spec) { _, newSpec in
            heatmapCache.update(spec: newSpec)
        }
    }

    private var ciscoStatsCard: some View {
        let st = store.coverageStats
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.selectedMetric == .qbssUtil ? "Target ≤ 50% Util" : (store.selectedMetric == .monRetry ? "Target ≤ 15% Retry" : "Cisco Target ≥ -67 dBm"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    Text(store.points.isEmpty ? "No Samples" : "Pass \(st.passPct)%")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundColor(st.passPct >= 80 ? .green : (st.passPct >= 50 ? .orange : .red))
                    if !store.points.isEmpty {
                        Text(String(format: "Avg %.0f | Min %.0f", st.avg, st.min))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                }
            }
            if st.roomW > 0.5 {
                Divider().frame(height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("RoomPlan Size").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                    Text(String(format: "%.1f × %.1f m", st.roomW, st.roomD))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .cornerRadius(9)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    private var ciscoDiscreteLegend: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Cisco Prime Thermal").font(.system(size: 9, weight: .bold))
                Spacer()
                Menu {
                    Button("Cutoff -75 dBm") { store.rssiCutoffDbm = -75 }
                    Button("Cutoff -80 dBm") { store.rssiCutoffDbm = -80 }
                    Button("Cutoff -85 dBm") { store.rssiCutoffDbm = -85 }
                    Button("No Cutoff (-95)") { store.rssiCutoffDbm = -95 }
                } label: {
                    Text("Cut \(Int(store.rssiCutoffDbm))")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            HStack(spacing: 4) {
                Text("-35").font(.system(size: 8, weight: .bold, design: .monospaced))
                LinearGradient(
                    colors: [
                        Color(red: 0.50, green: 0.00, blue: 0.00),
                        Color(red: 0.88, green: 0.14, blue: 0.14),
                        Color(red: 0.98, green: 0.45, blue: 0.09),
                        Color(red: 0.98, green: 0.80, blue: 0.08),
                        Color(red: 0.09, green: 0.83, blue: 0.31),
                        Color(red: 0.02, green: 0.76, blue: 0.91),
                        Color(red: 0.11, green: 0.31, blue: 0.85),
                        Color(red: 0.12, green: 0.04, blue: 0.36)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 145, height: 11)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.primary.opacity(0.4), lineWidth: 0.8))
                .cornerRadius(2)
                Text("-90").font(.system(size: 8, weight: .bold, design: .monospaced))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }

    private var calibrationPromptText: String {
        switch store.pickTarget {
        case .pickA: return "Step 1/2: Stand at Point A, then TAP Point A on floorplan"
        case .pickB: return "Step 2/2: Walk ≥2m to Point B, then TAP Point B on floorplan"
        case .reAnchor: return "Drift Fix: TAP your real current spot on the floorplan"
        case .none: return ""
        }
    }

    // MARK: - RoomPlan Architectural Cisco CAD Map

    private func drawRoomPlanCiscoMap(ctx: GraphicsContext, size: CGSize) {
        let isLight = store.ciscoLightTheme
        let proj = computeRoomProjection(in: size)

        // 1. Clean 1m architectural CAD grid
        let visMinX = Int(floor((0 - proj.ox) / proj.scale)), visMaxX = Int(ceil((size.width - proj.ox) / proj.scale))
        let visMinZ = Int(floor((0 - proj.oz) / proj.scale)), visMaxZ = Int(ceil((size.height - proj.oz) / proj.scale))
        var grid = Path()
        if visMaxX - visMinX < 100 {
            for gx in visMinX...visMaxX {
                let sx = Double(gx) * proj.scale + proj.ox
                grid.move(to: CGPoint(x: sx, y: 0)); grid.addLine(to: CGPoint(x: sx, y: size.height))
            }
        }
        if visMaxZ - visMinZ < 100 {
            for gz in visMinZ...visMaxZ {
                let sz = Double(gz) * proj.scale + proj.oz
                grid.move(to: CGPoint(x: 0, y: sz)); grid.addLine(to: CGPoint(x: size.width, y: sz))
            }
        }
        ctx.stroke(grid, with: .color(isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.07)), lineWidth: 1)

        // 2. RoomPlan Floor Polygon base fill
        for poly in store.floorPolygons where poly.count >= 3 {
            var fp = Path()
            for (i, pt) in poly.enumerated() {
                let sp = proj.toScreen(pt.x, pt.z)
                if i == 0 { fp.move(to: sp) } else { fp.addLine(to: sp) }
            }
            fp.closeSubpath()
            ctx.fill(fp, with: .color(isLight ? .white : Color(red: 0.09, green: 0.12, blue: 0.17)))
        }

        // 3. Cached Async-Rendered Smooth Cisco Contour Heatmap CGImage
        if let cached = heatmapCache.cached,
           case let .roomPlan(bounds, _) = cached.spec.mode {
            let tl = proj.rotatedToScreen(bounds.minRX, bounds.minRZ)
            let br = proj.rotatedToScreen(bounds.maxRX, bounds.maxRZ)
            let targetRect = CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)
            ctx.draw(Image(decorative: cached.image, scale: 1.0), in: targetRect)
        }

        // 4. RoomPlan Architectural Furniture Outlines
        for obj in store.objects where obj.corners.count == 4 {
            var op = Path()
            for (i, c) in obj.corners.enumerated() {
                let sp = proj.toScreen(c.x, c.z)
                if i == 0 { op.move(to: sp) } else { op.addLine(to: sp) }
            }
            op.closeSubpath()
            ctx.fill(op, with: .color(isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.08)))
            ctx.stroke(op, with: .color(isLight ? Color(red: 0.45, green: 0.52, blue: 0.60) : Color.white.opacity(0.35)), lineWidth: 1.2)
        }

        // 5. RoomPlan Crisp Architectural Walls, Windows & Doors
        drawRoomSurfaces(ctx: ctx, toScreen: proj.toScreen, isLight: isLight)

        // 6. Walk Path, Estimated Cisco AP Icons, Measured dBm Pills & Live Position
        drawSurveyOverlays(
            ctx: ctx,
            samples: currentSamples,
            toScreen: proj.toScreen,
            headingRad: store.cameraYaw + proj.rotRad,
            isLight: isLight,
            scale: proj.scale
        )
    }

    // MARK: - Calibrated Imported Floorplan Cisco Map

    private func drawCalibratedCiscoMap(ctx: GraphicsContext, size: CGSize, image: UIImage) {
        let rect = fittedImageRect(in: size, image: image)
        ctx.draw(Image(uiImage: image), in: rect)

        let cal = store.calibration
        func toScreen(_ wx: Double, _ wz: Double) -> CGPoint {
            let uv = cal.worldToNormalized(wx, wz)
            return CGPoint(x: rect.minX + uv.x * rect.width, y: rect.minY + uv.y * rect.height)
        }

        if let au = cal.pointAImgU, let av = cal.pointAImgV {
            drawAnchorBadge(ctx: ctx, at: CGPoint(x: rect.minX + au * rect.width, y: rect.minY + av * rect.height), label: "A", color: .yellow)
        }
        if let bu = cal.pointBImgU, let bv = cal.pointBImgV {
            drawAnchorBadge(ctx: ctx, at: CGPoint(x: rect.minX + bu * rect.width, y: rect.minY + bv * rect.height), label: "B", color: .green)
        }
        guard cal.isCalibrated else { return }

        if let cached = heatmapCache.cached,
           case .calibrated = cached.spec.mode {
            ctx.draw(Image(decorative: cached.image, scale: 1.0), in: rect)
        }

        if store.showRoomWallsOnFloorplan {
            drawRoomSurfaces(ctx: ctx, toScreen: toScreen, isLight: true)
        }
        drawSurveyOverlays(ctx: ctx, samples: currentSamples, toScreen: toScreen, headingRad: store.cameraYaw + cal.rotationRad, isLight: true, scale: 50)
    }

    private func drawRoomSurfaces(ctx: GraphicsContext, toScreen: (Double, Double) -> CGPoint, isLight: Bool) {
        if !store.walls.isEmpty {
            var wp = Path()
            for w in store.walls {
                wp.move(to: toScreen(w.x1, w.z1))
                wp.addLine(to: toScreen(w.x2, w.z2))
            }
            ctx.stroke(
                wp,
                with: .color(isLight ? Color(red: 0.11, green: 0.16, blue: 0.24) : Color(red: 0.90, green: 0.94, blue: 0.98)),
                style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round)
            )
        }
        if !store.windows.isEmpty {
            var winP = Path()
            for w in store.windows {
                winP.move(to: toScreen(w.x1, w.z1)); winP.addLine(to: toScreen(w.x2, w.z2))
            }
            ctx.stroke(winP, with: .color(Color(red: 0.08, green: 0.62, blue: 0.95)), style: StrokeStyle(lineWidth: 4.5, lineCap: .butt))
        }
        if !store.doors.isEmpty {
            var doorP = Path()
            for d in store.doors {
                doorP.move(to: toScreen(d.x1, d.z1)); doorP.addLine(to: toScreen(d.x2, d.z2))
            }
            ctx.stroke(doorP, with: .color(Color(red: 0.10, green: 0.72, blue: 0.45)), style: StrokeStyle(lineWidth: 4.0, lineCap: .round, dash: [6, 4]))
        }
    }

    private func drawAnchorBadge(ctx: GraphicsContext, at p: CGPoint, label: String, color: Color) {
        let r = CGRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22)
        ctx.fill(Path(ellipseIn: r), with: .color(color))
        ctx.stroke(Path(ellipseIn: r), with: .color(.black), lineWidth: 2)
        ctx.draw(Text(label).font(.system(size: 12, weight: .black)).foregroundColor(.black), at: p)
    }

    private func drawSurveyOverlays(
        ctx: GraphicsContext,
        samples: [HeatmapSample],
        toScreen: (Double, Double) -> CGPoint,
        headingRad: Double,
        isLight: Bool,
        scale: Double
    ) {
        // Walk path
        if store.points.count > 1 {
            var walk = Path()
            for (i, pt) in store.points.enumerated() {
                let sp = toScreen(pt.x, pt.z)
                if i == 0 { walk.move(to: sp) } else { walk.addLine(to: sp) }
            }
            ctx.stroke(walk, with: .color(Color(red: 0.04, green: 0.46, blue: 0.85).opacity(0.75)), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
        }

        // Survey Point Pins with clean Cisco-style dBm callout pills
        for s in samples {
            let p = toScreen(s.x, s.z)
            let c = store.bandInfoForCurrentMetric(s.val)
            let fillCol = Color(red: c.r, green: c.g, blue: c.b)

            let outer = Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14))
            ctx.fill(outer, with: .color(.white))
            ctx.stroke(outer, with: .color(fillCol), lineWidth: 3)

            let inner = Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
            ctx.fill(inner, with: .color(fillCol))

            if scale > 20 {
                let lbl = (store.selectedMetric == .qbssUtil || store.selectedMetric == .monRetry)
                    ? String(format: "%.0f%%", s.val)
                    : String(format: "%.0f", s.val)
                let pillRect = CGRect(x: p.x - 15, y: p.y - 24, width: 30, height: 14)
                ctx.fill(Path(roundedRect: pillRect, cornerRadius: 4), with: .color(isLight ? .white.opacity(0.92) : .black.opacity(0.82)))
                ctx.stroke(Path(roundedRect: pillRect, cornerRadius: 4), with: .color(fillCol), lineWidth: 1)
                ctx.draw(
                    Text(lbl).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(isLight ? .black : .white),
                    at: CGPoint(x: p.x, y: p.y - 17)
                )
            }
        }

        // Classic Cisco Prime Target Crosshair AP Icons + Crisp White Bordered Callout Tags
        if store.showEstimatedAPs {
            for ap in store.estimatedAPs {
                let p = toScreen(ap.x, ap.z)
                let outer = Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18))
                ctx.fill(outer, with: .color(Color(red: 0.28, green: 0.33, blue: 0.41)))
                ctx.stroke(outer, with: .color(.white), lineWidth: 2)
                let innerRing = Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
                ctx.stroke(innerRing, with: .color(.white), lineWidth: 1.2)
                var cross = Path()
                cross.move(to: CGPoint(x: p.x - 11, y: p.y)); cross.addLine(to: CGPoint(x: p.x + 11, y: p.y))
                cross.move(to: CGPoint(x: p.x, y: p.y - 11)); cross.addLine(to: CGPoint(x: p.x, y: p.y + 11))
                ctx.stroke(cross, with: .color(.white), lineWidth: 1.1)

                let tag = "\(ap.label.prefix(16)) (Ch\(ap.ch))"
                let tagW = CGFloat(max(78, tag.count * 6 + 12))
                let tagRect = CGRect(x: p.x + 13, y: p.y - 9, width: tagW, height: 18)
                ctx.fill(Path(tagRect), with: .color(.white))
                ctx.stroke(Path(tagRect), with: .color(.black), lineWidth: 1.2)
                ctx.draw(
                    Text(tag).font(.system(size: 9, weight: .bold)).foregroundColor(.black),
                    at: CGPoint(x: tagRect.midX, y: tagRect.midY)
                )
            }
        }

        // Live Surveyor Position + Heading Cone
        let camPt = toScreen(store.cameraX, store.cameraZ)
        var cone = Path()
        let coneLen: CGFloat = 28, spread = 0.45
        cone.move(to: camPt)
        cone.addLine(to: CGPoint(x: camPt.x + cos(headingRad - spread) * coneLen, y: camPt.y + sin(headingRad - spread) * coneLen))
        cone.addLine(to: CGPoint(x: camPt.x + cos(headingRad + spread) * coneLen, y: camPt.y + sin(headingRad + spread) * coneLen))
        cone.closeSubpath()
        ctx.fill(cone, with: .color(Color(red: 0.02, green: 0.56, blue: 0.96).opacity(0.35)))

        let meDot = Path(ellipseIn: CGRect(x: camPt.x - 7, y: camPt.y - 7, width: 14, height: 14))
        ctx.fill(meDot, with: .color(Color(red: 0.02, green: 0.56, blue: 0.96)))
        ctx.stroke(meDot, with: .color(.white), lineWidth: 2.5)
    }
}
