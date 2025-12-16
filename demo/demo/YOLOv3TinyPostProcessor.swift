//
//  YOLOv3TinyPostProcessor.swift
//  demo
//
//  Created by Mintesnot Shigutie on 12/16/25.
//


import Foundation
import Vision
import CoreML
import CoreGraphics
import simd

final class YOLOv3TinyPostProcessor {
    // YOLOv3-Tiny uses 2 heads, 3 anchors each, COCO = 80 classes => 85 values per anchor
    private let numClasses = 80
    private var valuesPerAnchor: Int { numClasses + 5 } // 85

    // Standard YOLOv3 anchors for 416 input (Tiny uses masks [3,4,5] and [0,1,2])
    // (w, h) in pixels relative to model input size
    private let anchors: [SIMD2<Float>] = [
        SIMD2(10,14), SIMD2(23,27), SIMD2(37,58),
        SIMD2(81,82), SIMD2(135,169), SIMD2(344,319)
    ]
    private let masksByGrid: [Int: [Int]] = [
        13: [3,4,5],
        26: [0,1,2]
    ]

    private let scoreThreshold: Float
    private let nmsThreshold: CGFloat

    init(scoreThreshold: Float = 0.45, nmsThreshold: CGFloat = 0.45) {
        self.scoreThreshold = scoreThreshold
        self.nmsThreshold = nmsThreshold
    }

    func process(_ observations: [VNObservation]) -> [Detection] {
        let arrays = observations.compactMap { $0 as? VNCoreMLFeatureValueObservation }
            .compactMap { $0.featureValue.multiArrayValue }

        // YOLOv3Tiny should yield 2 feature maps; if not, we still try best-effort.
        // Sort by total elements so we process larger grid (26) and smaller grid (13).
        let sorted = arrays.sorted { $0.count > $1.count }

        var dets: [Detection] = []
        for arr in sorted {
            dets.append(contentsOf: decodeOne(arr))
        }

        // NMS
        return nonMaxSuppression(dets, iouThreshold: nmsThreshold)
    }

    // MARK: - Decode

    private func sigmoid(_ x: Float) -> Float { 1 / (1 + exp(-x)) }

    private func decodeOne(_ arr: MLMultiArray) -> [Detection] {
        guard let layout = MultiArrayLayout(arr) else { return [] }
        let H = layout.gridH
        let W = layout.gridW
        guard let mask = masksByGrid[H] ?? masksByGrid[W] else {
            // If grid is unexpected, skip gracefully.
            return []
        }

        // Expect channels = 3 * 85 = 255 (Tiny head)
        if layout.channels != 3 * valuesPerAnchor { return [] }

        var out: [Detection] = []
        out.reserveCapacity(64)

        // Iterate grid cells and 3 anchors
        for gy in 0..<H {
            for gx in 0..<W {
                for a in 0..<3 {
                    let anchorIndex = mask[a]
                    let baseC = a * valuesPerAnchor

                    let tx = layout.read(gx: gx, gy: gy, c: baseC + 0)
                    let ty = layout.read(gx: gx, gy: gy, c: baseC + 1)
                    let tw = layout.read(gx: gx, gy: gy, c: baseC + 2)
                    let th = layout.read(gx: gx, gy: gy, c: baseC + 3)
                    let to = layout.read(gx: gx, gy: gy, c: baseC + 4)

                    let objectness = sigmoid(to)
                    if objectness < 0.01 { continue }

                    // Best class
                    var bestClass = 0
                    var bestProb: Float = 0
                    for cls in 0..<numClasses {
                        let p = sigmoid(layout.read(gx: gx, gy: gy, c: baseC + 5 + cls))
                        if p > bestProb { bestProb = p; bestClass = cls }
                    }

                    let score = objectness * bestProb
                    if score < scoreThreshold { continue }

                    // Decode box in normalized coordinates
                    let bx = (sigmoid(tx) + Float(gx)) / Float(W)
                    let by = (sigmoid(ty) + Float(gy)) / Float(H)

                    let aw = anchors[anchorIndex].x
                    let ah = anchors[anchorIndex].y

                    // YOLO: bw = anchor * exp(tw) / inputSize
                    // We can normalize by grid scale using W/H directly:
                    // input is 416, stride = 416 / W
                    let stride = 416.0 / Float(W)
                    let bw = (aw * exp(tw)) / (stride * Float(W)) // equivalent to /416
                    let bh = (ah * exp(th)) / (stride * Float(H))

                    let x = CGFloat(bx - bw / 2)
                    let y = CGFloat(by - bh / 2)
                    let w = CGFloat(bw)
                    let h = CGFloat(bh)

                    let rect = CGRect(x: x, y: y, width: w, height: h)
                        .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))

                    if rect.isNull || rect.width <= 0 || rect.height <= 0 { continue }

                    out.append(Detection(
                        classIndex: bestClass,
                        label: bestClass < cocoLabels.count ? cocoLabels[bestClass] : "cls\(bestClass)",
                        score: score,
                        rect: rect
                    ))
                }
            }
        }

        return out
    }
}

/// A tiny helper that makes YOLO tensor access robust across common Core ML layouts.
/// Supports these common shapes:
/// - [1, 255, H, W]  (NCHW)
/// - [1, H, W, 255]  (NHWC)
private struct MultiArrayLayout {
    let arr: MLMultiArray
    let ptr: UnsafeMutablePointer<Float32>

    let gridH: Int
    let gridW: Int
    let channels: Int

    // Strides in elements
    let s0: Int, s1: Int, s2: Int, s3: Int
    // Indices mapping
    enum Kind { case nchw, nhwc }
    let kind: Kind

    init?(_ arr: MLMultiArray) {
        guard arr.dataType == .float32 else { return nil }
        self.arr = arr
        self.ptr = UnsafeMutablePointer<Float32>(OpaquePointer(arr.dataPointer))

        let shape = arr.shape.map { Int(truncating: $0) }
        let strides = arr.strides.map { Int(truncating: $0) }

        guard shape.count == 4 else { return nil }
        (s0, s1, s2, s3) = (strides[0], strides[1], strides[2], strides[3])

        // Detect where "255" is (channels)
        if shape[1] == 255 {
            // [N, C, H, W]
            kind = .nchw
            channels = shape[1]
            gridH = shape[2]
            gridW = shape[3]
        } else if shape[3] == 255 {
            // [N, H, W, C]
            kind = .nhwc
            channels = shape[3]
            gridH = shape[1]
            gridW = shape[2]
        } else {
            return nil
        }
    }

    @inline(__always)
    func read(gx: Int, gy: Int, c: Int) -> Float {
        switch kind {
        case .nchw:
            // [0, c, gy, gx]
            let idx = 0*s0 + c*s1 + gy*s2 + gx*s3
            return ptr[idx]
        case .nhwc:
            // [0, gy, gx, c]
            let idx = 0*s0 + gy*s1 + gx*s2 + c*s3
            return ptr[idx]
        }
    }
}
