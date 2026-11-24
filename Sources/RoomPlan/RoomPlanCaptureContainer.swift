import SwiftUI
import RoomPlan
import ARKit
import UIKit

// MARK: - Apple RoomPlan Capture View Container (Live Architectural Room Scan + Pose Tracking)

struct RoomPlanCaptureContainer: UIViewRepresentable {
    @ObservedObject var store: SurveyStore
    @ObservedObject var client: WlanPiClient

    func makeUIView(context: Context) -> UIView {
        if RoomCaptureSession.isSupported {
            let rcv = RoomCaptureView(frame: .zero)
            rcv.captureSession.delegate = context.coordinator
            context.coordinator.roomCaptureView = rcv

            store.onRestartRoomScan = { [weak coord = context.coordinator] in
                coord?.restartSession()
            }
            store.onFinalizeRoomScan = { [weak coord = context.coordinator] in
                coord?.finalizeScanKeepAR()
            }

            var cfg = RoomCaptureSession.Configuration()
            cfg.isCoachingEnabled = true
            rcv.captureSession.run(configuration: cfg)
            context.coordinator.startPoseTimer()
            return rcv
        } else {
            // Clean placeholder for iOS Simulator or devices without LiDAR
            let container = UIView(frame: .zero)
            container.backgroundColor = UIColor(red: 0.08, green: 0.10, blue: 0.15, alpha: 1.0)

            let stack = UIStackView()
            stack.axis = .vertical
            stack.alignment = .center
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false

            let icon = UIImageView(image: UIImage(systemName: "lidar.sensor") ?? UIImage(systemName: "camera.viewfinder"))
            icon.tintColor = UIColor.systemCyan
            icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 32, weight: .semibold)

            let title = UILabel()
            title.text = "LiDAR / RoomPlan Unavailable"
            title.textColor = .white
            title.font = .systemFont(ofSize: 14, weight: .bold)

            let sub = UILabel()
            sub.text = "Open Settings → Demo Mode to load a sample office survey or use a LiDAR iPad/iPhone."
            sub.textColor = UIColor.white.withAlphaComponent(0.68)
            sub.font = .systemFont(ofSize: 11)
            sub.numberOfLines = 0
            sub.textAlignment = .center

            stack.addArrangedSubview(icon)
            stack.addArrangedSubview(title)
            stack.addArrangedSubview(sub)
            container.addSubview(stack)

            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 18),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -18)
            ])
            return container
        }
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store, client: client)
    }

    final class Coordinator: NSObject, RoomCaptureSessionDelegate {
        let store: SurveyStore
        let client: WlanPiClient
        weak var roomCaptureView: RoomCaptureView?
        private var poseTimer: Timer?

        init(store: SurveyStore, client: WlanPiClient) {
            self.store = store
            self.client = client
        }

        deinit {
            poseTimer?.invalidate()
        }

        func startPoseTimer() {
            poseTimer?.invalidate()
            // Poll live ARFrame from RoomCaptureSession.arSession safely without replacing its internal delegate!
            poseTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                guard let self = self,
                      let session = self.roomCaptureView?.captureSession,
                      let frame = session.arSession.currentFrame else { return }
                let t = frame.camera.transform
                let pos = t.columns.3
                let yaw = atan2(Double(-t.columns.2.z), Double(-t.columns.2.x))
                let track: String
                switch frame.camera.trackingState {
                case .normal: track = "RoomPlan Tracking OK"
                case .notAvailable: track = "Unavailable"
                case .limited(let r):
                    switch r {
                    case .initializing: track = "Initializing..."
                    case .excessiveMotion: track = "Slow down"
                    case .insufficientFeatures: track = "Low light/texture"
                    case .relocalizing: track = "Relocalizing..."
                    @unknown default: track = "Limited"
                    }
                }
                Task { @MainActor in
                    self.store.updatePose(
                        x: Double(pos.x), y: Double(pos.y), z: Double(pos.z),
                        yaw: yaw, tracking: track,
                        latestScan: self.client.latestScan
                    )
                }
            }
        }

        func restartSession() {
            guard let rcv = roomCaptureView, RoomCaptureSession.isSupported else { return }
            rcv.captureSession.stop()
            var cfg = RoomCaptureSession.Configuration()
            cfg.isCoachingEnabled = true
            rcv.captureSession.run(configuration: cfg)
            startPoseTimer()
        }

        func finalizeScanKeepAR() {
            // Stop RoomPlan geometry refinement while keeping ARSession tracking alive so user can continue walking!
            roomCaptureView?.captureSession.stop(pauseARSession: false)
            Task { @MainActor in
                self.store.roomScanFinalized = true
                self.store.roomPlanInstruction = "Room locked! Continue walking to measure RF"
            }
        }

        func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
            Task { @MainActor in
                self.store.updateRoomPlan(room)
            }
        }

        func captureSession(_ session: RoomCaptureSession, didAdd room: CapturedRoom) {
            Task { @MainActor in
                self.store.updateRoomPlan(room)
            }
        }

        func captureSession(_ session: RoomCaptureSession, didChange room: CapturedRoom) {
            Task { @MainActor in
                self.store.updateRoomPlan(room)
            }
        }

        func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
            let text: String
            switch instruction {
            case .moveCloseToWall: text = "Move closer to wall"
            case .moveAwayFromWall: text = "Step back slightly from wall"
            case .slowDown: text = "Pan slowly for cleaner walls"
            case .turnOnLight: text = "More lighting helps RoomPlan"
            case .lowTexture: text = "Point at wall edges & corners"
            case .normal: text = "Good — keep scanning room walls"
            @unknown default: text = "Scanning room..."
            }
            Task { @MainActor in
                self.store.roomPlanInstruction = text
            }
        }
    }
}
