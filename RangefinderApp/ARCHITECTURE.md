# SniperScope - Application Architecture Design

## Overview

SniperScope is a passive camera-based rangefinding application for iOS that estimates distances to targets up to 1000 yards without laser emission. It combines object detection, monocular depth estimation, and size-based triangulation.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SniperScope App                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │
│  │   Camera    │    │   Vision    │    │   Ranging   │    │     UI      │  │
│  │   Module    │───▶│   Pipeline  │───▶│   Engine    │───▶│   Layer     │  │
│  └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘  │
│         │                  │                  │                  │          │
│         ▼                  ▼                  ▼                  ▼          │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │
│  │ AVFoundation│    │  Core ML    │    │   Fusion    │    │   SwiftUI   │  │
│  │ Calibration │    │  Models     │    │   Kalman    │    │   Overlay   │  │
│  └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Core Modules

### 1. Camera Module (`CameraManager`)

Handles all camera operations and calibration data extraction.

```swift
// CameraManager.swift

class CameraManager: NSObject, ObservableObject {
    // MARK: - Properties
    @Published var isRunning = false
    @Published var currentFrame: CVPixelBuffer?
    @Published var cameraIntrinsics: CameraIntrinsics?

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let calibrationQueue = DispatchQueue(label: "calibration")

    // MARK: - Camera Intrinsics
    struct CameraIntrinsics {
        let focalLengthX: Float      // fx in pixels
        let focalLengthY: Float      // fy in pixels
        let principalPointX: Float   // cx
        let principalPointY: Float   // cy
        let referenceWidth: Int
        let referenceHeight: Int

        var focalLengthMM: Float {
            // Convert to mm using sensor size
            // iPhone sensor pitch ~1.22 microns
            return focalLengthX * 0.00122
        }
    }

    // MARK: - Configuration
    func configure() async throws {
        captureSession.sessionPreset = .hd4K3840x2160  // Max resolution for small objects

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.deviceNotFound
        }

        let input = try AVCaptureDeviceInput(device: device)
        captureSession.addInput(input)

        // Enable intrinsics delivery
        videoOutput.setSampleBufferDelegate(self, queue: calibrationQueue)
        captureSession.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            connection.isCameraIntrinsicMatrixDeliveryEnabled = true
        }
    }

    // MARK: - Intrinsics Extraction
    func extractIntrinsics(from sampleBuffer: CMSampleBuffer) -> CameraIntrinsics? {
        guard let attachment = CMGetAttachment(
            sampleBuffer,
            key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
            attachmentModeOut: nil
        ) as? Data else { return nil }

        let matrix = attachment.withUnsafeBytes {
            $0.load(as: matrix_float3x3.self)
        }

        return CameraIntrinsics(
            focalLengthX: matrix.columns.0.x,
            focalLengthY: matrix.columns.1.y,
            principalPointX: matrix.columns.2.x,
            principalPointY: matrix.columns.2.y,
            referenceWidth: 3840,
            referenceHeight: 2160
        )
    }
}
```

### 2. Vision Pipeline (`VisionPipeline`)

Orchestrates ML model inference for object detection and depth estimation.

