//
//  ARViewContainer.swift
//  demo
//
//  Created by Mintesnot Shigutie on 12/16/25.
//


import simd
import ARKit
import UIKit
import SwiftUI
import ImageIO
import RealityKit

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var state: AppState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        arView.session.delegate = context.coordinator
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        // Let coordinator keep a reference to the ARView for pinning/anchors
        context.coordinator.attach(arView: arView)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.handleActions(
          on: uiView,
          detections: state.detections,
          pinToken: state.pinRequestToken,
          clearToken: state.clearPinsToken,
          startToken: state.startSessionToken,
          stopToken: state.stopSessionToken
        )

    }

    final class Coordinator: NSObject, ARSessionDelegate {
        private let state: AppState
        private let yolo: YOLOInferenceRunner

        private weak var arView: ARView?
        
        private var labelEntities: [Entity] = []
        private var lastBillboardUpdate: TimeInterval = 0


        // Track tokens so each press is handled once
        private var lastPinToken: Int = 0
        private var lastClearToken: Int = 0

        // Keep anchors to remove later
        private var pinAnchors: [AnchorEntity] = []
        
        private var recorder: SessionRecorder? = nil
        private var isRecording = false
        private var lastStartToken = 0
        private var lastStopToken = 0

        private var lastFrameLogUptime: TimeInterval = 0
        private let frameLogInterval: TimeInterval = 0.5 // 2 Hz

        private var latestDetections: [Detection] = []
        private var lastCameraTransform: simd_float4x4 = matrix_identity_float4x4
        
        private var lastPoseSampleUptime: TimeInterval = 0
        private let poseSampleInterval: TimeInterval = 0.10
        


        init(state: AppState) {
            self.state = state
            UIDevice.current.isBatteryMonitoringEnabled = true
            do {
                self.yolo = try YOLOInferenceRunner()
            } catch {
                fatalError("Failed to init YOLOInferenceRunner: \(error)")
            }
            super.init()
        }

        func attach(arView: ARView) {
            self.arView = arView
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            let pixelBuffer = frame.capturedImage
            let orientation = Self.exifOrientation()
            lastCameraTransform = frame.camera.transform
            
            /// Only sample poses when tracking is reasonable (avoids junk path)
            let trackingOK: Bool = {
                switch frame.camera.trackingState {
                case .normal: return true
                default: return false
                }
            }()

            if trackingOK {
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastPoseSampleUptime >= poseSampleInterval {
                    lastPoseSampleUptime = now

                    let T = frame.camera.transform
                    let p = SIMD3<Float>(T.columns.3.x, T.columns.3.y, T.columns.3.z)

                    Task { @MainActor in
                        state.trajectory.append(PoseSample(t: now, position: p))
                        // keep last N points so UI stays fast
                        if state.trajectory.count > 600 { // 60 seconds @ 10Hz
                            state.trajectory.removeFirst(state.trajectory.count - 600)
                        }
                    }
                }
            }

            
            if isRecording {
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastFrameLogUptime >= frameLogInterval {
                    lastFrameLogUptime = now

                    Task {
                        let telemetry = self.makeTelemetry(odFPS: nil)
                        try? await self.recorder?.appendFrame(
                            ts: Date().timeIntervalSince1970,
                            cameraTransform: self.lastCameraTransform,
                            detections: self.latestDetections,
                            telemetry: telemetry
                        )
                    }
                }
            }


            yolo.run(pixelBuffer: pixelBuffer, orientation: orientation) { [weak self] dets in
                guard let self else { return }
                self.latestDetections = dets
                Task { @MainActor in
                    self.state.detections = dets
                }
            }
            
            Task { @MainActor in
                self.updateLabelsFacingCamera(frame.camera.transform)
            }

        }

        func handleActions(on arView: ARView,
                           detections: [Detection],
                           pinToken: Int,
                           clearToken: Int,
                           startToken: Int,
                           stopToken: Int)

        {
            if startToken != lastStartToken {
                lastStartToken = startToken
                startSession()
            }

            if stopToken != lastStopToken {
                lastStopToken = stopToken
                stopSession()
            }

            if clearToken != lastClearToken {
                lastClearToken = clearToken
                clearPins(on: arView)
            }

            if pinToken != lastPinToken {
                lastPinToken = pinToken
                pinBestDetection(on: arView, detections: detections)
            }
        }

        private func pinBestDetection(on arView: ARView, detections: [Detection]) {
            guard let best = detections.max(by: { $0.score < $1.score }) else {
                Task { @MainActor in state.status = "No detections to pin" }
                return
            }

            // Convert normalized rect center → screen point
            let viewSize = arView.bounds.size
            let cx = best.rect.midX * viewSize.width
            let cy = best.rect.midY * viewSize.height
            let point = CGPoint(x: cx, y: cy)

            // Raycast
            let results = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .any)
            guard let hit = results.first else {
                Task { @MainActor in state.status = "Raycast failed (move closer / improve lighting)" }
                return
            }

            // Place marker anchor
            let anchor = AnchorEntity(world: hit.worldTransform)
            let marker = ModelEntity(
                mesh: .generateSphere(radius: 0.01),
                materials: [SimpleMaterial(color: .red, isMetallic: false)]
            )
            marker.position = .zero
            anchor.addChild(marker)

            // Optional label (small, billboard-like)
            let labelEntity = makeLabelEntity(text: best.label)
            labelEntity.position = SIMD3<Float>(0, 0.03, 0)
            anchor.addChild(labelEntity)
            labelEntities.append(labelEntity)

            arView.scene.addAnchor(anchor)
            pinAnchors.append(anchor)

            let t = hit.worldTransform.columns.3
            let world = SIMD3<Float>(t.x, t.y, t.z)
            
            if isRecording, let recorder = recorder {
                let telemetry = makeTelemetry(odFPS: nil)
                Task {
                    try? await recorder.appendPin(
                        ts: Date().timeIntervalSince1970,
                        cameraTransform: lastCameraTransform,
                        pinned: best,
                        worldPosition: world,
                        telemetry: telemetry
                    )
                }
            }


            Task { @MainActor in
                state.status = "Pinned: \(best.label) \(Int(best.score * 100))%"
                state.pinned.append(PinnedDetection(
                    ts: ProcessInfo.processInfo.systemUptime,
                    label: best.label,
                    score: best.score,
                    worldPosition: world
                ))
            }
        }

        private func clearPins(on arView: ARView) {
            pinAnchors.forEach { $0.removeFromParent() }
            pinAnchors.removeAll()

            Task { @MainActor in
                state.pinned.removeAll()
                labelEntities.removeAll()
                state.status = "Pins cleared"
            }
        }

        private func makeLabelEntity(text: String) -> ModelEntity {
            // Smaller font + small extrusion
            let mesh = MeshResource.generateText(
                text,
                extrusionDepth: 0.0005,
                font: .systemFont(ofSize: 0.035, weight: .semibold),
                containerFrame: .zero,
                alignment: .center,
                lineBreakMode: .byTruncatingTail
            )

            // Unlit = stays readable regardless of lighting
            let mat = UnlitMaterial(color: .white)

            let e = ModelEntity(mesh: mesh, materials: [mat])

            // Additional downscale (safe knob)
            e.scale = SIMD3<Float>(repeating: 0.25)

            return e
        }
        private func startSession() {
            Task {
                do {
                    recorder = try await SessionRecorder(appName: "object-detection-arkit-yolov3-demo")
                    isRecording = true
                    await MainActor.run {
                        state.isRecording = true
                        state.exportURL = nil
                        state.status = "Recording started"
                    }
                } catch {
                    await MainActor.run { state.status = "Recorder error: \(error.localizedDescription)" }
                }
            }
        }

        private func stopSession() {
            Task {
                guard let recorder else { return }
                do {
                    try await recorder.finish()
                    let url = await recorder.url()
                    self.recorder = nil
                    isRecording = false
                    await MainActor.run {
                        state.isRecording = false
                        state.exportURL = url
                        state.status = "Recording saved"
                    }
                } catch {
                    await MainActor.run { state.status = "Stop error: \(error.localizedDescription)" }
                }
            }
        }

        private func makeTelemetry(odFPS: Float?) -> SessionRecorder.Telemetry {
            let thermal: String = {
                switch ProcessInfo.processInfo.thermalState {
                case .nominal: return "nominal"
                case .fair: return "fair"
                case .serious: return "serious"
                case .critical: return "critical"
                @unknown default: return "unknown"
                }
            }()
            let battery = UIDevice.current.batteryLevel // -1 if unavailable
            return SessionRecorder.Telemetry(thermal: thermal, battery: battery, od_fps: odFPS)
        }

        @MainActor
        private func updateLabelsFacingCamera(_ cameraTransform: simd_float4x4) {
            guard !labelEntities.isEmpty else { return }

            // Throttle billboard updates (saves CPU)
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastBillboardUpdate < 0.08 { return } // ~12 Hz
            lastBillboardUpdate = now

            let camPos = SIMD3<Float>(cameraTransform.columns.3.x,
                                      cameraTransform.columns.3.y,
                                      cameraTransform.columns.3.z)

            for label in labelEntities {
                // World position of label
                let p = label.position(relativeTo: nil)
                let dir = camPos - p

                // Yaw-only rotation (keeps text upright)
                let yaw = atan2(dir.x, dir.z)
                let q = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))

                label.setOrientation(q, relativeTo: nil)
            }
        }



        private static func exifOrientation() -> CGImagePropertyOrientation {
            return .right
        }
    }
}
