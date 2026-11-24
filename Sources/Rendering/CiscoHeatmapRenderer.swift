import Foundation
import CoreGraphics
import SwiftUI

// MARK: - Thread-Safe High-Res Cisco Contour Bitmap Generator + Async Cache

struct HeatmapSample: Equatable, Sendable {
    let x: Double
    let z: Double
    let val: Double
}

struct HeatmapBounds: Equatable, Sendable {
    let minRX: Double
    let maxRX: Double
    let minRZ: Double
    let maxRZ: Double

    var width: Double { max(0.1, maxRX - minRX) }
    var height: Double { max(0.1, maxRZ - minRZ) }
}

enum HeatmapModeKey: Equatable, Sendable {
    case roomPlan(bounds: HeatmapBounds, rotationDeg: Double)
    case calibrated(calibration: FloorplanCalibration)
}

struct HeatmapRenderSpec: Equatable, Sendable {
    let mode: HeatmapModeKey
    let widthPx: Int
    let heightPx: Int
    let samples: [HeatmapSample]
    let metric: HeatmapMetric
    let rssiCutoffDbm: Double
    let floorPolygons: [[RoomPoint2D]]
    let clipToRoom: Bool
}

struct CachedHeatmapResult: Sendable {
    let spec: HeatmapRenderSpec
    let image: CGImage
}

