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
            ARViewContainer(state: state).ignoresSafeArea()
            BoxesOverlay(detections: state.detections).ignoresSafeArea()

            VStack {
                HStack {
                    Text("Detections: \(state.detections.count)")
                        .padding(8)
                        .background(.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .cornerRadius(8)
                    Spacer()
                }
                .padding()
                Spacer()
            }
        }

    }
}

//#Preview {
//    ContentView()
//}
