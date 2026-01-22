//
//  VisionPipeline.swift
//  SniperScope
//
//  Orchestrates ML inference for object detection and depth estimation.
//
//  This file is the core of the computer vision system, responsible for:
//  - Loading and managing CoreML models
//  - Running object detection on camera frames
//  - Running monocular depth estimation
//  - Publishing detection results for the ranging engine
//
//  ML Models Used:
//  ---------------
//  1. SniperScope_Detector (YOLO-based)
//     - Detects people, vehicles, wildlife, and structures
//     - Outputs: class labels, confidence scores, bounding boxes
//     - Input: 640x640 or 1280x1280 RGB image
//
//  2. DepthAnythingV2_Small (optional)
//     - Estimates relative depth from a single image
//     - Outputs: depth map (inverse depth values)
//     - Used as secondary signal for sensor fusion
//
//  Processing Pipeline:
//  --------------------
//  Camera Frame → Object Detection ─┬→ VisionResult → RangingEngine
//                                   │
//                Depth Estimation ──┘
//
//  Copyright (c) 2025. For educational use only.
//

import Foundation
import Vision
import CoreML
import Combine
import CoreImage

// MARK: - Detection Result

/// Represents a single detected object in the camera frame.
///
/// Contains all information needed to calculate distance:
/// - The object's label (for looking up known size)
/// - The bounding box in both normalized and pixel coordinates
/// - Detection confidence for weighting in sensor fusion
///
/// ## Coordinate Systems
/// - `boundingBox`: Normalized (0-1), origin at bottom-left (Vision convention)
/// - `pixelBoundingBox`: Pixel coordinates, origin at top-left (UI convention)
struct Detection: Identifiable {

    /// Unique identifier for SwiftUI ForEach compatibility.
    let id = UUID()

    /// The detected object's class label (e.g., "person", "car", "deer").
    ///
    /// This label is used to look up the object's known real-world size
    /// in the `KnownObjectDatabase`.
    let label: String

    /// Detection confidence score (0.0 to 1.0).
    ///
    /// Higher values indicate more certainty about the detection.
    /// Detections below 0.3 are typically filtered out.
    let confidence: Float

    /// Bounding box in normalized coordinates (0-1 range).
    ///
    /// Origin is at bottom-left corner (Vision framework convention).
    /// Used for display overlays and Vision framework compatibility.
    let boundingBox: CGRect           // Normalized coordinates (0-1)

    /// Bounding box in pixel coordinates.
    ///
    /// Origin is at top-left corner (standard UI convention).
    /// Used for size-based ranging calculations.
    let pixelBoundingBox: CGRect      // Pixel coordinates

    /// When this detection was made.
    let timestamp: Date

    // MARK: - Computed Properties

    /// Center point of the bounding box in normalized coordinates.
    ///
    /// Useful for determining which detection is closest to the crosshair.
    var centerPoint: CGPoint {
        CGPoint(
            x: boundingBox.midX,
            y: boundingBox.midY
        )
    }

    /// Center point of the bounding box in pixel coordinates.
    var pixelCenterPoint: CGPoint {
        CGPoint(
            x: pixelBoundingBox.midX,
            y: pixelBoundingBox.midY
        )
    }

    /// Height of the bounding box in pixels.
    ///
    /// This is the primary measurement used in size-based ranging:
    /// `Distance = (RealHeight × FocalLength) / PixelHeight`
    var pixelHeight: CGFloat {
        pixelBoundingBox.height
    }

    /// Width of the bounding box in pixels.
    ///
    /// Used for objects where width is more reliable (e.g., vehicles from the side).
    var pixelWidth: CGFloat {
        pixelBoundingBox.width
    }
}

// MARK: - Vision Result

/// Complete result from one frame of vision processing.
///
/// Bundles together all outputs from the vision pipeline:
/// - All detected objects
/// - Optional depth map
/// - Camera intrinsics at capture time
/// - Image dimensions for coordinate conversion
///
/// The `RangingEngine` consumes these results to calculate distances.
struct VisionResult {

    /// All objects detected in this frame.
    let detections: [Detection]

    /// Depth map from monocular depth estimation (if available).
    ///
    /// Contains relative inverse depth values. Closer objects have higher values.
    /// `nil` if depth estimation is disabled or failed.
    let depthMap: CVPixelBuffer?

    /// Camera intrinsics at the time this frame was captured.
    ///
    /// Essential for accurate distance calculation via the pinhole camera model.
    let intrinsics: CameraIntrinsics

    /// Dimensions of the source image in pixels.
    ///
    /// Used for coordinate conversion between normalized and pixel spaces.
    let imageSize: CGSize

