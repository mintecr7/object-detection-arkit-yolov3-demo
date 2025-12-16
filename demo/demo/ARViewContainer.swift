//
//  ARViewContainer.swift
//  demo
//
//  Created by Mintesnot Shigutie on 12/16/25.
//


import SwiftUI
import RealityKit
import ARKit
import ImageIO

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var state: AppState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Configure AR session
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        // Optional, but recommended on LiDAR iPhone Pro for better raycasts later:
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        arView.session.delegate = context.coordinator
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // no-op
    }

    // MARK: - Coordinator
    final class Coordinator: NSObject, ARSessionDelegate {
        private let state: AppState
        private let yolo: YOLOInferenceRunner

        init(state: AppState) {
            self.state = state
            do {
                self.yolo = try YOLOInferenceRunner()
            } catch {
                fatalError("Failed to init YOLOInferenceRunner: \(error)")
            }
            super.init()
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            let pixelBuffer = frame.capturedImage
            let orientation = Self.exifOrientation()

            yolo.run(pixelBuffer: pixelBuffer, orientation: orientation) { [weak self] dets in
                guard let self else { return }
                Task { @MainActor in
                    self.state.detections = dets
                }
            }
        }

        // For a meeting demo, this mapping is usually sufficient.
        // If boxes appear rotated/mirrored, we’ll adjust this mapping based on your device orientation.
        private static func exifOrientation() -> CGImagePropertyOrientation {
            // Assuming portrait UI with back camera:
            // ARFrame.capturedImage is typically landscape; .right is commonly correct for portrait display.
            return .right
        }
    }
}
