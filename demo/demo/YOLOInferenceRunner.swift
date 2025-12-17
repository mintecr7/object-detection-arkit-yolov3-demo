//
//  YOLOInferenceRunner.swift
//  demo
//
//  Created by Mintesnot Shigutie on 12/16/25.
//


import Vision
import CoreML
import ImageIO
import QuartzCore

final class YOLOInferenceRunner {
    private var inFlight = false
    private let vnModel: VNCoreMLModel
    private let request: VNCoreMLRequest
    private let queue = DispatchQueue(label: "ml.yolo.inference", qos: .userInitiated)
    private let post = YOLOv3TinyPostProcessor(scoreThreshold: 0.45, nmsThreshold: 0.45)


    // Simple throttling (adjust later)
    private var lastRunTime: CFTimeInterval = 0
    private let minInterval: CFTimeInterval = 0.12   // ~8 FPS

    init() throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all

        // Xcode will generate this class name from the .mlmodel filename.
        // If you used YOLOv3TinyFP16.mlmodel, the class is usually YOLOv3TinyFP16.
        let coreMLModel = try YOLOv3Tiny(configuration: config).model

        self.vnModel = try VNCoreMLModel(for: coreMLModel)
        self.request = VNCoreMLRequest(model: vnModel)
        self.request.imageCropAndScaleOption = .scaleFill
    }

    func run(pixelBuffer: CVPixelBuffer,
             orientation: CGImagePropertyOrientation,
             completion: @escaping ([Detection]) -> Void) {

        let now = CACurrentMediaTime()
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
                let results = self.request.results ?? []
                print("VNCoreMLRequest results count:", results.count)
                
                let dets = self.post.process(results)
                DispatchQueue.main.async {
                    completion(dets)
                }

            } catch {
                // For now: log and keep going
                print("YOLO inference error:", error)
            }
        }
    }
}