```swift
// VisionPipeline.swift

class VisionPipeline: ObservableObject {
    // MARK: - Models
    private var objectDetector: VNCoreMLModel?
    private var depthEstimator: VNCoreMLModel?

    // MARK: - Results
    @Published var detections: [Detection] = []
    @Published var depthMap: CVPixelBuffer?

    // MARK: - Detection Result
    struct Detection {
        let label: String
        let confidence: Float
        let boundingBox: CGRect      // Normalized coordinates
        let pixelBoundingBox: CGRect // Pixel coordinates
        let knownSize: KnownObjectSize?
    }

    // MARK: - Initialization
    func loadModels() async throws {
        // Load object detection model (YOLO11)
        let detectorConfig = MLModelConfiguration()
        detectorConfig.computeUnits = .all  // Use Neural Engine

        let detectorURL = Bundle.main.url(forResource: "SniperScope_Detector", withExtension: "mlmodelc")!
        let detectorModel = try await MLModel.load(contentsOf: detectorURL, configuration: detectorConfig)
        objectDetector = try VNCoreMLModel(for: detectorModel)

        // Load depth estimation model (Depth Anything V2)
        let depthURL = Bundle.main.url(forResource: "DepthAnythingV2_Small", withExtension: "mlmodelc")!
        let depthModel = try await MLModel.load(contentsOf: depthURL, configuration: detectorConfig)
        depthEstimator = try VNCoreMLModel(for: depthModel)
    }

    // MARK: - Processing
    func process(pixelBuffer: CVPixelBuffer, intrinsics: CameraIntrinsics) async -> VisionResult {
        async let detections = runObjectDetection(pixelBuffer)
        async let depthMap = runDepthEstimation(pixelBuffer)

        return VisionResult(
            detections: await detections,
            depthMap: await depthMap,
            intrinsics: intrinsics
        )
    }

    private func runObjectDetection(_ pixelBuffer: CVPixelBuffer) async -> [Detection] {
        guard let model = objectDetector else { return [] }

        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])

        guard let results = request.results as? [VNRecognizedObjectObservation] else { return [] }

        let imageWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let imageHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        return results.compactMap { observation in
            guard let label = observation.labels.first else { return nil }

            let normalizedBox = observation.boundingBox
            let pixelBox = CGRect(
                x: normalizedBox.origin.x * imageWidth,
                y: (1 - normalizedBox.origin.y - normalizedBox.height) * imageHeight,
                width: normalizedBox.width * imageWidth,
                height: normalizedBox.height * imageHeight
            )

            return Detection(
                label: label.identifier,
                confidence: label.confidence,
                boundingBox: normalizedBox,
                pixelBoundingBox: pixelBox,
                knownSize: KnownObjectDatabase.shared.getSize(for: label.identifier)
            )
        }
    }

    private func runDepthEstimation(_ pixelBuffer: CVPixelBuffer) async -> CVPixelBuffer? {
        guard let model = depthEstimator else { return nil }

        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])

        guard let result = request.results?.first as? VNPixelBufferObservation else { return nil }
        return result.pixelBuffer
    }
}
```

### 3. Ranging Engine (`RangingEngine`)

Calculates distance using multiple methods and fuses results.