    /// Timestamp of frame capture.
    let timestamp: Date

    // MARK: - Primary Detection Selection

    /// Returns the most relevant detection for ranging.
    ///
    /// Selection criteria:
    /// 1. Prefers detections closer to the image center (crosshair)
    /// 2. Weights by confidence (higher confidence = more trustworthy)
    /// 3. Balances both factors with a scoring formula
    ///
    /// - Returns: The detection that should be used for ranging, or `nil` if no detections.
    var primaryDetection: Detection? {
        guard !detections.isEmpty else { return nil }

        let center = CGPoint(x: 0.5, y: 0.5)

        // Find detection with highest score (confidence / distance_to_center)
        return detections.max { a, b in
            // Calculate distance from each detection's center to image center
            let distA = hypot(a.centerPoint.x - center.x, a.centerPoint.y - center.y)
            let distB = hypot(b.centerPoint.x - center.x, b.centerPoint.y - center.y)

            // Score = confidence / (distance + epsilon)
            // Higher score = more confident AND closer to center
            // epsilon (0.1) prevents division issues when detection is at center
            let scoreA = a.confidence / Float(distA + 0.1)
            let scoreB = b.confidence / Float(distB + 0.1)

            return scoreA < scoreB
        }
    }
}

// MARK: - Vision Pipeline

/// Orchestrates ML inference for object detection and depth estimation.
///
/// The `VisionPipeline` is the central hub for all computer vision operations.
/// It loads ML models, processes camera frames, and publishes results for
/// downstream ranging calculations.
///
/// ## Architecture
/// ```
/// CameraManager.framePublisher
///        ↓
/// VisionPipeline.process()
///        ↓
/// ┌──────┴──────┐
/// │  Detection  │  (VNCoreMLRequest with YOLO model)
/// └──────┬──────┘
///        │
/// ┌──────┴──────┐
/// │    Depth    │  (VNCoreMLRequest with DepthAnything)
/// └──────┬──────┘
///        ↓
/// VisionPipeline.resultPublisher
///        ↓
/// RangingEngine
/// ```
///
/// ## Threading
/// - Frame processing occurs on `processingQueue` (user-initiated QoS)
/// - Published properties are updated on main thread
/// - Model loading is async to avoid blocking app startup
///
/// ## Usage
/// ```swift
/// let pipeline = VisionPipeline()
/// try await pipeline.loadModels()
///
/// cameraManager.framePublisher
///     .sink { pixelBuffer, intrinsics in
///         pipeline.process(pixelBuffer: pixelBuffer, intrinsics: intrinsics)
///     }
///
/// pipeline.resultPublisher
///     .sink { result in
///         // Process detections and depth
///     }
/// ```
class VisionPipeline: ObservableObject {

    // MARK: - Published Properties

    /// Current detections from the most recent frame.
    ///
    /// Updated on the main thread for UI binding.
    @Published var detections: [Detection] = []

    /// Whether inference is currently running.
    ///
    /// Can be used to show a processing indicator.
    @Published var isProcessing = false

    /// Whether all required models have been loaded successfully.
    ///
    /// The pipeline can still function with some models missing,
    /// but with reduced capabilities.
    @Published var modelsLoaded = false

    /// Current error state, if any.
    @Published var error: VisionError?

    // MARK: - Result Publisher

    /// Publishes complete vision results for each processed frame.
    ///
    /// Subscribe to this for downstream processing (e.g., in RangingEngine).
    let resultPublisher = PassthroughSubject<VisionResult, Never>()

    // MARK: - Private Properties

    /// CoreML model wrapped for Vision framework (object detection).
    private var objectDetector: VNCoreMLModel?

    /// CoreML model wrapped for Vision framework (depth estimation).
    private var depthEstimator: VNCoreMLModel?

    /// Dedicated queue for ML inference.
    ///
    /// Uses `.userInitiated` QoS for responsive processing.
    private let processingQueue = DispatchQueue(label: "com.sniperscope.vision", qos: .userInitiated)

    // MARK: - Throttling

    /// Timestamp of last processed frame.
    private var lastProcessTime: Date = .distantPast

    /// Minimum time between processing frames (50ms = 20 FPS max).
    ///
    /// Prevents overwhelming the ML pipeline with too many requests.
    private let minProcessInterval: TimeInterval = 0.05  // 20 FPS max

    /// Storage for Combine subscriptions.
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Error Types

    /// Errors that can occur during vision pipeline operation.
    enum VisionError: LocalizedError {

        /// The specified model file was not found in the app bundle.
        case modelNotFound(String)

