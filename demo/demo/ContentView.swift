//
//  ContentView.swift
//  demo
//
//  Created by Mintesnot Shigutie on 12/16/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var state = AppState()

    var body: some View {
        ZStack {
            ARViewContainer(state: state)
                .ignoresSafeArea()

            BoxesOverlay(detections: state.detections)
                .ignoresSafeArea()
        }
    }
}

#Preview {
    ContentView()
}
