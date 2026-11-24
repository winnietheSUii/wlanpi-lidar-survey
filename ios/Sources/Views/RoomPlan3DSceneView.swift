import SwiftUI
import SceneKit
import UIKit

// MARK: - Interactive 3D Architectural RoomPlan + Cisco RF SceneKit View

struct RoomPlan3DSceneView: UIViewRepresentable {
    @ObservedObject var store: SurveyStore
    let cameraResetToken: Int

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = store.ciscoLightTheme
            ? UIColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1.0)
            : UIColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 1.0)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X

        let scene = SCNScene()
        view.scene = scene

        let camNode = SCNNode()
        camNode.name = "mainCam"
        camNode.camera = SCNCamera()
        camNode.camera?.zNear = 0.05
        camNode.camera?.zFar = 200.0
        camNode.position = SCNVector3(0, 9, 11)
        camNode.eulerAngles = SCNVector3(-0.70, 0, 0)
        scene.rootNode.addChildNode(camNode)
        view.pointOfView = camNode

        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light?.type = .ambient
        amb.light?.intensity = 750
        scene.rootNode.addChildNode(amb)

        let dir = SCNNode()
        dir.light = SCNLight()
        dir.light?.type = .directional
        dir.light?.intensity = 850
        dir.eulerAngles = SCNVector3(-0.9, 0.5, 0)
        scene.rootNode.addChildNode(dir)

        let worldRoot = SCNNode()
        worldRoot.name = "worldRoot"
        scene.rootNode.addChildNode(worldRoot)

        let meNode = buildLiveMarkerNode()
        meNode.name = "liveMe"
        scene.rootNode.addChildNode(meNode)

        context.coordinator.lastResetToken = cameraResetToken
        rebuildSceneContent(in: worldRoot, store: store)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.backgroundColor = store.ciscoLightTheme
            ? UIColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1.0)
            : UIColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 1.0)
        guard let scene = uiView.scene else { return }

        if let me = scene.rootNode.childNode(withName: "liveMe", recursively: false) {
            me.position = SCNVector3(Float(store.cameraX), Float(store.floorY + 0.35), Float(store.cameraZ))
            me.eulerAngles = SCNVector3(0, Float(-store.cameraYaw + .pi * 0.5), 0)
        }

        let key = "\(store.scene3DRevision)-\(store.selectedSSID)-\(store.selectedBand.rawValue)-\(store.selectedMetric.rawValue)-\(store.useCisco3DDomes)-\(store.elevate3DHeatmap)-\(store.show3DWalls)-\(store.show3DObjects)-\(store.ciscoLightTheme)-\(store.clipHeatmapToRoom)"
        if context.coordinator.lastBuildKey != key {
            context.coordinator.lastBuildKey = key
            if let root = scene.rootNode.childNode(withName: "worldRoot", recursively: false) {
                rebuildSceneContent(in: root, store: store)
            }
        }

        if context.coordinator.lastResetToken != cameraResetToken {
            context.coordinator.lastResetToken = cameraResetToken
            if let cam = scene.rootNode.childNode(withName: "mainCam", recursively: false) {
                let cx = Float(store.cameraX), cz = Float(store.cameraZ), fy = Float(store.floorY)
                cam.position = SCNVector3(cx, fy + 9.0, cz + 10.0)
                cam.look(at: SCNVector3(cx, fy, cz))
                uiView.pointOfView = cam
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        var lastBuildKey: String = ""
        var lastResetToken: Int = 0
    }

    private func buildLiveMarkerNode() -> SCNNode {
        let parent = SCNNode()
        let sphere = SCNSphere(radius: 0.16)
        sphere.firstMaterial?.diffuse.contents = UIColor.systemBlue
        sphere.firstMaterial?.emission.contents = UIColor.systemBlue.withAlphaComponent(0.5)
        parent.addChildNode(SCNNode(geometry: sphere))
        let cone = SCNCone(topRadius: 0.0, bottomRadius: 0.15, height: 0.42)
        cone.firstMaterial?.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.75)
        let cNode = SCNNode(geometry: cone)
        cNode.eulerAngles = SCNVector3(Float.pi * 0.5, 0, 0)
        cNode.position = SCNVector3(0, 0, -0.3)
        parent.addChildNode(cNode)
        return parent
    }

    private func rebuildSceneContent(in root: SCNNode, store: SurveyStore) {
        root.childNodes.forEach { $0.removeFromParentNode() }
        let fy = Float(store.floorY)
        let isLight = store.ciscoLightTheme

        var minX = store.cameraX - 5.0, maxX = store.cameraX + 5.0
        var minZ = store.cameraZ - 5.0, maxZ = store.cameraZ + 5.0
        for pt in store.points {
            minX = min(minX, pt.x - 3.0); maxX = max(maxX, pt.x + 3.0)
            minZ = min(minZ, pt.z - 3.0); maxZ = max(maxZ, pt.z + 3.0)
        }
        for w in store.walls {
            minX = min(minX, min(w.x1, w.x2) - 1.5); maxX = max(maxX, max(w.x1, w.x2) + 1.5)
            minZ = min(minZ, min(w.z1, w.z2) - 1.5); maxZ = max(maxZ, max(w.z1, w.z2) + 1.5)
        }

        // 1. Floor Grid or Calibrated Real Floorplan
        if let fpImg = store.floorplanImage, store.calibration.isCalibrated {
            let cal = store.calibration
            let c00 = cal.normalizedToWorld(0, 0), c10 = cal.normalizedToWorld(1, 0), c01 = cal.normalizedToWorld(0, 1)
            let wM = hypot(c10.0 - c00.0, c10.1 - c00.1)
            let hM = hypot(c01.0 - c00.0, c01.1 - c00.1)
            let center = cal.normalizedToWorld(0.5, 0.5)
            let plane = SCNPlane(width: CGFloat(wM), height: CGFloat(hM))
            plane.firstMaterial?.diffuse.contents = fpImg
            plane.firstMaterial?.lightingModel = .constant
            plane.firstMaterial?.isDoubleSided = true
            let n = SCNNode(geometry: plane)
            n.position = SCNVector3(Float(center.0), fy - 0.02, Float(center.1))
            n.eulerAngles = SCNVector3(-Float.pi * 0.5, Float(cal.rotationRad), 0)
            root.addChildNode(n)
        } else {
            root.addChildNode(buildFloorGrid(minX: minX, maxX: maxX, minZ: minZ, maxZ: maxZ, y: fy - 0.02, isLight: isLight))
        }

        // 2. Clean Matte-Gray 3D RoomPlan Architectural Walls (Cisco DNA 3D style!)
        if store.show3DWalls {
            let wallMat = SCNMaterial()
            wallMat.diffuse.contents = isLight
                ? UIColor(red: 0.72, green: 0.75, blue: 0.79, alpha: 0.96)
                : UIColor(red: 0.58, green: 0.78, blue: 0.96, alpha: 0.42)
            wallMat.roughness.contents = 0.85
            wallMat.isDoubleSided = true

            let borderMat = SCNMaterial()
            borderMat.diffuse.contents = isLight ? UIColor(red: 0.36, green: 0.40, blue: 0.46, alpha: 1.0) : UIColor.cyan

            for w in store.walls {
                let len = hypot(w.x2 - w.x1, w.z2 - w.z1)
                if len < 0.2 { continue }
                let h = max(1.8, min(3.5, w.yMax - w.yMin))
                let box = SCNBox(width: CGFloat(len), height: CGFloat(h), length: 0.08, chamferRadius: 0)
                box.materials = [wallMat]
                let node = SCNNode(geometry: box)
                let mx = Float((w.x1 + w.x2) * 0.5), mz = Float((w.z1 + w.z2) * 0.5)
                let yaw = Float(-atan2(w.z2 - w.z1, w.x2 - w.x1))
                node.position = SCNVector3(mx, fy + Float(h * 0.5), mz)
                node.eulerAngles = SCNVector3(0, yaw, 0)
                root.addChildNode(node)

                let cap = SCNBox(width: CGFloat(len), height: 0.05, length: 0.10, chamferRadius: 0)
                cap.materials = [borderMat]
                let capN = SCNNode(geometry: cap)
                capN.position = SCNVector3(mx, fy + Float(h), mz)
                capN.eulerAngles = SCNVector3(0, yaw, 0)
                root.addChildNode(capN)
            }

            let winMat = SCNMaterial()
            winMat.diffuse.contents = UIColor(red: 0.15, green: 0.68, blue: 0.98, alpha: 0.55)
            for win in store.windows {
                let len = hypot(win.x2 - win.x1, win.z2 - win.z1)
                let h = max(0.6, win.yMax - win.yMin)
                let box = SCNBox(width: CGFloat(len), height: CGFloat(h), length: 0.11, chamferRadius: 0)
                box.materials = [winMat]
                let node = SCNNode(geometry: box)
                node.position = SCNVector3(Float((win.x1 + win.x2) * 0.5), Float((win.yMin + win.yMax) * 0.5), Float((win.z1 + win.z2) * 0.5))
                node.eulerAngles = SCNVector3(0, Float(-atan2(win.z2 - win.z1, win.x2 - win.x1)), 0)
                root.addChildNode(node)
            }

            let doorMat = SCNMaterial()
            doorMat.diffuse.contents = UIColor(red: 0.12, green: 0.72, blue: 0.45, alpha: 0.55)
            for d in store.doors {
                let len = hypot(d.x2 - d.x1, d.z2 - d.z1)
                let h = max(1.8, d.yMax - d.yMin)
                let box = SCNBox(width: CGFloat(len), height: CGFloat(h), length: 0.11, chamferRadius: 0)
                box.materials = [doorMat]
                let node = SCNNode(geometry: box)
                node.position = SCNVector3(Float((d.x1 + d.x2) * 0.5), fy + Float(h * 0.5), Float((d.z1 + d.z2) * 0.5))
                node.eulerAngles = SCNVector3(0, Float(-atan2(d.z2 - d.z1, d.x2 - d.x1)), 0)
                root.addChildNode(node)
            }
        }

        // 3. Clean 3D RoomPlan Furniture Boxes
        if store.show3DObjects {
            let objMat = SCNMaterial()
            objMat.diffuse.contents = isLight
                ? UIColor(red: 0.70, green: 0.75, blue: 0.82, alpha: 0.65)
                : UIColor(red: 0.45, green: 0.52, blue: 0.62, alpha: 0.5)
            for obj in store.objects {
                let b = SCNBox(width: CGFloat(max(0.15, obj.width)), height: CGFloat(max(0.15, obj.height)), length: CGFloat(max(0.15, obj.depth)), chamferRadius: 0.03)
                b.materials = [objMat]
                let n = SCNNode(geometry: b)
                n.position = SCNVector3(Float(obj.cx), Float(obj.cy), Float(obj.cz))
                n.eulerAngles = SCNVector3(0, Float(-obj.yawRad), 0)
                root.addChildNode(n)
            }
        }

        // 4. Cisco DNA Center 3D Wireless Analyzer (Red Floor + Volumetric Green/Amber Domes + Teardrop Score Pins!)
        let samples: [(x: Double, y: Double, z: Double, val: Double)] = store.points.compactMap { pt in
            guard let v = store.metricValue(for: pt) else { return nil }
            return (pt.x, pt.y, pt.z, v)
        }
        if !samples.isEmpty {
            if store.useCisco3DDomes {
                let slabW = CGFloat(max(4.0, maxX - minX))
                let slabD = CGFloat(max(4.0, maxZ - minZ))
                let slab = SCNBox(width: slabW, height: 0.04, length: slabD, chamferRadius: 0)
                slab.firstMaterial?.diffuse.contents = UIColor(red: 0.90, green: 0.17, blue: 0.17, alpha: 0.95)
                slab.firstMaterial?.lightingModel = .constant
                let slabN = SCNNode(geometry: slab)
                slabN.position = SCNVector3(Float((minX + maxX) * 0.5), fy + 0.01, Float((minZ + maxZ) * 0.5))
                root.addChildNode(slabN)

                let domeTargets: [(x: Double, z: Double, rssi: Double, label: String)] = {
                    let aps = store.estimatedAPs
                    if !aps.isEmpty {
                        return aps.map { ($0.x, $0.z, $0.rssi, "\($0.label.prefix(14))-Ch\($0.ch)") }
                    }
                    return samples.prefix(6).enumerated().map { ($0.element.x, $0.element.z, $0.element.val, "Pt-\($0.offset + 1)") }
                }()

                for ap in domeTargets {
                    if ap.rssi >= -65.0 {
                        let rG = max(1.1, min(3.2, (ap.rssi + 73.0) * 0.14))
                        let hG = min(2.0, rG * 0.78)
                        let gDome = buildHemisphereNode(
                            radiusXZ: Float(rG), heightY: Float(hG),
                            color: UIColor(red: 0.07, green: 0.60, blue: 0.18, alpha: 0.88),
                            renderOrder: 5
                        )
                        gDome.position = SCNVector3(Float(ap.x), fy + 0.03, Float(ap.z))
                        root.addChildNode(gDome)
                    }

                    if ap.rssi >= -75.0 {
                        let rA = max(1.9, min(4.6, (ap.rssi + 84.0) * 0.16))
                        let hA = min(2.5, rA * 0.65)
                        let aDome = buildHemisphereNode(
                            radiusXZ: Float(rA), heightY: Float(hA),
                            color: UIColor(red: 0.96, green: 0.65, blue: 0.14, alpha: 0.48),
                            renderOrder: 10
                        )
                        aDome.position = SCNVector3(Float(ap.x), fy + 0.03, Float(ap.z))
                        root.addChildNode(aDome)
                    }

                    let apTile = SCNBox(width: 0.28, height: 0.06, length: 0.28, chamferRadius: 0.02)
                    apTile.firstMaterial?.diffuse.contents = UIColor.white
                    let tileN = SCNNode(geometry: apTile)
                    tileN.position = SCNVector3(Float(ap.x), fy + 0.08, Float(ap.z))
                    root.addChildNode(tileN)

                    let score = ap.rssi >= -58 ? 10 : (ap.rssi >= -65 ? 9 : (ap.rssi >= -72 ? 7 : 6))
                    let pinNode = buildBillboardPinNode(score: score, title: ap.label)
                    pinNode.position = SCNVector3(Float(ap.x), fy + 2.55, Float(ap.z))
                    root.addChildNode(pinNode)
                }
            } else {
                if let hmNode = buildCisco3DHeatmap(samples: samples, minX: minX, maxX: maxX, minZ: minZ, maxZ: maxZ, floorY: fy + 0.05, store: store) {
                    root.addChildNode(hmNode)
                }
            }
        }
    }

    private func buildHemisphereNode(radiusXZ: Float, heightY: Float, color: UIColor, renderOrder: Int) -> SCNNode {
        let segsU = 28, segsV = 12
        var verts: [SCNVector3] = []
        var norms: [SCNVector3] = []
        var indices: [UInt32] = []

        for iv in 0...segsV {
            let phi = Float(iv) / Float(segsV) * (Float.pi * 0.5)
            let cosP = cos(phi), sinP = sin(phi)
            for iu in 0...segsU {
                let th = Float(iu) / Float(segsU) * (Float.pi * 2.0)
                let cosT = cos(th), sinT = sin(th)
                let vx = cosP * cosT * radiusXZ
                let vy = sinP * heightY
                let vz = cosP * sinT * radiusXZ
                verts.append(SCNVector3(vx, vy, vz))
                norms.append(SCNVector3(cosP * cosT, sinP, cosP * sinT))
            }
        }
        let stride = segsU + 1
        for iv in 0..<segsV {
            for iu in 0..<segsU {
                let i0 = UInt32(iv * stride + iu)
                let i1 = i0 + 1
                let i2 = UInt32((iv + 1) * stride + iu)
                let i3 = i2 + 1
                indices.append(contentsOf: [i0, i1, i2, i1, i3, i2])
            }
        }
        let geom = SCNGeometry(
            sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.isDoubleSided = true
        mat.writesToDepthBuffer = (renderOrder < 8)
        mat.transparencyMode = .aOne
        geom.materials = [mat]
        let node = SCNNode(geometry: geom)
        node.renderingOrder = renderOrder
        return node
    }

    private func buildBillboardPinNode(score: Int, title: String) -> SCNNode {
        let imgSize = CGSize(width: 280, height: 84)
        let renderer = UIGraphicsImageRenderer(size: imgSize)
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            let pinColor = score >= 8
                ? UIColor(red: 0.09, green: 0.64, blue: 0.29, alpha: 1.0)
                : UIColor(red: 0.96, green: 0.62, blue: 0.05, alpha: 1.0)

            let cx: CGFloat = 34, cy: CGFloat = 34
            cg.setFillColor(pinColor.cgColor)
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(3.0)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: cx, y: 76))
            path.addCurve(to: CGPoint(x: cx, y: 10), controlPoint1: CGPoint(x: cx - 32, y: 48), controlPoint2: CGPoint(x: cx - 30, y: 10))
            path.addCurve(to: CGPoint(x: cx, y: 76), controlPoint1: CGPoint(x: cx + 30, y: 10), controlPoint2: CGPoint(x: cx + 32, y: 48))
            path.close()
            cg.addPath(path.cgPath)
            cg.drawPath(using: .fillStroke)

            let sAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let sStr = "\(score)" as NSString
            let sSz = sStr.size(withAttributes: sAttrs)
            sStr.draw(at: CGPoint(x: cx - sSz.width * 0.5, y: cy - sSz.height * 0.5), withAttributes: sAttrs)

            let lAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Georgia-Bold", size: 18) ?? UIFont.boldSystemFont(ofSize: 18),
                .foregroundColor: UIColor(red: 0.12, green: 0.16, blue: 0.23, alpha: 1.0)
            ]
            (title as NSString).draw(at: CGPoint(x: 68, y: 22), withAttributes: lAttrs)
        }

        let plane = SCNPlane(width: 2.3, height: 0.70)
        plane.firstMaterial?.diffuse.contents = img
        plane.firstMaterial?.lightingModel = .constant
        plane.firstMaterial?.isDoubleSided = true
        let node = SCNNode(geometry: plane)
        let bb = SCNBillboardConstraint()
        bb.freeAxes = [.X, .Y]
        node.constraints = [bb]
        node.renderingOrder = 20
        return node
    }

    private func buildFloorGrid(minX: Double, maxX: Double, minZ: Double, maxZ: Double, y: Float, isLight: Bool) -> SCNNode {
        var verts: [SCNVector3] = [], indices: [UInt32] = []
        let x0 = Int(floor(minX)), x1 = Int(ceil(maxX)), z0 = Int(floor(minZ)), z1 = Int(ceil(maxZ))
        if x1 - x0 <= 120 {
            for gx in x0...x1 {
                let i = UInt32(verts.count)
                verts.append(SCNVector3(Float(gx), y, Float(z0))); verts.append(SCNVector3(Float(gx), y, Float(z1)))
                indices.append(i); indices.append(i + 1)
            }
        }
        if z1 - z0 <= 120 {
            for gz in z0...z1 {
                let i = UInt32(verts.count)
                verts.append(SCNVector3(Float(x0), y, Float(gz))); verts.append(SCNVector3(Float(x1), y, Float(gz)))
                indices.append(i); indices.append(i + 1)
            }
        }
        let geom = SCNGeometry(sources: [SCNGeometrySource(vertices: verts)], elements: [SCNGeometryElement(indices: indices, primitiveType: .line)])
        geom.firstMaterial?.diffuse.contents = isLight ? UIColor.black.withAlphaComponent(0.10) : UIColor.white.withAlphaComponent(0.14)
        geom.firstMaterial?.lightingModel = .constant
        return SCNNode(geometry: geom)
    }

    private func buildCisco3DHeatmap(
        samples: [(x: Double, y: Double, z: Double, val: Double)],
        minX: Double, maxX: Double, minZ: Double, maxZ: Double,
        floorY: Float,
        store: SurveyStore
    ) -> SCNNode? {
        let cols = 48, rows = 48
        let dx = (maxX - minX) / Double(cols - 1)
        let dz = (maxZ - minZ) / Double(rows - 1)
        let hasPolys = store.clipHeatmapToRoom && !store.floorPolygons.isEmpty
        let radiusM = 6.0, radiusM2 = radiusM * radiusM

        var verts: [SCNVector3] = []
        var colors: [SIMD4<Float>] = []
        var valid = [Bool](repeating: false, count: cols * rows)

        for r in 0..<rows {
            let wz = minZ + Double(r) * dz
            for c in 0..<cols {
                let wx = minX + Double(c) * dx
                var ok = true
                if hasPolys {
                    ok = store.floorPolygons.contains { CiscoColors.pointInPolygon(x: wx, z: wz, poly: $0) }
                }
                if !ok {
                    verts.append(SCNVector3(Float(wx), floorY, Float(wz)))
                    colors.append(SIMD4<Float>(0, 0, 0, 0))
                    continue
                }
                var num = 0.0, den = 0.0, minD2 = Double.greatestFiniteMagnitude
                for s in samples {
                    let d2 = (wx - s.x) * (wx - s.x) + (wz - s.z) * (wz - s.z)
                    if d2 < minD2 { minD2 = d2 }
                    let w = 1.0 / (d2 + 0.16)
                    num += w * s.val; den += w
                }
                if (!hasPolys && minD2 > radiusM2) || den <= 0 {
                    verts.append(SCNVector3(Float(wx), floorY, Float(wz)))
                    colors.append(SIMD4<Float>(0, 0, 0, 0))
                    continue
                }
                let v = num / den
                let ci = store.bandInfoForCurrentMetric(v)
                let dist = sqrt(minD2)
                let alpha: Float = hasPolys ? 0.78 : Float(max(0.18, min(0.80, (1.0 - dist / radiusM) * 0.90)))
                var h: Float = 0
                if store.elevate3DHeatmap {
                    let norm = Double(ci.band) / 5.0
                    h = Float(norm * 1.25)
                }
                verts.append(SCNVector3(Float(wx), floorY + h, Float(wz)))
                colors.append(SIMD4<Float>(Float(ci.r), Float(ci.g), Float(ci.b), alpha))
                valid[r * cols + c] = true
            }
        }

        var indices: [UInt32] = []
        for r in 0..<(rows - 1) {
            for c in 0..<(cols - 1) {
                let i0 = r * cols + c, i1 = i0 + 1, i2 = i0 + cols, i3 = i2 + 1
                if valid[i0] && valid[i1] && valid[i2] { indices.append(contentsOf: [UInt32(i0), UInt32(i2), UInt32(i1)]) }
                if valid[i1] && valid[i2] && valid[i3] { indices.append(contentsOf: [UInt32(i1), UInt32(i2), UInt32(i3)]) }
            }
        }
        guard !indices.isEmpty else { return nil }

        let vSrc = SCNGeometrySource(vertices: verts)
        let colorData = colors.withUnsafeBytes { Data($0) }
        let cSrc = SCNGeometrySource(
            data: colorData, semantic: .color, vectorCount: colors.count,
            usesFloatComponents: true, componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
            dataStride: MemoryLayout<SIMD4<Float>>.stride
        )
        let geom = SCNGeometry(sources: [vSrc, cSrc], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.blendMode = .alpha
        mat.writesToDepthBuffer = false
        geom.materials = [mat]
        return SCNNode(geometry: geom)
    }
}
