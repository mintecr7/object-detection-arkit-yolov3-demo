//
//  AppState.swift
//  demo
//
//  Created by Mintesnot Shigutie on 12/16/25.
//


import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var detections: [Detection] = []
}
