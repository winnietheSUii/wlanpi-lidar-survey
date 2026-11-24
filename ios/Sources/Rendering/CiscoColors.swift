import SwiftUI
import UIKit

// MARK: - Cisco Prime 2D Thermal & Cisco DNA 3D Color Engine

struct CiscoColors {
    /// Classic Cisco Prime Infrastructure Thermal Rainbow (-35 dBm Deep Red -> -90 dBm Indigo)
    private static let primeStops: [(dbm: Double, r: Double, g: Double, b: Double)] = [
        (-35, 0.50, 0.00, 0.00), // Deep Crimson
        (-42, 0.88, 0.14, 0.14), // Bright Red
        (-50, 0.98, 0.45, 0.09), // Vivid Orange
        (-57, 0.98, 0.80, 0.08), // Warm Yellow
        (-64, 0.09, 0.83, 0.31), // Emerald Green
        (-72, 0.02, 0.76, 0.91), // Bright Cyan
        (-81, 0.11, 0.31, 0.85), // Royal Blue
        (-90, 0.12, 0.04, 0.36)  // Deep Indigo
    ]

    static func primeThermalRGB(forRSSI dbm: Double) -> (r: Double, g: Double, b: Double) {
        if dbm >= primeStops[0].dbm { return (primeStops[0].r, primeStops[0].g, primeStops[0].b) }
        guard let last = primeStops.last else { return (0.12, 0.04, 0.36) }
        if dbm <= last.dbm { return (last.r, last.g, last.b) }
        for i in 0..<(primeStops.count - 1) {
            let a = primeStops[i], b = primeStops[i + 1]
            if dbm <= a.dbm && dbm >= b.dbm {
                let t = (a.dbm - dbm) / (a.dbm - b.dbm)
                return (a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
            }
        }
        return (last.r, last.g, last.b)
    }

    static func bandInfo(forRSSI dbm: Double) -> (r: Double, g: Double, b: Double, band: Int) {
        let (r, g, b) = primeThermalRGB(forRSSI: dbm)
        let band: Int
        if dbm >= -50 { band = 5 }
        else if dbm >= -60 { band = 4 }
        else if dbm >= -67 { band = 3 }
        else if dbm >= -72 { band = 2 }
        else if dbm >= -80 { band = 1 }
        else { band = 0 }
        return (r, g, b, band)
    }

    static func bandInfo(forBadPct pct: Double, maxPct: Double) -> (r: Double, g: Double, b: Double, band: Int) {
        let eq = -35.0 - max(0.0, min(1.0, pct / maxPct)) * 55.0
        return bandInfo(forRSSI: eq)
    }

    static func bandInfo(forMetric metric: HeatmapMetric, value v: Double) -> (r: Double, g: Double, b: Double, band: Int) {
        switch metric {
        case .qbssUtil: return bandInfo(forBadPct: v, maxPct: 100.0)
        case .monRetry: return bandInfo(forBadPct: v, maxPct: 40.0)
        default: return bandInfo(forRSSI: v)
        }
    }

    static func color(forRSSI dbm: Double) -> Color {
        if dbm >= -55 { return Color(red: 0.08, green: 0.72, blue: 0.32) }
        if dbm >= -67 { return Color(red: 0.52, green: 0.82, blue: 0.12) }
        if dbm >= -75 { return Color(red: 0.96, green: 0.72, blue: 0.08) }
        if dbm >= -82 { return Color(red: 0.98, green: 0.45, blue: 0.09) }
        return Color(red: 0.90, green: 0.22, blue: 0.21)
    }

    static func uiColor(forRSSI dbm: Double) -> UIColor {
        let c = primeThermalRGB(forRSSI: dbm)
        return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1.0)
    }

    static func pointInPolygon(x: Double, z: Double, poly: [RoomPoint2D]) -> Bool {
        guard poly.count >= 3 else { return false }
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let xi = poly[i].x, zi = poly[i].z
            let xj = poly[j].x, zj = poly[j].z
            let intersect = ((zi > z) != (zj > z)) && (x < (xj - xi) * (z - zi) / ((zj - zi) + 1e-12) + xi)
            if intersect { inside.toggle() }
            j = i
        }
        return inside
    }
}