struct CiscoHeatmapRenderer {
    /// Pure, thread-safe Cisco Prime Infrastructure Thermal Rainbow CGImage generator.
    static func renderContourImage(spec: HeatmapRenderSpec) -> CGImage? {
        let widthPx = spec.widthPx
        let heightPx = spec.heightPx
        let samples = spec.samples
        guard !samples.isEmpty, widthPx > 4, heightPx > 4 else { return nil }

        let count = widthPx * heightPx
        var rgba = [UInt8](repeating: 0, count: count * 4)

        let hasPolys = spec.clipToRoom && !spec.floorPolygons.isEmpty
        let cutoff = spec.rssiCutoffDbm
        let metric = spec.metric
        let isRSSIMetric = (metric == .primaryRSSI || metric == .secondaryRSSI)

        // Precompute inverse rotation for RoomPlan mode
        let rotRad: Double
        let cr: Double
        let sr: Double
        let bounds: HeatmapBounds
        let cal: FloorplanCalibration?

        switch spec.mode {
        case .roomPlan(let b, let rotDeg):
            bounds = b
            rotRad = rotDeg * .pi / 180.0
            cr = cos(rotRad)
            sr = sin(rotRad)
            cal = nil
        case .calibrated(let c):
            bounds = HeatmapBounds(minRX: 0, maxRX: 1, minRZ: 0, maxRZ: 1)
            rotRad = 0
            cr = 1
            sr = 0
            cal = c
        }

        let invW = 1.0 / Double(widthPx)
        let invH = 1.0 / Double(heightPx)
        let spanRX = bounds.maxRX - bounds.minRX
        let spanRZ = bounds.maxRZ - bounds.minRZ

        for py in 0..<heightPx {
            let v = (Double(py) + 0.5) * invH
            for px in 0..<widthPx {
                let u = (Double(px) + 0.5) * invW
                let wx: Double
                let wz: Double
                if let c = cal {
                    (wx, wz) = c.normalizedToWorld(u, v)
                } else {
                    let rx = bounds.minRX + u * spanRX
                    let rz = bounds.minRZ + v * spanRZ
                    wx = rx * cr + rz * sr
                    wz = -rx * sr + rz * cr
                }

                if hasPolys {
                    var insideAny = false
                    for poly in spec.floorPolygons {
                        if CiscoColors.pointInPolygon(x: wx, z: wz, poly: poly) {
                            insideAny = true
                            break
                        }
                    }
                    if !insideAny { continue }
                }

                var num = 0.0
                var den = 0.0
                var minD2 = Double.greatestFiniteMagnitude
                for s in samples {
                    let dx = wx - s.x
                    let dz = wz - s.z
                    let d2 = dx * dx + dz * dz
                    if d2 < minD2 { minD2 = d2 }
                    let w = 1.0 / (d2 + 0.18)
                    num += w * s.val
                    den += w
                }
                guard den > 0 else { continue }

                let minD = sqrt(minD2)
                var val = num / den
                if isRSSIMetric {
                    // Realistic radial path-loss bloom outside measured points (Cisco Prime style)
                    let decay = minD > 1.0 ? 2.6 * (minD - 1.0) : 0.0
                    val -= decay
                    if val < cutoff { continue }
                } else if !hasPolys && minD > 5.5 {
                    continue
                }

                let info = CiscoColors.bandInfo(forMetric: metric, value: val)
                let edgeFade: Double = isRSSIMetric
                    ? min(1.0, (val - cutoff) / 4.0)
                    : (hasPolys ? 1.0 : max(0.0, min(1.0, (1.0 - minD / 5.5) * 1.4)))

                let o = (py * widthPx + px) * 4
                rgba[o]     = UInt8(max(0, min(255, Int(info.r * 255))))
                rgba[o + 1] = UInt8(max(0, min(255, Int(info.g * 255))))
                rgba[o + 2] = UInt8(max(0, min(255, Int(info.b * 255))))
                rgba[o + 3] = UInt8(max(0, min(255, Int(edgeFade * 175.0))))
            }
        }

        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(
            width: widthPx, height: heightPx,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: widthPx * 4,
            space: cs, bitmapInfo: bitmapInfo, provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    /// Computes a stable rotated-world bounding box from samples and walls (independent of live camera pose/pan/zoom).
    static func stableRoomPlanBounds(
        samples: [HeatmapSample],
        walls: [RoomSurfaceSegment],
        rotationDeg: Double
    ) -> HeatmapBounds? {
        guard !samples.isEmpty else { return nil }
        let rot = rotationDeg * .pi / 180.0
        let cr = cos(rot), sr = sin(rot)
        func rotW(_ x: Double, _ z: Double) -> (Double, Double) { (x * cr - z * sr, x * sr + z * cr) }

        var minRX = Double.greatestFiniteMagnitude
        var maxRX = -Double.greatestFiniteMagnitude
        var minRZ = Double.greatestFiniteMagnitude
        var maxRZ = -Double.greatestFiniteMagnitude

        // Pad around samples by 6.5m so radial path-loss bloom fits cleanly
        let samplePad = 6.5
        for s in samples {
            let p = rotW(s.x, s.z)
            minRX = min(minRX, p.0 - samplePad)
            maxRX = max(maxRX, p.0 + samplePad)
            minRZ = min(minRZ, p.1 - samplePad)
            maxRZ = max(maxRZ, p.1 + samplePad)
        }
        for w in walls {
            let p1 = rotW(w.x1, w.z1)
            let p2 = rotW(w.x2, w.z2)
            minRX = min(minRX, min(p1.0, p2.0) - 1.0)
            maxRX = max(maxRX, max(p1.0, p2.0) + 1.0)
            minRZ = min(minRZ, min(p1.1, p2.1) - 1.0)
            maxRZ = max(maxRZ, max(p1.1, p2.1) + 1.0)
        }
        return HeatmapBounds(minRX: minRX, maxRX: maxRX, minRZ: minRZ, maxRZ: maxRZ)
    }
}

/// Manages background rendering and caching of the 2D heatmap bitmap so pan/zoom and 12.5 Hz AR pose updates never stall the main thread.
@MainActor
final class HeatmapCacheController: ObservableObject {
    @Published private(set) var cached: CachedHeatmapResult?
    @Published private(set) var isRendering: Bool = false

    private var requestedSpec: HeatmapRenderSpec?
    private var renderTask: Task<Void, Never>?

    deinit {
        renderTask?.cancel()
    }

    func update(spec: HeatmapRenderSpec?) {
        guard let spec else {
            renderTask?.cancel()
            requestedSpec = nil
            if cached != nil { cached = nil }
            isRendering = false
            return
        }
        if spec == requestedSpec || spec == cached?.spec {
            return
        }
        requestedSpec = spec
        renderTask?.cancel()
        isRendering = true

        renderTask = Task.detached(priority: .userInitiated) { [spec] in
            if Task.isCancelled { return }
            let img = CiscoHeatmapRenderer.renderContourImage(spec: spec)
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self, self.requestedSpec == spec else { return }
                if let img {
                    self.cached = CachedHeatmapResult(spec: spec, image: img)
                }
                self.isRendering = false
            }
        }
    }
}
