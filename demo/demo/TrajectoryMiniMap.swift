//
//  TrajectoryMiniMap.swift
//  demo
//
//  Created by Mintesnot Shigutie on 12/24/25.
//



import simd
import SwiftUI

struct TrajectoryMiniMap: View {
    let trajectory: [PoseSample]
    let pins: [PinnedDetection]

    var body: some View {
        Canvas { context, size in
            guard trajectory.count >= 2 else {
                drawEmpty(context: context, size: size)
                return
            }

            // Use recent window for auto-scaling
            let pts = trajectory.map { SIMD2<Float>($0.position.x, $0.position.z) }
            let pinPts = pins.map { SIMD2<Float>($0.worldPosition.x, $0.worldPosition.z) }

            let all = pts + pinPts
            let minX = all.map{$0.x}.min() ?? 0
            let maxX = all.map{$0.x}.max() ?? 1
            let minY = all.map{$0.y}.min() ?? 0
            let maxY = all.map{$0.y}.max() ?? 1

            // Padding
            let pad: Float = 0.2
            let spanX = max(0.001, (maxX - minX) + pad)
            let spanY = max(0.001, (maxY - minY) + pad)

            func map(_ p: SIMD2<Float>) -> CGPoint {
                // Normalize into [0,1]
                let nx = (p.x - (minX - pad/2)) / spanX
                let ny = (p.y - (minY - pad/2)) / spanY
                // Fit into view; invert y so "forward" looks up
                return CGPoint(x: CGFloat(nx) * size.width,
                               y: (1 - CGFloat(ny)) * size.height)
            }

            // Draw path
            var path = Path()
            path.move(to: map(pts[0]))
            for p in pts.dropFirst() {
                path.addLine(to: map(p))
            }
            context.stroke(path, with: .color(.white.opacity(0.9)), lineWidth: 2)

            // Draw current position (last point)
            if let last = pts.last {
                let c = map(last)
                let r = CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: r), with: .color(.green))
            }

            // Draw pins
            for pin in pinPts {
                let c = map(pin)
                let r = CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: r), with: .color(.red))
            }

            // Border
            context.stroke(Path(CGRect(origin: .zero, size: size)),
                           with: .color(.white.opacity(0.25)), lineWidth: 1)
        }
        .background(.black.opacity(0.55))
        .cornerRadius(12)
    }

    private func drawEmpty(context: GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(rect), with: .color(.black.opacity(0.55)))
        context.stroke(Path(rect), with: .color(.white.opacity(0.25)), lineWidth: 1)
    }
}
