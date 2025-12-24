//
//  SessionRecorder.swift
//  demo
//
//  Created by Mintesnot Shigutie on 12/24/25.
//



import Foundation
import simd
import UIKit

actor SessionRecorder {
    struct Pose: Codable {
        let t: [Float]     // x,y,z
        let q: [Float]     // x,y,z,w
    }

    struct DetectionRec: Codable {
        let label: String
        let score: Float
        let bbox: [Float]  // x,y,w,h (normalized, top-left)
    }

    struct Telemetry: Codable {
        let thermal: String
        let battery: Float
        let od_fps: Float?
    }

    struct Event: Codable {
        let type: String
        let ts: Double

        let pose: Pose?
        let detections: [DetectionRec]?
        let pin: DetectionRec?
        let world: [Float]?
        let telemetry: Telemetry?
        let meta: [String: String]?
    }

    private let sessionId: String
    private let dirURL: URL
    private let jsonlURL: URL
    private var handle: FileHandle?

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()

    init(appName: String = "demo") async  throws {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = iso.string(from: Date())

        self.sessionId = "\(appName)_\(ts)"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.dirURL = docs.appendingPathComponent("Sessions/\(sessionId)", isDirectory: true)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        self.jsonlURL = dirURL.appendingPathComponent("session.jsonl")

        FileManager.default.createFile(atPath: jsonlURL.path, contents: nil)
        self.handle = try FileHandle(forWritingTo: jsonlURL)

        // Start event
        let start = await Event(
            type: "start",
            ts: Date().timeIntervalSince1970,
            pose: nil,
            detections: nil,
            pin: nil,
            world: nil,
            telemetry: nil,
            meta: [
                "sessionId": sessionId,
                "device": UIDevice.current.model,
                "system": UIDevice.current.systemVersion
            ]
        )
        try append(start)
    }

    func url() -> URL { jsonlURL }

    func appendFrame(
        ts: Double,
        cameraTransform: simd_float4x4,
        detections: [Detection],
        telemetry: Telemetry
    ) throws {
        let pose = Self.makePose(cameraTransform)

        let dets: [DetectionRec] = detections.map {
            DetectionRec(label: $0.label,
                         score: $0.score,
                         bbox: [
                            Float($0.rect.origin.x),
                            Float($0.rect.origin.y),
                            Float($0.rect.size.width),
                            Float($0.rect.size.height)
                         ]
            )
        }

        let ev = Event(type: "frame",
                       ts: ts,
                       pose: pose,
                       detections: dets,
                       pin: nil,
                       world: nil,
                       telemetry: telemetry,
                       meta: nil)
        try append(ev)
    }

    func appendPin(
        ts: Double,
        cameraTransform: simd_float4x4,
        pinned: Detection,
        worldPosition: SIMD3<Float>,
        telemetry: Telemetry
    ) throws {
        let pose = Self.makePose(cameraTransform)
        let pin = DetectionRec(
                label: pinned.label,
                score: pinned.score,
                bbox: [
                    Float(pinned.rect.origin.x),
                    Float(pinned.rect.origin.y),
                    Float(pinned.rect.size.width),
                    Float(pinned.rect.size.height)
                ]
        )

        let ev = Event(type: "pin",
                       ts: ts,
                       pose: pose,
                       detections: nil,
                       pin: pin,
                       world: [worldPosition.x, worldPosition.y, worldPosition.z],
                       telemetry: telemetry,
                       meta: nil
                )
        try append(ev)
    }

    func finish() throws {
        let stop = Event(
                type: "stop",
                ts: Date().timeIntervalSince1970,
                pose: nil,
                detections: nil,
                pin: nil,
                world: nil,
                telemetry: nil,
                meta: ["sessionId": sessionId]
            )
        try append(stop)

        try handle?.synchronize()
        try handle?.close()
        handle = nil
    }

    // MARK: - Private

    private func append(_ ev: Event) throws {
        guard let handle else { return }
        let data = try encoder.encode(ev)
        handle.write(data)
        handle.write(Data([0x0A])) // newline for JSONL
    }

    private static func makePose(_ T: simd_float4x4) -> Pose {
        let t = SIMD3<Float>(T.columns.3.x, T.columns.3.y, T.columns.3.z)
        let q = simd_quatf(T)
        return Pose(t: [t.x, t.y, t.z], q: [q.vector.x, q.vector.y, q.vector.z, q.vector.w])
    }
}