        /// The model file exists but failed to load.
        case modelLoadFailed(String)

        /// An error occurred during model inference.
        case inferenceError(String)

        var errorDescription: String? {
            switch self {
            case .modelNotFound(let name):
                return "Model not found: \(name)"
            case .modelLoadFailed(let name):
                return "Failed to load model: \(name)"
            case .inferenceError(let message):
                return "Inference error: \(message)"
            }
        }
    }

    // MARK: - Initialization

    /// Creates a new vision pipeline.
    ///
    /// Models are not loaded automatically. Call `loadModels()` before processing.
    init() {}

    // MARK: - Model Loading

    /// Loads all required ML models asynchronously.
    ///
    /// This method attempts to load:
    /// 1. Object detection model (SniperScope_Detector)
    /// 2. Depth estimation model (DepthAnythingV2_Small)
    ///
    /// If a model is not found or fails to load, the pipeline continues
    /// with reduced functionality rather than failing completely.
    ///
    /// - Throws: Errors are logged but not propagated to allow partial operation.
    func loadModels() async throws {
        // Try to load object detection model
        do {
            try await loadObjectDetector()
        } catch {
            print("Warning: Object detector not loaded: \(error)")
            // Continue without detector - will return empty detections
        }

        // Try to load depth model
        do {
            try await loadDepthEstimator()
        } catch {
            print("Warning: Depth estimator not loaded: \(error)")
            // Continue without depth - will return nil depth maps
        }

        // Mark as loaded even with partial success
        await MainActor.run {
            self.modelsLoaded = true
        }
    }

    /// Loads the object detection model from the app bundle.
    ///
    /// Searches for either compiled (.mlmodelc) or package (.mlpackage) formats.
    /// Configures the model to use all available compute units (CPU, GPU, Neural Engine).
    ///
    /// - Throws: `VisionError.modelLoadFailed` if the model can't be loaded.
    private func loadObjectDetector() async throws {
        // Look for the model in the bundle (try compiled first, then package)
        guard let modelURL = Bundle.main.url(forResource: "SniperScope_Detector", withExtension: "mlmodelc") ??
                            Bundle.main.url(forResource: "SniperScope_Detector", withExtension: "mlpackage") else {
            // For development without a trained model, use placeholder detection
            print("Object detector model not found in bundle - will use placeholder detection")
            return
        }

        // Configure for optimal performance
        let config = MLModelConfiguration()
        config.computeUnits = .all  // Use Neural Engine when available

        do {
            // Load the CoreML model asynchronously
            let mlModel = try await MLModel.load(contentsOf: modelURL, configuration: config)
            // Wrap in Vision-compatible model
            objectDetector = try VNCoreMLModel(for: mlModel)
            print("Object detector loaded successfully")
        } catch {
            throw VisionError.modelLoadFailed("SniperScope_Detector: \(error.localizedDescription)")
        }
    }

