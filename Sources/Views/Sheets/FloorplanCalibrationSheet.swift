import SwiftUI
import PhotosUI
import UIKit

// MARK: - Floorplan Import & 2-Point Walk Calibration Sheet

struct FloorplanCalibrationSheet: View {
    @ObservedObject var store: SurveyStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section("1. Real Floorplan Image (Optional)") {
                    let hasFloorplan = store.floorplanImage != nil
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(hasFloorplan ? "Replace Floorplan Image" : "Import Floorplan from Photos", systemImage: "photo.on.rectangle.angled")
                    }
                    .onChange(of: selectedPhoto) { _, newItem in
                        guard let item = newItem else { return }
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let uiImg = UIImage(data: data) {
                                store.setFloorplanImage(uiImg)
                            }
                        }
                    }

                    if store.floorplanImage != nil {
                        Button(role: .destructive) {
                            store.floorplanImage = nil
                            store.calibration = .empty
                            store.pickTarget = .none
                            store.scene3DRevision += 1
                        } label: {
                            Label("Remove Floorplan (Use RoomPlan Auto Floorplan)", systemImage: "xmark.circle")
                        }
                    }
                }

                if store.floorplanImage != nil {
                    Section("2. 2-Point Walk Calibration (Align to Real Room)") {
                        Text("Stand at Corner A → tap Point A on the 2D Map. Walk ≥2–5m to Corner B → tap Point B. Exact scale & rotation are solved automatically.")
                            .font(.caption).foregroundColor(.secondary)

                        Button {
                            store.pickTarget = .pickA
                            dismiss()
                        } label: {
                            Label("Start 2-Point Calibration (A → B)", systemImage: "scope")
                        }
                        .buttonStyle(.borderedProminent)

                        if store.calibration.isCalibrated {
                            HStack {
                                Text("Scale"); Spacer()
                                Text(String(format: "%.1f px/m", store.calibration.scalePxPerMeter)).foregroundColor(.green).font(.caption.monospaced())
                            }
                            Slider(value: $store.calibration.rotationRad, in: -.pi ... .pi) { Text("Rotation") }
                            Toggle("Overlay RoomPlan Walls", isOn: $store.showRoomWallsOnFloorplan)
                            Button { store.pickTarget = .reAnchor; dismiss() } label: {
                                Label("Fix Drift (Re-Anchor Here)", systemImage: "pin.fill")
                            }
                        }
                    }
                } else {
                    Section("RoomPlan Auto Floorplan Controls") {
                        Button { store.autoStraightenWalls(); dismiss() } label: {
                            Label("Auto-Align Longest Wall Straight", systemImage: "rotate.right")
                        }
                        VStack(alignment: .leading) {
                            Text(String(format: "Map Rotation: %.0f°", store.mapRotationDeg)).font(.caption)
                            Slider(value: $store.mapRotationDeg, in: -180...180, step: 1)
                        }
                        Toggle("Clip Heatmap Inside RoomPlan Floor", isOn: $store.clipHeatmapToRoom)
                        Toggle("Show Estimated Cisco AP Icons", isOn: $store.showEstimatedAPs)
                        Toggle("Cisco Light CAD Theme", isOn: $store.ciscoLightTheme)
                    }
                }
            }
            .navigationTitle("Floorplan & Calibrate")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