```swift
// RangingEngine.swift

class RangingEngine: ObservableObject {
    // MARK: - Results
    @Published var currentRange: RangeEstimate?

    // MARK: - Fusion
    private var kalmanFilter = KalmanFilter()
    private var temporalBuffer: [RangeEstimate] = []

    // MARK: - Range Estimate
    struct RangeEstimate {
        let distance: Measurement<UnitLength>  // Primary estimate
        let confidence: Float                   // 0-1
        let method: RangingMethod
        let uncertainty: Measurement<UnitLength>
        let components: [RangeComponent]

        var distanceYards: Double {
            distance.converted(to: .yards).value
        }

        var distanceMeters: Double {
            distance.converted(to: .meters).value
        }
    }

    struct RangeComponent {
        let method: RangingMethod
        let distance: Double  // meters
        let confidence: Float
        let weight: Float
    }

    enum RangingMethod {
        case sizeBasedHuman
        case sizeBasedVehicle
        case sizeBasedWildlife
        case sizeBasedGeneric
        case monocularDepth
        case atmosphericHaze
        case fused
    }

    // MARK: - Distance Calculation
    func calculateRange(from visionResult: VisionResult) -> RangeEstimate {
        var components: [RangeComponent] = []

        // Method 1: Size-based ranging for each detection with known size
        for detection in visionResult.detections {
            if let sizeEstimate = calculateSizeBasedRange(
                detection: detection,
                intrinsics: visionResult.intrinsics
            ) {
                components.append(sizeEstimate)
            }
        }

        // Method 2: Monocular depth estimation
        if let depthEstimate = calculateDepthBasedRange(
            depthMap: visionResult.depthMap,
            targetRegion: visionResult.detections.first?.boundingBox
        ) {
            components.append(depthEstimate)
        }

        // Method 3: Atmospheric analysis (supplementary)
        if let hazeEstimate = calculateAtmosphericRange(
            image: visionResult.originalImage,
            targetRegion: visionResult.detections.first?.boundingBox
        ) {
            components.append(hazeEstimate)
        }

        // Fuse all estimates
        return fuseEstimates(components)
    }

    // MARK: - Size-Based Ranging
    private func calculateSizeBasedRange(
        detection: VisionPipeline.Detection,
        intrinsics: CameraManager.CameraIntrinsics
    ) -> RangeComponent? {
        guard let knownSize = detection.knownSize else { return nil }

        // Use height for humans/animals, width for vehicles
        let pixelSize: CGFloat
        let realSize: Double

        switch knownSize.measurementType {
        case .height:
            pixelSize = detection.pixelBoundingBox.height
            realSize = knownSize.sizeMeters
        case .width:
            pixelSize = detection.pixelBoundingBox.width
            realSize = knownSize.sizeMeters
        case .diagonal:
            pixelSize = sqrt(pow(detection.pixelBoundingBox.width, 2) +
                           pow(detection.pixelBoundingBox.height, 2))
            realSize = knownSize.sizeMeters
        }

        // Pinhole camera model: Distance = (RealSize × FocalLength) / PixelSize
        let focalLength = Double(intrinsics.focalLengthY)  // Use Y for height
        let distance = (realSize * focalLength) / Double(pixelSize)

        // Calculate confidence based on:
        // - Detection confidence
        // - Object size variability
        // - Pixel measurement precision
        let confidence = calculateSizeConfidence(
            detection: detection,
            knownSize: knownSize,
            pixelSize: pixelSize
        )

        return RangeComponent(
            method: methodForObjectType(knownSize.objectType),
            distance: distance,
            confidence: confidence,
            weight: confidence * knownSize.reliabilityWeight
        )
    }

    private func calculateSizeConfidence(
        detection: VisionPipeline.Detection,
        knownSize: KnownObjectSize,
        pixelSize: CGFloat
    ) -> Float {
        // Base confidence from detection
        var confidence = detection.confidence

        // Reduce confidence for small pixel sizes (more error-prone)
        if pixelSize < 50 {
            confidence *= Float(pixelSize / 50)
        }

        // Reduce confidence based on object size variability
        confidence *= (1.0 - knownSize.sizeVariability)

        // Reduce confidence if partially occluded (aspect ratio check)
        let expectedAspect = knownSize.expectedAspectRatio
        let actualAspect = Float(detection.pixelBoundingBox.width / detection.pixelBoundingBox.height)
        let aspectDiff = abs(expectedAspect - actualAspect) / expectedAspect
        if aspectDiff > 0.3 {
            confidence *= 0.7  // Likely occluded
        }

        return min(confidence, 1.0)
    }

    // MARK: - Depth-Based Ranging
    private func calculateDepthBasedRange(
        depthMap: CVPixelBuffer?,
        targetRegion: CGRect?
    ) -> RangeComponent? {
        guard let depthMap = depthMap,
              let region = targetRegion else { return nil }

        // Extract depth values from target region
        let depthValues = extractDepthValues(from: depthMap, region: region)

        // Use median to reduce noise
        let medianDepth = depthValues.sorted()[depthValues.count / 2]

        // Depth Anything V2 outputs relative depth
        // We need to scale it using a reference or known object
        // For now, use calibrated scale factor
        let scaledDepth = Double(medianDepth) * depthScaleFactor

        return RangeComponent(
            method: .monocularDepth,
            distance: scaledDepth,
            confidence: 0.6,  // Monocular depth has inherent uncertainty
            weight: 0.3
        )
    }

    // MARK: - Estimate Fusion
    private func fuseEstimates(_ components: [RangeComponent]) -> RangeEstimate {
        guard !components.isEmpty else {
            return RangeEstimate(
                distance: Measurement(value: 0, unit: .meters),
                confidence: 0,
                method: .fused,
                uncertainty: Measurement(value: 0, unit: .meters),
                components: []
            )
        }

        // Weighted average
        let totalWeight = components.reduce(0) { $0 + $1.weight }
        let weightedDistance = components.reduce(0.0) {
            $0 + $1.distance * Double($1.weight)
        } / Double(totalWeight)

        // Apply Kalman filter for temporal smoothing
        let filteredDistance = kalmanFilter.update(measurement: weightedDistance)

        // Calculate uncertainty
        let variance = components.reduce(0.0) { sum, comp in
            let diff = comp.distance - weightedDistance
            return sum + diff * diff * Double(comp.weight)
        } / Double(totalWeight)
        let uncertainty = sqrt(variance)

        // Overall confidence
        let confidence = components.max(by: { $0.confidence < $1.confidence })?.confidence ?? 0

        return RangeEstimate(
            distance: Measurement(value: filteredDistance, unit: .meters),
            confidence: confidence,
            method: .fused,
            uncertainty: Measurement(value: uncertainty, unit: .meters),
            components: components
        )
    }
}
```

