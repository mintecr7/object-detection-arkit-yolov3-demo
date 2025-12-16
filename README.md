# object-detection-arkit-yolov3-demo

This repository contains a **time-boxed demo MVP** that showcases:
- **ARKit world tracking** (pose as an odometry/SLAM proxy)
- **On-device Object Detection** using **Apple YOLOv3 / YOLOv3-Tiny (Core ML)**
- **Real-time visualization** (2D bounding boxes + optional 3D pinning via raycast)
- **Session logging/export** (timestamped pose + detections + optional thumbnails)
- **Basic performance awareness** (OD FPS, thermal state, battery level)


---

## Target Outcome for the Meeting Demo

**One-screen “Inspection MVP”**
1. Start session
2. Live camera view (ARKit running)
3. YOLO detections overlaid in real time
4. Each detection can be **pinned into 3D** (raycast) and appears as a world-anchored marker
5. Export a session package (`.jsonl` + optional thumbnails) via Share Sheet

---

## Scope (What This Demo Is / Is Not)

### In scope
- ARKit pose tracking (odometry proxy)
- On-device object detection with Core ML
- 2D overlay + 3D marker placement
- Timestamp synchronization of pose + detections
- Session export and basic telemetry overlay

### Out of scope (intentionally)
- Client proprietary SLAM/odometry integration
- Windows 3-pane viewer and model alignment UI
- Defect-grade model accuracy (YOLO is generic)

---

## Tech Stack

- iOS: Swift
- AR: ARKit (WorldTracking + Raycast)
- ML: Core ML + Vision (VNCoreMLRequest)
- Rendering: RealityKit (preferred) or ARKit overlay layers
- Data export: JSON Lines (`.jsonl`) + optional JPG thumbnails

---

## Requirements

- Xcode: 15+ recommended
- iOS: iOS 17+ recommended
- Device: **iPhone Pro** with LiDAR (for best raycast stability; demo will still run without LiDAR but pinning may be less reliable)
- Apple Developer account for device deployment (standard)

---

## Getting Started

### 1) Create the project
- Xcode → New Project → iOS App
- Interface: SwiftUI (recommended for speed) or UIKit
- Include ARKit + RealityKit capabilities

### 2) Add the YOLOv3 Core ML model
- Download **YOLOv3** or **YOLOv3-Tiny** (`.mlmodel`) from Apple’s Core ML model gallery
- Drag the `.mlmodel` into the Xcode project target
- Confirm the model compiles (Xcode generates a model class)

> Note: Apple’s YOLO models typically require **post-processing** (decode + NMS). This repo will include a lightweight post-processing module for demo purposes.

### 3) Run on device
- Set signing team
- Select your iPhone Pro
- Build & Run

---

## Demo Flow (Suggested Script)

1. Tap **Start**
2. Show live detections (boxes + labels)
3. Move around; point to a known object; show stable detections
4. Tap **Pin** (or auto-pin) → markers appear in space and remain anchored
5. Tap **Stop**
6. Tap **Export** → share the session package

---

## Performance Strategy (Critical for Credibility)

To avoid thermal spikes and lag:
- Run OD on a **throttled schedule** (e.g., 5–10 FPS), not every frame
- Apply backpressure (skip frames while inference is in flight)
- Keep rendering lightweight
- Display:
  - OD FPS
  - Thermal state (`ProcessInfo.thermalState`)
  - Battery level

---

## Data Output Format (Draft)

Session output is written as **JSON Lines** (`session.jsonl`) for simple streaming and incremental processing.

Example line:
```json
{
  "ts": 12345.678,
  "pose": {
    "t": [x, y, z],
    "q": [qx, qy, qz, qw]
  },
  "detections": [
    {
      "label": "person",
      "conf": 0.87,
      "bbox": [x, y, w, h],
      "pinned": true,
      "world": [X, Y, Z]
    }
  ],
  "telemetry": {
    "od_fps": 8.2,
    "thermal": "fair",
    "battery": 0.62
  }
}