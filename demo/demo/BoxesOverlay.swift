//
//  BoxesOverlay.swift
//  demo
//
//  Created by Mintesnot Shigutie on 12/16/25.
//


import SwiftUI

struct BoxesOverlay: View {
    let detections: [Detection]

    var body: some View {
        GeometryReader { geo in
            ForEach(detections) { d in
                let r = denormalize(d.rect, size: geo.size)
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .path(in: r)
                        .stroke(Color.green, lineWidth: 2)

                    Text("\(d.label) \(Int(d.score * 100))%")
                        .font(.caption2)
                        .padding(4)
                        .background(.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .offset(x: r.minX, y: max(0, r.minY - 18))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func denormalize(_ rect: CGRect, size: CGSize) -> CGRect {
        CGRect(
            x: rect.origin.x * size.width,
            y: rect.origin.y * size.height,
            width: rect.size.width * size.width,
            height: rect.size.height * size.height
        )
    }
}
