//
//  AppState.swift
//  demo
//
//  Created by Mintesnot Shigutie on 12/16/25.
//


import simd
import Foundation

struct PoseSample: Identifiable {
    let id = UUID()
    let t: TimeInterval
    let position: SIMD3<Float>   // world
}

struct PinnedDetection: Identifiable {
    let id = UUID()
    let ts: TimeInterval
    let label: String
    let score: Float
    let worldPosition: SIMD3<Float>
}

@MainActor
final class AppState: ObservableObject {
    @Published var detections: [Detection] = []
    @Published var pinned: [PinnedDetection] = []
    
    /// Slam
    @Published var trajectory: [PoseSample] = []


    @Published var status: String = ""
    @Published var isRecording: Bool = false

    /// Actions
    @Published var pinRequestToken: Int = 0
    @Published var clearPinsToken: Int = 0
    @Published var startSessionToken: Int = 0
    @Published var stopSessionToken: Int = 0

    /// Export
    @Published var exportURL: URL? = nil
    @Published var showShareSheet: Bool = false
}
