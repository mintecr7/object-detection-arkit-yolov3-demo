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
            BoxesOverlay(detections: state.detections).ignoresSafeArea().allowsHitTesting(false)
            VStack {
                HStack {
                    Spacer()
                    TrajectoryMiniMap(trajectory: state.trajectory, pins: state.pinned)
                        .frame(width: 170, height: 170)
                        .padding(.trailing, 12)
                        .padding(.top, 60)
                }
                Spacer()
            }


            VStack(spacing: 10) {
                HStack {
                    Text("Detections: \(state.detections.count)")
                        .padding(8).background(.black.opacity(0.6))
                        .foregroundStyle(.white).cornerRadius(8)

                    Spacer()

                    Text(state.status)
                        .lineLimit(1)
                        .padding(8).background(.black.opacity(0.6))
                        .foregroundStyle(.white).cornerRadius(8)
                }
                .padding(.horizontal)
                .padding(.top, 10)

                Spacer()

                if !state.pinned.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(state.pinned) { p in
                                Text("\(p.label) \(Int(p.score * 100))%  [\(String(format: "%.2f", p.worldPosition.x)), \(String(format: "%.2f", p.worldPosition.y)), \(String(format: "%.2f", p.worldPosition.z))]")
                                    .font(.caption2).foregroundStyle(.white)
                            }
                        }.padding(10)
                    }
                    .frame(maxHeight: 140)
                    .background(.black.opacity(0.55))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                HStack(spacing: 10) {
                    Button {
                        state.startSessionToken += 1
                    } label: {
                        Text(state.isRecording ? "Recording…" : "Start Session")
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isRecording)

                    Button {
                        state.stopSessionToken += 1
                    } label: {
                        Text("Stop")
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!state.isRecording)
                }
                .padding(.horizontal)

                HStack(spacing: 10) {
                    Button { state.pinRequestToken += 1 } label: {
                        Text("Pin Best").frame(maxWidth: .infinity, minHeight: 54)
                    }.buttonStyle(.borderedProminent)

                    Button { state.clearPinsToken += 1 } label: {
                        Text("Clear Pins").frame(maxWidth: .infinity, minHeight: 54)
                    }.buttonStyle(.bordered)
                }
                .padding(.horizontal)

                Button {
                    if state.exportURL != nil { state.showShareSheet = true }
                } label: {
                    Text("Export JSON")
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                .padding(.bottom, 18)
                .disabled(state.exportURL == nil)
            }
        }
        .sheet(isPresented: $state.showShareSheet) {
            if let url = state.exportURL {
                ShareSheet(items: [url])
            }
        }
    }
}

//#Preview {
//    ContentView()
//}
