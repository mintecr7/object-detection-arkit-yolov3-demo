//
//  NMS.swift
//  demo
//
//  Created by Mintesnot Shigutie on 12/16/25.
//


import CoreGraphics

func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
    let inter = a.intersection(b)
    if inter.isNull || inter.width <= 0 || inter.height <= 0 { return 0 }
    let interArea = inter.width * inter.height
    let unionArea = a.width * a.height + b.width * b.height - interArea
    return unionArea > 0 ? (interArea / unionArea) : 0
}

func nonMaxSuppression(_ dets: [Detection], iouThreshold: CGFloat) -> [Detection] {
    // Per-class NMS (more stable visually)
    let grouped = Dictionary(grouping: dets, by: { $0.classIndex })
    var out: [Detection] = []
    out.reserveCapacity(dets.count)

    for (_, group) in grouped {
        let sorted = group.sorted { $0.score > $1.score }
        var kept: [Detection] = []

        for d in sorted {
            var shouldKeep = true
            for k in kept {
                if iou(d.rect, k.rect) > iouThreshold {
                    shouldKeep = false
                    break
                }
            }
            if shouldKeep { kept.append(d) }
        }
        out.append(contentsOf: kept)
    }
    return out
}