### 4. Known Object Database (`KnownObjectDatabase`)

Maintains real-world sizes for detectable objects.

```swift
// KnownObjectDatabase.swift

class KnownObjectDatabase {
    static let shared = KnownObjectDatabase()

    // MARK: - Object Size Definition
    struct KnownObjectSize {
        let objectType: ObjectType
        let label: String
        let sizeMeters: Double
        let measurementType: MeasurementType
        let sizeVariability: Float      // 0-1, how much size varies
        let reliabilityWeight: Float    // How reliable for ranging
        let expectedAspectRatio: Float  // Width/Height

        enum MeasurementType {
            case height
            case width
            case diagonal
        }
    }

    enum ObjectType {
        case human
        case vehicle
        case wildlife
        case structure
        case sign
    }

    // MARK: - Size Database
    private let sizeDatabase: [String: KnownObjectSize] = [
        // Humans
        "person": KnownObjectSize(
            objectType: .human,
            label: "person",
            sizeMeters: 1.75,           // Average adult height
            measurementType: .height,
            sizeVariability: 0.12,      // ~12% variation
            reliabilityWeight: 0.9,
            expectedAspectRatio: 0.4    // Width/Height
        ),
        "person_head": KnownObjectSize(
            objectType: .human,
            label: "person_head",
            sizeMeters: 0.24,           // Average head height
            measurementType: .height,
            sizeVariability: 0.08,
            reliabilityWeight: 0.85,
            expectedAspectRatio: 0.85
        ),

        // Vehicles
        "car": KnownObjectSize(
            objectType: .vehicle,
            label: "car",
            sizeMeters: 1.45,           // Average sedan height
            measurementType: .height,
            sizeVariability: 0.15,
            reliabilityWeight: 0.85,
            expectedAspectRatio: 2.5
        ),
        "truck": KnownObjectSize(
            objectType: .vehicle,
            label: "truck",
            sizeMeters: 2.0,            // Average pickup height
            measurementType: .height,
            sizeVariability: 0.2,
            reliabilityWeight: 0.8,
            expectedAspectRatio: 2.0
        ),
        "suv": KnownObjectSize(
            objectType: .vehicle,
            label: "suv",
            sizeMeters: 1.75,
            measurementType: .height,
            sizeVariability: 0.15,
            reliabilityWeight: 0.8,
            expectedAspectRatio: 1.8
        ),

        // Wildlife (hunting targets)
        "deer": KnownObjectSize(
            objectType: .wildlife,
            label: "deer",
            sizeMeters: 1.0,            // White-tail shoulder height
            measurementType: .height,
            sizeVariability: 0.15,
            reliabilityWeight: 0.85,
            expectedAspectRatio: 1.5
        ),
        "elk": KnownObjectSize(
            objectType: .wildlife,
            label: "elk",
            sizeMeters: 1.5,            // Elk shoulder height
            measurementType: .height,
            sizeVariability: 0.12,
            reliabilityWeight: 0.85,
            expectedAspectRatio: 1.4
        ),
        "wild_boar": KnownObjectSize(
            objectType: .wildlife,
            label: "wild_boar",
            sizeMeters: 0.75,
            measurementType: .height,
            sizeVariability: 0.2,
            reliabilityWeight: 0.75,
            expectedAspectRatio: 2.0
        ),
        "coyote": KnownObjectSize(
            objectType: .wildlife,
            label: "coyote",
            sizeMeters: 0.6,
            measurementType: .height,
            sizeVariability: 0.15,
            reliabilityWeight: 0.7,
            expectedAspectRatio: 1.8
        ),

        // Structures
        "door": KnownObjectSize(
            objectType: .structure,
            label: "door",
            sizeMeters: 2.03,           // Standard door height (80")
            measurementType: .height,
            sizeVariability: 0.05,
            reliabilityWeight: 0.95,
            expectedAspectRatio: 0.4
        ),
        "window": KnownObjectSize(
            objectType: .structure,
            label: "window",
            sizeMeters: 1.2,            // Average window height
            measurementType: .height,
            sizeVariability: 0.25,
            reliabilityWeight: 0.7,
            expectedAspectRatio: 0.8
        ),

        // Signs
        "stop_sign": KnownObjectSize(
            objectType: .sign,
            label: "stop_sign",
            sizeMeters: 0.75,           // Standard stop sign (30")
            measurementType: .width,
            sizeVariability: 0.02,      // Very standardized
            reliabilityWeight: 0.98,
            expectedAspectRatio: 1.0
        ),
        "speed_limit_sign": KnownObjectSize(
            objectType: .sign,
            label: "speed_limit_sign",
            sizeMeters: 0.61,           // Standard (24")
            measurementType: .width,
            sizeVariability: 0.05,
            reliabilityWeight: 0.95,
            expectedAspectRatio: 0.75
        )
    ]

    func getSize(for label: String) -> KnownObjectSize? {
        // Exact match
        if let size = sizeDatabase[label.lowercased()] {
            return size
        }

        // Fuzzy match
        for (key, size) in sizeDatabase {
            if label.lowercased().contains(key) || key.contains(label.lowercased()) {
                return size
            }
        }

        return nil
    }

    func getAllSizes(for type: ObjectType) -> [KnownObjectSize] {
        return sizeDatabase.values.filter { $0.objectType == type }
    }
}
```

