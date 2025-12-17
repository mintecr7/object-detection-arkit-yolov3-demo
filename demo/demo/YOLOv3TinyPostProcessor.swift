//
//  YOLOv3TinyPostProcessor.swift
//  demo
//
//  Created by Mintesnot Shigutie on 12/16/25.
//


import simd
import Vision
import CoreML
import Foundation
import CoreGraphics

final class YOLOv3TinyPostProcessor {
    // YOLOv3-Tiny uses 2 heads, 3 anchors each, COCO = 80 classes => 85 values per anchor
    private var didLog = false
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

    init(scoreThreshold: Float = 0.20, nmsThreshold: CGFloat = 0.45) {
        self.scoreThreshold = scoreThreshold
        self.nmsThreshold = nmsThreshold
    }

    func process(_ observations: [VNObservation]) -> [Detection] {
        if !didLog {
                didLog = true
                print("Vision observations count =", observations.count)
                for o in observations {
                    print(" - type:", String(describing: type(of: o)))
                    if let f = o as? VNCoreMLFeatureValueObservation,
                       let arr = f.featureValue.multiArrayValue {
                        print("   feature:", f.featureName,
                              "shape:", arr.shape,
                              "strides:", arr.strides,
                              "dtype:", arr.dataType)
                    }
                }
            }
        let ros = observations.compactMap { $0 as? VNRecognizedObjectObservation }
          if !ros.isEmpty {
              return ros.compactMap { ro in
                  guard let top = ro.labels.first else { return nil }
                  let bb = ro.boundingBox
                  // Vision BB origin is bottom-left; your overlay assumes top-left
                  let rect = CGRect(
                      x: bb.origin.x,
                      y: 1 - bb.origin.y - bb.height,
                      width: bb.width,
                      height: bb.height
                  )
                  return Detection(classIndex: -1, label: top.identifier, score: Float(top.confidence), rect: rect)
              }
          }
        let feats = observations.compactMap { $0 as? VNCoreMLFeatureValueObservation }

            if !feats.isEmpty {
                for f in feats {
                    if let arr = f.featureValue.multiArrayValue {
                        print("YOLO out:", f.featureName,
                              "shape:", arr.shape,
                              "strides:", arr.strides,
                              "type:", arr.dataType)
                    } else {
                        print("YOLO out:", f.featureName, "non-multiarray:", f.featureValue.type)
                    }
                }
            }

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
                    let inputSize: Float = 416.0
                    let bw = (aw * exp(tw)) / inputSize
                    let bh = (ah * exp(th)) / inputSize


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

    let gridH: Int
    let gridW: Int
    let channels: Int

    // Strides in elements
    let strides: [Int]
    let shape: [Int]

    enum Kind { case nchw, nhwc, chw, hwc }
    let kind: Kind

    init?(_ arr: MLMultiArray) {
        self.arr = arr
        self.shape = arr.shape.map { Int(truncating: $0) }
        self.strides = arr.strides.map { Int(truncating: $0) }

        // Expected channels = 255 for YOLOv3-tiny heads
        // Support shapes:
        // [1,255,H,W], [1,H,W,255], [255,H,W], [H,W,255]
        if shape.count == 4, shape[1] == 255 {
            kind = .nchw
            channels = 255
            gridH = shape[2]
            gridW = shape[3]
        } else if shape.count == 4, shape[3] == 255 {
            kind = .nhwc
            channels = 255
            gridH = shape[1]
            gridW = shape[2]
        } else if shape.count == 3, shape[0] == 255 {
            kind = .chw
            channels = 255
            gridH = shape[1]
            gridW = shape[2]
        } else if shape.count == 3, shape[2] == 255 {
            kind = .hwc
            channels = 255
            gridH = shape[0]
            gridW = shape[1]
        } else {
            return nil
        }
    }

    @inline(__always)
    func read(gx: Int, gy: Int, c: Int) -> Float {
        let idx: Int
        switch kind {
        case .nchw:
            // [0, c, gy, gx]
            idx = 0*strides[0] + c*strides[1] + gy*strides[2] + gx*strides[3]
        case .nhwc:
            // [0, gy, gx, c]
            idx = 0*strides[0] + gy*strides[1] + gx*strides[2] + c*strides[3]
        case .chw:
            // [c, gy, gx]
            idx = c*strides[0] + gy*strides[1] + gx*strides[2]
        case .hwc:
            // [gy, gx, c]
            idx = gy*strides[0] + gx*strides[1] + c*strides[2]
        }

        switch arr.dataType {
        case .float32:
            let p = arr.dataPointer.assumingMemoryBound(to: Float32.self)
            return Float(p[idx])
        case .float16:
            let p = arr.dataPointer.assumingMemoryBound(to: UInt16.self)
            return Float(Float16(bitPattern: p[idx]))
        case .double:
            let p = arr.dataPointer.assumingMemoryBound(to: Double.self)
            return Float(p[idx])
        default:
            // Fallback (slow) – should rarely happen
            return (arr[[NSNumber(value: idx)]] ).floatValue
        }
    }
}