    /// Loads the depth estimation model from the app bundle.
    ///
    /// Uses Depth Anything V2 Small, a monocular depth estimation model
    /// that provides relative depth values without requiring stereo cameras.
    ///
    /// - Throws: `VisionError.modelLoadFailed` if the model can't be loaded.
    private func loadDepthEstimator() async throws {
        // Look for Depth Anything V2 model
        guard let modelURL = Bundle.main.url(forResource: "DepthAnythingV2_Small", withExtension: "mlmodelc") ??
                            Bundle.main.url(forResource: "DepthAnythingV2_Small", withExtension: "mlpackage") else {
            print("Depth estimator model not found in bundle - will skip depth estimation")
            return
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all  // Neural Engine preferred for depth models

        do {
            let mlModel = try await MLModel.load(contentsOf: modelURL, configuration: config)
            depthEstimator = try VNCoreMLModel(for: mlModel)
            print("Depth estimator loaded successfully")
        } catch {
            throw VisionError.modelLoadFailed("DepthAnythingV2: \(error.localizedDescription)")
        }
    }

    // MARK: - Frame Processing

    /// Processes a camera frame through the vision pipeline.
    ///
    /// This is the main entry point for frame processing. It:
    /// 1. Throttles to prevent overwhelming the pipeline
    /// 2. Runs object detection and depth estimation in parallel
    /// 3. Combines results into a `VisionResult`
    /// 4. Publishes the result for downstream processing
    ///
    /// ## Threading
    /// This method returns immediately. Processing occurs on `processingQueue`.
    ///
    /// - Parameters:
    ///   - pixelBuffer: The camera frame to process.
    ///   - intrinsics: Camera intrinsics at capture time.
    func process(pixelBuffer: CVPixelBuffer, intrinsics: CameraIntrinsics) {
        // Throttle processing to max FPS limit
        let now = Date()
        guard now.timeIntervalSince(lastProcessTime) >= minProcessInterval else {
            return
        }
        lastProcessTime = now

        // Skip if already processing (prevents queue buildup)
        guard !isProcessing else { return }

        processingQueue.async { [weak self] in
            guard let self = self else { return }

            // Mark as processing
            DispatchQueue.main.async {
                self.isProcessing = true
            }

            // Get image dimensions for coordinate conversion
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let imageSize = CGSize(width: width, height: height)

            // Run detection and depth in parallel using DispatchGroup
            let group = DispatchGroup()

            var detectionResults: [Detection] = []
            var depthResult: CVPixelBuffer?

            // Object detection task
            group.enter()
            self.runObjectDetection(pixelBuffer, imageSize: imageSize) { detections in
                detectionResults = detections
                group.leave()
            }

            // Depth estimation task (only if model is loaded)
            if self.depthEstimator != nil {
                group.enter()
                self.runDepthEstimation(pixelBuffer) { depth in
                    depthResult = depth
                    group.leave()
                }
            }

            // Wait for both tasks to complete
            group.wait()

            // Create combined result
            let result = VisionResult(
                detections: detectionResults,
                depthMap: depthResult,
                intrinsics: intrinsics,
                imageSize: imageSize,
                timestamp: now
            )

            // Update published properties on main thread
            DispatchQueue.main.async {
                self.detections = detectionResults
                self.isProcessing = false
            }

            // Publish result for RangingEngine
            self.resultPublisher.send(result)
        }
    }

    // MARK: - Object Detection

    /// Runs object detection on a pixel buffer.
    ///
    /// Uses the Vision framework to run a CoreML YOLO model.
    /// Converts VNRecognizedObjectObservation results into Detection structs.
    ///
    /// - Parameters:
    ///   - pixelBuffer: The image to analyze.
    ///   - imageSize: Image dimensions for coordinate conversion.
    ///   - completion: Called with array of detections (may be empty).
    private func runObjectDetection(
        _ pixelBuffer: CVPixelBuffer,
        imageSize: CGSize,
        completion: @escaping ([Detection]) -> Void
    ) {
        // If no model loaded, return empty results
        guard let model = objectDetector else {
            // No model available - return empty
            completion([])
            return
        }

        // Create Vision request with our CoreML model
        let request = VNCoreMLRequest(model: model) { request, error in
            if let error = error {
                print("Detection error: \(error)")
                completion([])
                return
            }

            // Cast results to object observations
            guard let results = request.results as? [VNRecognizedObjectObservation] else {
                completion([])
                return
            }

            // Convert to our Detection type
            let detections = results.compactMap { observation -> Detection? in
                // Get the top label (highest confidence class)
                guard let topLabel = observation.labels.first,
                      topLabel.confidence > 0.3 else {  // Filter low-confidence detections
                    return nil
                }

                let normalizedBox = observation.boundingBox

                // Convert from Vision coordinates (origin bottom-left)
                // to pixel coordinates (origin top-left)
                let pixelBox = CGRect(
                    x: normalizedBox.origin.x * imageSize.width,
                    y: (1 - normalizedBox.origin.y - normalizedBox.height) * imageSize.height,
                    width: normalizedBox.width * imageSize.width,
                    height: normalizedBox.height * imageSize.height
                )

                return Detection(
                    label: topLabel.identifier,
                    confidence: topLabel.confidence,
                    boundingBox: normalizedBox,
                    pixelBoundingBox: pixelBox,
                    timestamp: Date()
                )
            }

            completion(detections)
        }

        // Configure request to scale input to model's expected size
        request.imageCropAndScaleOption = .scaleFill

        // Create image handler and perform request
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform detection: \(error)")
            completion([])
        }
    }

    // MARK: - Depth Estimation