### 5. UI Layer

```swift
// RangefinderView.swift

import SwiftUI

struct RangefinderView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var visionPipeline = VisionPipeline()
    @StateObject private var rangingEngine = RangingEngine()

    @State private var displayUnit: UnitLength = .yards
    @State private var showSettings = false
    @State private var selectedTarget: VisionPipeline.Detection?

    var body: some View {
        ZStack {
            // Camera Preview
            CameraPreviewView(cameraManager: cameraManager)
                .ignoresSafeArea()

            // Detection Overlays
            DetectionOverlayView(
                detections: visionPipeline.detections,
                selectedTarget: $selectedTarget
            )

            // Crosshair
            CrosshairView()

            // Range Display
            VStack {
                Spacer()

                RangeDisplayView(
                    estimate: rangingEngine.currentRange,
                    displayUnit: displayUnit
                )
                .padding(.bottom, 100)
            }

            // Top HUD
            VStack {
                HUDView(
                    confidence: rangingEngine.currentRange?.confidence ?? 0,
                    method: rangingEngine.currentRange?.method ?? .fused,
                    onSettingsTap: { showSettings = true }
                )
                Spacer()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(displayUnit: $displayUnit)
        }
        .task {
            await initialize()
        }
    }

    private func initialize() async {
        try? await cameraManager.configure()
        try? await visionPipeline.loadModels()
        cameraManager.startCapture()
    }
}

// MARK: - Crosshair View
struct CrosshairView: View {
    var body: some View {
        ZStack {
            // Horizontal line
            Rectangle()
                .fill(Color.green)
                .frame(width: 40, height: 2)

            // Vertical line
            Rectangle()
                .fill(Color.green)
                .frame(width: 2, height: 40)

            // Center dot
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)

            // Mil-dot marks
            ForEach([-20, -10, 10, 20], id: \.self) { offset in
                Rectangle()
                    .fill(Color.green.opacity(0.7))
                    .frame(width: 10, height: 2)
                    .offset(x: CGFloat(offset))

                Rectangle()
                    .fill(Color.green.opacity(0.7))
                    .frame(width: 2, height: 10)
                    .offset(y: CGFloat(offset))
            }
        }
    }
}

// MARK: - Range Display
struct RangeDisplayView: View {
    let estimate: RangingEngine.RangeEstimate?
    let displayUnit: UnitLength

    var body: some View {
        VStack(spacing: 8) {
            if let estimate = estimate, estimate.confidence > 0.3 {
                // Main distance
                Text(formattedDistance)
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                    .shadow(color: .black, radius: 2)

                // Unit label
                Text(unitLabel)
                    .font(.title2)
                    .foregroundColor(.green.opacity(0.8))

                // Uncertainty
                Text("± \(formattedUncertainty)")
                    .font(.caption)
                    .foregroundColor(.yellow)

                // Confidence bar
                ConfidenceBar(confidence: estimate.confidence)
                    .frame(width: 200, height: 8)
            } else {
                Text("---")
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)

                Text("NO TARGET")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
    }

    private var formattedDistance: String {
        guard let estimate = estimate else { return "---" }
        let value = estimate.distance.converted(to: displayUnit).value
        return String(format: "%.0f", value)
    }

    private var unitLabel: String {
        switch displayUnit {
        case .yards: return "YDS"
        case .meters: return "M"
        case .feet: return "FT"
        default: return "YDS"
        }
    }

    private var formattedUncertainty: String {
        guard let estimate = estimate else { return "---" }
        let value = estimate.uncertainty.converted(to: displayUnit).value
        return String(format: "%.0f %@", value, unitLabel)
    }
}

// MARK: - Confidence Bar
struct ConfidenceBar: View {
    let confidence: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))

                Rectangle()
                    .fill(confidenceColor)
                    .frame(width: geometry.size.width * CGFloat(confidence))
            }
            .cornerRadius(4)
        }
    }

    private var confidenceColor: Color {
        if confidence > 0.7 { return .green }
        if confidence > 0.5 { return .yellow }
        return .orange
    }
}
```

