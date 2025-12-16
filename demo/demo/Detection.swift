//
//  Detection.swift
//  demo
//
//  Created by Mintesnot Shigutie on 12/16/25.
//


import CoreGraphics
import Foundation

struct Detection: Identifiable {
    let id = UUID()
    let classIndex: Int
    let label: String
    let score: Float
    /// Normalized rect in [0,1] with origin at top-left.
    let rect: CGRect
}
