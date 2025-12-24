//
//  YOLOInferenceRunner.swift
//  demo
//
//  Created by Mintesnot Shigutie on 12/16/25.
//


import Vision
import CoreML
import ImageIO

final class YOLOInferenceRunner {
    private let request: VNCoreMLRequest
    private let queue = DispatchQueue(label: "ml.yolo.inference", qos: .userInitiated)

    private var lastRunTime: TimeInterval = 0
    private let minInterval: TimeInterval = 0.12   // ~8 FPS
    private var inFlight = false

    // Tweak for demo
    private let minConfidence: Float = 0.30
    private let maxBoxes = 20

    init() throws {
        
        let config = MLModelConfiguration()
        config.computeUnits = .all

        let coreMLModel = try YOLOv3Tiny(configuration: config).model
        let vnModel = try VNCoreMLModel(for: coreMLModel)

        self.request = VNCoreMLRequest(model: vnModel)
        // Match ARView's “fill” behavior (usually best alignment)
        self.request.imageCropAndScaleOption = .scaleFill
    }

    func run(pixelBuffer: CVPixelBuffer,
             orientation: CGImagePropertyOrientation,
             completion: @escaping ([Detection]) -> Void) {

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastRunTime >= minInterval else { return }
        guard !inFlight else { return }
        lastRunTime = now
        inFlight = true

        queue.async {
            defer { self.inFlight = false }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                orientation: orientation,
                                                options: [:])
            do {
                try handler.perform([self.request])

                let ros = (self.request.results as? [VNRecognizedObjectObservation]) ?? []

                // Convert to your Detection model (IMPORTANT: flip Y)
                var dets: [Detection] = ros.compactMap { ro in
                    guard let top = ro.labels.first else { return nil }
                    let bb = ro.boundingBox  // normalized, origin is bottom-left

                    let rectTopLeft = CGRect(
                        x: bb.origin.x,
                        y: 1 - bb.origin.y - bb.size.height,
                        width: bb.size.width,
                        height: bb.size.height
                    )

                    return Detection(
                        classIndex: -1,
                        label: top.identifier,
                        score: Float(top.confidence),
                        rect: rectTopLeft
                    )
                }

                dets = dets
                    .filter { $0.score >= self.minConfidence }
                    .sorted { $0.score > $1.score }

                if dets.count > self.maxBoxes { dets = Array(dets.prefix(self.maxBoxes)) }

                DispatchQueue.main.async { completion(dets) }
            } catch {
                print("YOLO inference error:", error)
            }
        }
    }
}