---

## Data Flow

```
┌──────────────┐
│ Camera Frame │
│  (4K @ 30fps)│
└──────┬───────┘
       │
       ▼
┌──────────────────────────────────────────────────────────┐
│                    Frame Processor                        │
│  1. Extract camera intrinsics                            │
│  2. Downsample for ML (1280x720)                         │
│  3. Dispatch to Vision Pipeline                          │
└──────────────────────────────────────────────────────────┘
       │
       ├─────────────────────┬─────────────────────┐
       ▼                     ▼                     ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   Object     │    │    Depth     │    │ Atmospheric  │
│  Detection   │    │  Estimation  │    │   Analysis   │
│  (YOLO11)    │    │  (DA V2)     │    │   (Haze)     │
└──────┬───────┘    └──────┬───────┘    └──────┬───────┘
       │                   │                   │
       └─────────────────────┬─────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────┐
│                    Ranging Engine                         │
│  1. Size-based calculation for each detection            │
│  2. Depth map sampling at target region                  │
│  3. Atmospheric depth estimation                         │
│  4. Kalman filter fusion                                 │
│  5. Uncertainty quantification                           │
└──────────────────────────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────┐
│                      UI Update                            │
│  - Distance display                                       │
│  - Confidence indicator                                   │
│  - Bounding box overlay                                   │
│  - Method indicator                                       │
└──────────────────────────────────────────────────────────┘
```

---

## Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| Frame rate | 30 FPS | Full pipeline |
| Detection latency | <50ms | Object detection |
| Depth latency | <100ms | Can run at lower rate |
| Total latency | <150ms | Camera to display |
| Memory usage | <500MB | During inference |
| Battery drain | <15%/hr | Active ranging |

---

## File Structure

```
SniperScope/
├── App/
│   ├── SniperScopeApp.swift
│   └── AppDelegate.swift
├── Camera/
│   ├── CameraManager.swift
│   ├── CameraPreviewView.swift
│   └── CameraIntrinsics.swift
├── Vision/
│   ├── VisionPipeline.swift
│   ├── ObjectDetector.swift
│   └── DepthEstimator.swift
├── Ranging/
│   ├── RangingEngine.swift
│   ├── SizeBasedRanger.swift
│   ├── DepthBasedRanger.swift
│   ├── AtmosphericRanger.swift
│   └── KalmanFilter.swift
├── Database/
│   ├── KnownObjectDatabase.swift
│   ├── HumanSizes.swift
│   ├── VehicleSizes.swift
│   └── WildlifeSizes.swift
├── UI/
│   ├── RangefinderView.swift
│   ├── CrosshairView.swift
│   ├── RangeDisplayView.swift
│   ├── DetectionOverlayView.swift
│   ├── HUDView.swift
│   └── SettingsView.swift
├── Utilities/
│   ├── Extensions.swift
│   ├── Constants.swift
│   └── Formatters.swift
├── Models/
│   ├── SniperScope_Detector.mlmodelc
│   └── DepthAnythingV2_Small.mlmodelc
└── Resources/
    ├── Assets.xcassets
    └── Info.plist
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-22 | Initial architecture design |