    /// Runs monocular depth estimation on a pixel buffer.
    ///
    /// Uses Depth Anything V2 to estimate relative depth from a single image.
    /// The output is an inverse depth map where closer objects have higher values.
    ///
    /// - Parameters:
    ///   - pixelBuffer: The image to analyze.
    ///   - completion: Called with depth map or nil if estimation fails.
    private func runDepthEstimation(
        _ pixelBuffer: CVPixelBuffer,
        completion: @escaping (CVPixelBuffer?) -> Void
    ) {
        guard let model = depthEstimator else {
            completion(nil)
            return
        }

        let request = VNCoreMLRequest(model: model) { request, error in
            if let error = error {
                print("Depth estimation error: \(error)")
                completion(nil)
                return
            }

            // Handle different output types from depth models
            if let observation = request.results?.first as? VNPixelBufferObservation {
                // Direct pixel buffer output (preferred)
                completion(observation.pixelBuffer)
            } else if let observation = request.results?.first as? VNCoreMLFeatureValueObservation,
                      let multiArray = observation.featureValue.multiArrayValue {
                // MLMultiArray output - convert to pixel buffer
                completion(self.multiArrayToPixelBuffer(multiArray))
            } else {
                completion(nil)
            }
        }

        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform depth estimation: \(error)")
            completion(nil)
        }
    }

    // MARK: - Utility

    /// Converts an MLMultiArray depth output to a CVPixelBuffer.
    ///
    /// Some depth models output MLMultiArray instead of CVPixelBuffer.
    /// This converts the array to a float32 pixel buffer for uniform handling.
    ///
    /// - Parameter multiArray: The depth output array (shape: [H, W] or [1, H, W]).
    /// - Returns: A single-channel float32 pixel buffer, or nil if conversion fails.
    private func multiArrayToPixelBuffer(_ multiArray: MLMultiArray) -> CVPixelBuffer? {
        // Get array shape
        let shape = multiArray.shape.map { $0.intValue }
        guard shape.count >= 2 else { return nil }

        // Extract dimensions (last two are height and width)
        let height = shape[shape.count - 2]
        let width = shape[shape.count - 1]

        // Create output pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!
        ] as CFDictionary

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_OneComponent32Float,  // Single-channel float32
            attrs,
            &pixelBuffer
        )

        guard let buffer = pixelBuffer else { return nil }

        // Lock buffer for writing
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)

        // Copy data from MLMultiArray to pixel buffer
        let dataPtr = multiArray.dataPointer.assumingMemoryBound(to: Float.self)
        let count = width * height
        for i in 0..<count {
            floatBuffer[i] = dataPtr[i]
        }

        return buffer
    }

    // MARK: - Depth Sampling

    /// Samples depth values from a specific region of the depth map.
    ///
    /// Used by the RangingEngine to get depth values at detection locations.
    /// Returns the depth at the center of the specified region.
    ///
    /// - Parameters:
    ///   - depthMap: The depth map pixel buffer.
    ///   - region: Region to sample (in image coordinates).
    ///   - imageSize: Size of the original image (for coordinate scaling).
    /// - Returns: Depth value at the region center, or nil if unavailable.
    func sampleDepth(from depthMap: CVPixelBuffer?, at region: CGRect, imageSize: CGSize) -> Float? {
        guard let depthMap = depthMap else { return nil }

        // Lock buffer for reading
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let pixelFormat = CVPixelBufferGetPixelFormatType(depthMap)

        // Scale region from image coordinates to depth map coordinates
        let scaleX = CGFloat(depthWidth) / imageSize.width
        let scaleY = CGFloat(depthHeight) / imageSize.height

        let scaledRegion = CGRect(
            x: region.origin.x * scaleX,
            y: region.origin.y * scaleY,
            width: region.width * scaleX,
            height: region.height * scaleY
        )

        // Sample at center of region
        let centerX = Int(scaledRegion.midX)
        let centerY = Int(scaledRegion.midY)

        // Bounds check
        guard centerX >= 0 && centerX < depthWidth &&
              centerY >= 0 && centerY < depthHeight else {
            return nil
        }

        // Read depth value based on pixel format
        if pixelFormat == kCVPixelFormatType_OneComponent32Float {
            // 32-bit float format
            let rowPtr = baseAddress + centerY * bytesPerRow
            let pixel = rowPtr.assumingMemoryBound(to: Float.self)
            return pixel[centerX]
        } else if pixelFormat == kCVPixelFormatType_DepthFloat16 {
            // 16-bit float format (common for LiDAR depth)
            let rowPtr = baseAddress + centerY * bytesPerRow
            let pixel = rowPtr.assumingMemoryBound(to: UInt16.self)

            // Convert float16 to float32 using Accelerate
            var float16 = pixel[centerX]
            var float32: Float = 0
            withUnsafePointer(to: &float16) { srcPtr in
                withUnsafeMutablePointer(to: &float32) { dstPtr in
                    var src = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: srcPtr), height: 1, width: 1, rowBytes: 2)
                    var dst = vImage_Buffer(data: dstPtr, height: 1, width: 1, rowBytes: 4)
                    vImageConvert_Planar16FtoPlanarF(&src, &dst, 0)
                }
            }
            return float32
        }

        return nil
    }
}

// Import for float16 conversion
import Accelerate
