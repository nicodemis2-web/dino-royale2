//
//  RangingEngine.swift
//  SniperScope
//
//  Distance calculation engine with multiple methods and sensor fusion.
//
//  This file implements the core ranging algorithms that convert visual
//  measurements into distance estimates. It combines multiple independent
//  ranging methods to improve accuracy and confidence.
//
//  Ranging Methods Implemented:
//  ----------------------------
//  1. Size-Based Ranging (Primary)
//     Uses the pinhole camera model with known object sizes:
//     Distance = (Real_Size × Focal_Length) / Pixel_Size
//
//  2. Monocular Depth Estimation (Secondary)
//     Uses AI depth maps for relative distance estimation.
//     Requires calibration to convert to absolute distances.
//
//  Sensor Fusion:
//  --------------
//  Multiple distance estimates are combined using weighted averaging,
//  where weights are based on:
//  - Detection confidence
//  - Object size reliability
//  - Ranging method accuracy
//
//  Temporal Smoothing:
//  -------------------
//  A Kalman filter smooths the output over time, reducing jitter
//  while maintaining responsiveness to actual distance changes.
//
//  Copyright (c) 2025. For educational use only.
//

import Foundation
import Combine
import simd

// MARK: - Ranging Method

/// Enumeration of available distance calculation methods.
///
/// Each method has different strengths and accuracy characteristics.
/// The app may use multiple methods simultaneously and fuse the results.
enum RangingMethod: String, CaseIterable {

    /// Distance calculated from detected human dimensions.
    ///
    /// High accuracy for standing adults at moderate distances.
    /// Accuracy degrades with unusual poses, partial occlusion, or children.
    case sizeBasedHuman = "Size (Human)"

    /// Distance calculated from detected vehicle dimensions.
    ///
    /// Good accuracy for standard vehicles when viewed from the side.
    /// Vehicle type must be correctly identified for best results.
    case sizeBasedVehicle = "Size (Vehicle)"

    /// Distance calculated from detected wildlife dimensions.
    ///
    /// Moderate accuracy. Wildlife sizes vary significantly by species,
    /// age, and sex. Works best with clearly identifiable species.
    case sizeBasedWildlife = "Size (Wildlife)"

    /// Distance calculated from detected structure dimensions.
    ///
    /// Excellent accuracy for standardized structures like doors.
    /// Limited applicability - structures aren't always visible.
    case sizeBasedStructure = "Size (Structure)"

    /// Distance calculated from detected sign dimensions.
    ///
    /// Excellent accuracy for standardized road signs (MUTCD).
    /// Signs have consistent, mandated sizes.
    case sizeBasedSign = "Size (Sign)"

    /// Distance from AI monocular depth estimation.
    ///
    /// Provides relative depth that requires calibration.
    /// Lower weight in fusion due to lack of absolute scale.
    case monocularDepth = "Depth AI"

    /// Combined estimate from multiple methods.
    ///
    /// Displayed when multiple methods contributed to the result.
    case fused = "Fused"

    /// SF Symbol icon representing each method in the UI.
    var icon: String {
        switch self {
        case .sizeBasedHuman: return "person.fill"
        case .sizeBasedVehicle: return "car.fill"
        case .sizeBasedWildlife: return "hare.fill"
        case .sizeBasedStructure: return "building.2.fill"
        case .sizeBasedSign: return "signpost.right.fill"
        case .monocularDepth: return "brain"
        case .fused: return "waveform.path.ecg"
        }
    }

    /// Maps an object type to its corresponding ranging method.
    ///
    /// Used to determine which method produced a given detection.
    static func from(objectType: ObjectType) -> RangingMethod {
        switch objectType {
        case .human: return .sizeBasedHuman
        case .vehicle: return .sizeBasedVehicle
        case .wildlife: return .sizeBasedWildlife
        case .structure: return .sizeBasedStructure
        case .sign: return .sizeBasedSign
        }
    }
}

// MARK: - Range Component

/// A single distance estimate from one ranging method.
///
/// Before fusion, each detection or depth sample produces a separate
/// `RangeComponent`. These are then combined into a final `RangeEstimate`.
struct RangeComponent {

    /// The method used to calculate this distance.
    let method: RangingMethod

    /// Calculated distance in meters.
    let distance: Double           // meters

    /// Confidence in this measurement (0.0 to 1.0).
    ///
    /// Based on detection confidence, pixel size, and object variability.
    let confidence: Float          // 0-1

    /// Weight for sensor fusion (0.0 to 1.0).
    ///
    /// Combines confidence with method-specific reliability.
    let weight: Float              // For fusion

    /// Label of the detected object (nil for depth-based).
    let objectLabel: String?

    /// Human-readable description of how distance was calculated.
    let details: String

    /// Distance converted to yards for display.
    var distanceYards: Double {
        return distance / 0.9144  // 1 yard = 0.9144 meters
    }
}

// MARK: - Range Estimate

/// Final distance estimate after fusion and filtering.
///
/// This is the primary output of the ranging engine, containing:
/// - The fused distance measurement with units
/// - Confidence and uncertainty metrics
/// - The method(s) used
/// - Contributing components for debugging
struct RangeEstimate {

    /// The estimated distance with unit information.
    ///
    /// Using `Measurement` allows easy conversion between units.
    let distance: Measurement<UnitLength>

    /// Overall confidence in this estimate (0.0 to 1.0).
    ///
    /// Higher values indicate more reliable measurements.
    let confidence: Float

    /// Primary method used for this estimate.
    ///
    /// Will be `.fused` if multiple methods contributed significantly.
    let method: RangingMethod

    /// Uncertainty range (± this value).
    ///
    /// The true distance is expected to be within this range
    /// with approximately 68% probability (one standard deviation).
    let uncertainty: Measurement<UnitLength>

    /// All individual components that contributed to this estimate.
    ///
    /// Useful for debugging and understanding the measurement.
    let components: [RangeComponent]

    /// When this estimate was calculated.
    let timestamp: Date

    // MARK: - Computed Properties

    /// Distance in yards (common unit for US shooters).
    var distanceYards: Double {
        return distance.converted(to: .yards).value
    }

    /// Distance in meters (SI unit).
    var distanceMeters: Double {
        return distance.converted(to: .meters).value
    }

    /// Uncertainty in yards.
    var uncertaintyYards: Double {
        return uncertainty.converted(to: .yards).value
    }

    /// Uncertainty in meters.
    var uncertaintyMeters: Double {
        return uncertainty.converted(to: .meters).value
    }

    /// Uncertainty as a percentage of distance.
    ///
    /// Lower percentages indicate more precise measurements.
    /// Example: 5% at 400 yards = ±20 yards.
    var uncertaintyPercent: Double {
        guard distanceMeters > 0 else { return 0 }
        return (uncertaintyMeters / distanceMeters) * 100
    }

    // MARK: - Quality Assessment

    /// Categorical quality rating based on confidence and uncertainty.
    ///
    /// Used to color-code the display and set user expectations.
    var quality: RangeQuality {
        if confidence > 0.8 && uncertaintyPercent < 5 {
            return .excellent
        } else if confidence > 0.6 && uncertaintyPercent < 10 {
            return .good
        } else if confidence > 0.4 && uncertaintyPercent < 20 {
            return .fair
        } else {
            return .poor
        }
    }

    /// Quality levels for range estimates.
    enum RangeQuality: String {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"

        /// Color to use when displaying this quality level.
        var color: String {
            switch self {
            case .excellent: return "green"
            case .good: return "yellow"
            case .fair: return "orange"
            case .poor: return "red"
            }
        }
    }

    // MARK: - Static Instances

    /// Represents no valid range estimate.
    ///
    /// Used when no objects are detected or no valid calculation is possible.
    static let none = RangeEstimate(
        distance: Measurement(value: 0, unit: .meters),
        confidence: 0,
        method: .fused,
        uncertainty: Measurement(value: 0, unit: .meters),
        components: [],
        timestamp: Date()
    )
}

// MARK: - Kalman Filter

/// Simple 1D Kalman filter for temporal smoothing.
///
/// The Kalman filter provides optimal estimation by balancing:
/// - Process model: The system's expected behavior (distance changes slowly)
/// - Measurements: New observations (which may be noisy)
///
/// ## How It Works
/// 1. **Predict**: Estimate next state based on previous state
/// 2. **Update**: Incorporate new measurement, weighted by uncertainty
///
/// ## Tuning Parameters
/// - `processNoise`: How much distance can change between frames (higher = more responsive)
/// - `measurementNoise`: How noisy measurements are (higher = more smoothing)
///
/// ## Usage
/// ```swift
/// let filter = KalmanFilter()
/// let smoothed = filter.update(measurement: rawDistance)
/// ```
class KalmanFilter {

    /// Current state estimate (distance in meters).
    private var state: Double = 0           // Estimated distance

    /// Current uncertainty in the state estimate.
    private var covariance: Double = 100    // Uncertainty

    /// Expected variance in state between updates.
    ///
    /// Higher values make the filter more responsive to changes.
    private let processNoise: Double        // System noise

    /// Expected variance in measurements.
    ///
    /// Higher values cause more smoothing (less trust in measurements).
    private let measurementNoise: Double    // Measurement noise

    /// Creates a Kalman filter with specified noise parameters.
    ///
    /// - Parameters:
    ///   - processNoise: Expected state change variance (default: 0.5 meters²)
    ///   - measurementNoise: Expected measurement variance (default: 2.0 meters²)
    init(processNoise: Double = 0.5, measurementNoise: Double = 2.0) {
        self.processNoise = processNoise
        self.measurementNoise = measurementNoise
    }

    /// Incorporates a new measurement and returns the filtered estimate.
    ///
    /// This implements the standard Kalman filter predict-update cycle:
    /// 1. Predict step: Increase uncertainty by process noise
    /// 2. Update step: Blend prediction with measurement using Kalman gain
    ///
    /// - Parameters:
    ///   - measurement: The new distance measurement
    ///   - measurementUncertainty: Override default measurement noise (optional)
    /// - Returns: Smoothed distance estimate
    func update(measurement: Double, measurementUncertainty: Double? = nil) -> Double {
        let noise = measurementUncertainty ?? measurementNoise

        // Predict step: state stays the same, but uncertainty increases
        let predictedCovariance = covariance + processNoise

        // Update step: compute Kalman gain (how much to trust the measurement)
        // When gain = 1: fully trust measurement
        // When gain = 0: fully trust prediction
        let kalmanGain = predictedCovariance / (predictedCovariance + noise)

        // Update state estimate: blend prediction with measurement
        state = state + kalmanGain * (measurement - state)

        // Update uncertainty: it decreases because we got new information
        covariance = (1 - kalmanGain) * predictedCovariance

        return state
    }

    /// Resets the filter to initial state.
    ///
    /// Call this when the target changes or the scene changes significantly.
    func reset() {
        state = 0
        covariance = 100  // High initial uncertainty
    }

    /// The current filtered distance estimate.
    var currentEstimate: Double { state }

    /// The current uncertainty (standard deviation) of the estimate.
    var currentUncertainty: Double { sqrt(covariance) }
}

// MARK: - Ranging Engine

/// Calculates distances from vision results using multiple methods and sensor fusion.
///
/// The `RangingEngine` is the final stage of the passive rangefinding pipeline.
/// It takes detection results from the vision pipeline and calculates distances
/// using the pinhole camera model and optional depth estimation.
///
/// ## Algorithm Overview
/// 1. For each detection, calculate distance using known object sizes
/// 2. Optionally calculate distance from depth map at detection location
/// 3. Fuse all estimates using weighted averaging
/// 4. Apply temporal smoothing with Kalman filter
///
/// ## Pinhole Camera Model
/// The fundamental equation used for size-based ranging:
/// ```
/// Distance = (Real_Object_Size × Focal_Length) / Pixel_Size
/// ```
///
/// Where:
/// - Real_Object_Size: Known size from `KnownObjectDatabase` (meters)
/// - Focal_Length: From camera intrinsics (pixels)
/// - Pixel_Size: From detection bounding box (pixels)
///
/// ## Usage
/// ```swift
/// let engine = RangingEngine()
///
/// visionPipeline.resultPublisher
///     .sink { result in
///         let estimate = engine.calculateRange(from: result)
///         print("Distance: \(estimate.distanceYards) yards")
///     }
/// ```
class RangingEngine: ObservableObject {

    // MARK: - Published Properties

    /// The most recent range estimate.
    ///
    /// Observe this to update UI displays.
    @Published var currentRange: RangeEstimate = .none

    /// Whether range calculation is in progress.
    @Published var isRanging = false

    /// Whether a target is currently locked.
    ///
    /// True when confidence exceeds the lock threshold (0.5).
    @Published var targetLocked = false

    // MARK: - Configuration

    /// Scale factor for converting depth map values to meters.
    ///
    /// Monocular depth models output relative (inverse) depth.
    /// This factor is calibrated using a known distance reference:
    /// `depthScaleFactor = known_distance × measured_depth_value`
    var depthScaleFactor: Double = 1.0      // Calibrated depth scale

    /// Whether to include depth estimation in sensor fusion.
    ///
    /// Disable for faster processing or if depth model isn't available.
    var enableDepthFusion = true

    /// Whether to apply Kalman filter smoothing.
    ///
    /// Disable for raw, unfiltered measurements (more responsive but noisier).
    var enableTemporalSmoothing = true

    // MARK: - Private Properties

    /// Kalman filter instance for temporal smoothing.
    private let kalmanFilter = KalmanFilter()

    /// Recent range estimates for trend analysis.
    private var rangeHistory: [RangeEstimate] = []

    /// Maximum number of historical estimates to keep.
    private let maxHistorySize = 10

    /// Combine subscriptions storage.
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// Creates a new ranging engine with default settings.
    init() {}

    // MARK: - Main Calculation

    /// Calculates distance from a vision pipeline result.
    ///
    /// This is the primary method of the ranging engine. It:
    /// 1. Calculates size-based distance for each detection
    /// 2. Calculates depth-based distance if enabled
    /// 3. Fuses all estimates with weighted averaging
    /// 4. Applies temporal smoothing if enabled
    /// 5. Updates published properties for UI binding
    ///
    /// - Parameter visionResult: Detection and depth results from vision pipeline.
    /// - Returns: Fused and filtered range estimate.
    func calculateRange(from visionResult: VisionResult) -> RangeEstimate {
        var components: [RangeComponent] = []

        // Method 1: Size-based ranging for each detection
        // Each detected object with a known size contributes an estimate
        for detection in visionResult.detections {
            if let sizeComponent = calculateSizeBasedRange(
                detection: detection,
                intrinsics: visionResult.intrinsics
            ) {
                components.append(sizeComponent)
            }
        }

        // Method 2: Depth-based ranging (if available and enabled)
        // Uses AI depth estimation as a secondary signal
        if enableDepthFusion,
           let depthComponent = calculateDepthBasedRange(
            depthMap: visionResult.depthMap,
            targetDetection: visionResult.primaryDetection,
            imageSize: visionResult.imageSize
           ) {
            components.append(depthComponent)
        }

        // Fuse all estimates into a single range
        let estimate = fuseEstimates(components, timestamp: visionResult.timestamp)

        // Update published state on main thread
        DispatchQueue.main.async { [weak self] in
            self?.currentRange = estimate
            // Lock target when confidence exceeds threshold
            self?.targetLocked = estimate.confidence > 0.5
        }

        return estimate
    }

    // MARK: - Size-Based Ranging

    /// Calculates distance using the pinhole camera model with known object sizes.
    ///
    /// This implements the core size-based ranging algorithm:
    /// `Distance = (Real_Size × Focal_Length) / Pixel_Size`
    ///
    /// - Parameters:
    ///   - detection: Object detection with bounding box
    ///   - intrinsics: Camera intrinsics with focal length
    /// - Returns: Range component, or nil if object size unknown or invalid
    private func calculateSizeBasedRange(
        detection: Detection,
        intrinsics: CameraIntrinsics
    ) -> RangeComponent? {
        // Look up known size for this object type
        guard let knownSize = KnownObjectDatabase.shared.getSizeFuzzy(for: detection.label) else {
            return nil  // Unknown object type
        }

        // Determine which dimension to use based on measurement type
        let pixelSize: CGFloat
        let realSize: Double

        switch knownSize.measurementType {
        case .height, .shoulderHeight:
            // Use vertical dimension (most common for people, animals)
            pixelSize = detection.pixelHeight
            realSize = knownSize.sizeMeters
        case .width:
            // Use horizontal dimension (vehicles from side, signs)
            pixelSize = detection.pixelWidth
            realSize = knownSize.sizeMeters
        case .diagonal:
            // Use diagonal (rarely used)
            pixelSize = sqrt(pow(detection.pixelWidth, 2) + pow(detection.pixelHeight, 2))
            realSize = knownSize.sizeMeters
        }

        // Sanity check: minimum 5 pixels for any measurement
        // Smaller objects have too much quantization error
        guard pixelSize > 5 else {
            return nil
        }

        // === THE PINHOLE CAMERA MODEL ===
        // Distance = (Real_Object_Size × Focal_Length) / Pixel_Size
        //
        // Derivation from similar triangles:
        //   RealSize / Distance = PixelSize / FocalLength
        //   Therefore: Distance = RealSize × FocalLength / PixelSize
        let focalLength = Double(intrinsics.focalLengthY)
        let distance = (realSize * focalLength) / Double(pixelSize)

        // Sanity check: valid range is 1m to 2000m
        // Outside this range, either the detection or model is wrong
        guard distance > 1 && distance < 2000 else {
            return nil
        }

        // Calculate confidence based on multiple factors
        let confidence = calculateSizeConfidence(
            detection: detection,
            knownSize: knownSize,
            pixelSize: pixelSize,
            distance: distance
        )

        // Weight for fusion: confidence × object reliability
        let weight = confidence * knownSize.reliabilityWeight

        let method = RangingMethod.from(objectType: knownSize.objectType)

        return RangeComponent(
            method: method,
            distance: distance,
            confidence: confidence,
            weight: weight,
            objectLabel: knownSize.displayName,
            details: String(format: "%.1fm object at %.0fpx", realSize, pixelSize)
        )
    }

    /// Calculates confidence for a size-based range estimate.
    ///
    /// Confidence is reduced by:
    /// - Small pixel sizes (high quantization error)
    /// - High object size variability
    /// - Unusual aspect ratios (likely occlusion)
    /// - Long distances (error accumulates)
    ///
    /// - Parameters:
    ///   - detection: The object detection
    ///   - knownSize: Known size information from database
    ///   - pixelSize: Measured pixel size
    ///   - distance: Calculated distance
    /// - Returns: Confidence score (0.0 to 1.0)
    private func calculateSizeConfidence(
        detection: Detection,
        knownSize: KnownObjectSize,
        pixelSize: CGFloat,
        distance: Double
    ) -> Float {
        // Start with detection confidence
        var confidence = detection.confidence

        // Reduce confidence for small pixel sizes (high relative error)
        // <50px: linear reduction to 0
        // 50-100px: gradual increase to full confidence
        if pixelSize < 50 {
            confidence *= Float(pixelSize / 50)
        } else if pixelSize < 100 {
            confidence *= Float(0.8 + (pixelSize - 50) / 250)  // Scale 0.8-1.0
        }

        // Reduce confidence based on object size variability
        // E.g., children vs adults, compact cars vs trucks
        confidence *= (1.0 - knownSize.sizeVariability * 0.5)

        // Check aspect ratio for occlusion detection
        // Unusual aspect ratios suggest partial visibility
        let actualAspect = Float(detection.pixelWidth / detection.pixelHeight)
        let expectedAspect = knownSize.expectedAspectRatio
        let aspectDiff = abs(actualAspect - expectedAspect) / max(expectedAspect, 0.1)

        if aspectDiff > 0.5 {
            confidence *= 0.6  // Likely occluded or unusual pose
        } else if aspectDiff > 0.3 {
            confidence *= 0.8  // Minor deviation
        }

        // Distance-based confidence reduction
        // Accuracy degrades at longer distances due to:
        // - Smaller pixel counts
        // - Atmospheric effects
        // - Detection accuracy drops
        if distance > 500 {
            confidence *= Float(500 / distance)
        }

        // Clamp to valid range
        return min(max(confidence, 0), 1.0)
    }

    // MARK: - Depth-Based Ranging

    /// Calculates distance using monocular depth estimation.
    ///
    /// AI depth models provide relative (inverse) depth values.
    /// To get absolute distance: `distance = scale_factor / depth_value`
    ///
    /// This method has lower weight in fusion because:
    /// - Requires calibration for absolute distance
    /// - Less accurate for distant objects
    /// - Can be confused by reflective surfaces
    ///
    /// - Parameters:
    ///   - depthMap: Depth map from vision pipeline
    ///   - targetDetection: Primary detection for sampling location
    ///   - imageSize: Image dimensions for coordinate scaling
    /// - Returns: Range component, or nil if depth unavailable
    private func calculateDepthBasedRange(
        depthMap: CVPixelBuffer?,
        targetDetection: Detection?,
        imageSize: CGSize
    ) -> RangeComponent? {
        guard let depthMap = depthMap else { return nil }

        // Determine where to sample in the depth map
        let sampleRegion: CGRect
        if let detection = targetDetection {
            // Sample at the center of the detected object
            let centerSize: CGFloat = 50  // Sample 50x50 pixel region
            sampleRegion = CGRect(
                x: detection.pixelCenterPoint.x - centerSize/2,
                y: detection.pixelCenterPoint.y - centerSize/2,
                width: centerSize,
                height: centerSize
            )
        } else {
            // No detection: sample at image center (crosshair location)
            let centerSize: CGFloat = 100
            sampleRegion = CGRect(
                x: imageSize.width/2 - centerSize/2,
                y: imageSize.height/2 - centerSize/2,
                width: centerSize,
                height: centerSize
            )
        }

        // Sample depth values from the region
        guard let depthValues = sampleDepthRegion(depthMap: depthMap, region: sampleRegion, imageSize: imageSize),
              !depthValues.isEmpty else {
            return nil
        }

        // Use median for robustness against outliers
        // (edges, holes, or artifacts in the depth map)
        let sortedDepths = depthValues.sorted()
        let medianDepth = sortedDepths[sortedDepths.count / 2]

        // Convert inverse depth to distance
        // Depth Anything outputs inverse depth: larger values = closer objects
        // actual_distance = scale_factor / inverse_depth
        let distance = depthScaleFactor / Double(medianDepth)

        // Sanity check
        guard distance > 0.5 && distance < 2000 else {
            return nil
        }

        // Depth-based ranging has inherently lower confidence
        // because it requires calibration and is less precise
        let confidence: Float = 0.5

        return RangeComponent(
            method: .monocularDepth,
            distance: distance,
            confidence: confidence,
            weight: 0.3,  // Lower weight for fusion (size-based is preferred)
            objectLabel: nil,
            details: "AI depth estimation"
        )
    }

    /// Samples multiple depth values from a region of the depth map.
    ///
    /// Samples every 4th pixel for efficiency while still getting
    /// a representative distribution of depth values.
    ///
    /// - Parameters:
    ///   - depthMap: The depth map pixel buffer
    ///   - region: Region to sample (in image coordinates)
    ///   - imageSize: Size of the original image
    /// - Returns: Array of depth values, or nil if sampling failed
    private func sampleDepthRegion(
        depthMap: CVPixelBuffer,
        region: CGRect,
        imageSize: CGSize
    ) -> [Float]? {
        // Lock buffer for reading
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        // Scale region from image coordinates to depth map coordinates
        // (depth map may be different resolution than camera image)
        let scaleX = CGFloat(depthWidth) / imageSize.width
        let scaleY = CGFloat(depthHeight) / imageSize.height

        let scaledRegion = CGRect(
            x: max(0, region.origin.x * scaleX),
            y: max(0, region.origin.y * scaleY),
            width: min(CGFloat(depthWidth), region.width * scaleX),
            height: min(CGFloat(depthHeight), region.height * scaleY)
        )

        var values: [Float] = []

        let startX = Int(scaledRegion.minX)
        let endX = min(Int(scaledRegion.maxX), depthWidth - 1)
        let startY = Int(scaledRegion.minY)
        let endY = min(Int(scaledRegion.maxY), depthHeight - 1)

        // Sample every 4th pixel for efficiency
        for y in stride(from: startY, to: endY, by: 4) {
            let rowPtr = baseAddress + y * bytesPerRow
            let floatRow = rowPtr.assumingMemoryBound(to: Float.self)

            for x in stride(from: startX, to: endX, by: 4) {
                let value = floatRow[x]
                // Only include valid, finite values
                if value > 0 && value.isFinite {
                    values.append(value)
                }
            }
        }

        return values.isEmpty ? nil : values
    }

    // MARK: - Estimate Fusion

    /// Combines multiple range components into a single estimate.
    ///
    /// Fusion algorithm:
    /// 1. If only one component: use it directly
    /// 2. If multiple: weighted average based on confidence and reliability
    /// 3. Calculate combined uncertainty from variance
    /// 4. Apply temporal smoothing if enabled
    ///
    /// - Parameters:
    ///   - components: Individual range estimates to fuse
    ///   - timestamp: Timestamp for the result
    /// - Returns: Fused range estimate
    private func fuseEstimates(_ components: [RangeComponent], timestamp: Date) -> RangeEstimate {
        // No components = no valid estimate
        guard !components.isEmpty else {
            return .none
        }

        // Single component: use directly
        if components.count == 1 {
            let comp = components[0]
            var finalDistance = comp.distance

            // Apply temporal smoothing
            if enableTemporalSmoothing {
                finalDistance = kalmanFilter.update(measurement: comp.distance)
            }

            // Uncertainty is proportional to (1 - confidence) × distance
            let uncertainty = comp.distance * Double(1 - comp.confidence) * 0.2

            return RangeEstimate(
                distance: Measurement(value: finalDistance, unit: .meters),
                confidence: comp.confidence,
                method: comp.method,
                uncertainty: Measurement(value: uncertainty, unit: .meters),
                components: components,
                timestamp: timestamp
            )
        }

        // Multiple components: weighted average fusion
        let totalWeight = components.reduce(Float(0)) { $0 + $1.weight }

        guard totalWeight > 0 else {
            return .none
        }

        // Weighted average distance
        let weightedDistance = components.reduce(0.0) { sum, comp in
            sum + comp.distance * Double(comp.weight)
        } / Double(totalWeight)

        // Calculate weighted variance for uncertainty estimation
        // Variance = Σ(weight × (value - mean)²) / Σweight
        let variance = components.reduce(0.0) { sum, comp in
            let diff = comp.distance - weightedDistance
            return sum + diff * diff * Double(comp.weight)
        } / Double(totalWeight)

        let uncertainty = sqrt(variance)

        // Apply temporal smoothing
        var finalDistance = weightedDistance
        if enableTemporalSmoothing {
            finalDistance = kalmanFilter.update(
                measurement: weightedDistance,
                measurementUncertainty: uncertainty
            )
        }

        // Combined confidence: average of max and weighted average
        // This balances "best case" with "typical case"
        let maxConfidence = components.max(by: { $0.confidence < $1.confidence })?.confidence ?? 0
        let avgConfidence = components.reduce(Float(0)) { $0 + $1.confidence * $1.weight } / totalWeight
        let confidence = (maxConfidence + avgConfidence) / 2

        // Determine primary method (or "fused" if multiple contributed)
        let primaryMethod: RangingMethod
        if let bestComponent = components.max(by: { $0.weight < $1.weight }) {
            primaryMethod = components.count > 1 ? .fused : bestComponent.method
        } else {
            primaryMethod = .fused
        }

        let estimate = RangeEstimate(
            distance: Measurement(value: finalDistance, unit: .meters),
            confidence: confidence,
            method: primaryMethod,
            // Minimum 3% uncertainty even with perfect conditions
            uncertainty: Measurement(value: max(uncertainty, finalDistance * 0.03), unit: .meters),
            components: components,
            timestamp: timestamp
        )

        // Update history for trend analysis
        rangeHistory.append(estimate)
        if rangeHistory.count > maxHistorySize {
            rangeHistory.removeFirst()
        }

        return estimate
    }

    // MARK: - Calibration

    /// Calibrates the depth scale factor using a known distance.
    ///
    /// To calibrate:
    /// 1. Place a target at a known distance (measured with laser rangefinder)
    /// 2. Capture the depth map and get the depth value at the target
    /// 3. Call this method with both values
    ///
    /// The scale factor is: `known_distance × measured_depth`
    /// (because depth = scale / distance, so scale = depth × distance)
    ///
    /// - Parameters:
    ///   - knownDistance: Actual distance to target (meters)
    ///   - measuredDepth: Depth value at target location
    func calibrateDepthScale(knownDistance: Double, measuredDepth: Double) {
        guard measuredDepth > 0 else { return }
        depthScaleFactor = knownDistance * measuredDepth
        print("Depth scale calibrated: \(depthScaleFactor)")
    }

    // MARK: - Reset

    /// Resets the ranging engine state.
    ///
    /// Call this when:
    /// - The target changes significantly
    /// - The scene changes (e.g., user moves to new location)
    /// - Calibration is performed
    func reset() {
        kalmanFilter.reset()
        rangeHistory.removeAll()
        currentRange = .none
        targetLocked = false
    }
}

// MARK: - Distance Formatter

/// Extension providing formatted string output for range estimates.
extension RangeEstimate {

    /// Formats the distance for display.
    ///
    /// - Parameters:
    ///   - unit: Unit for display (default: yards)
    ///   - precision: Decimal places (default: 0)
    /// - Returns: Formatted distance string
    func formattedDistance(unit: UnitLength = .yards, precision: Int = 0) -> String {
        let value = distance.converted(to: unit).value
        return String(format: "%.\(precision)f", value)
    }

    /// Formats the uncertainty for display.
    ///
    /// - Parameters:
    ///   - unit: Unit for display (default: yards)
    ///   - precision: Decimal places (default: 0)
    /// - Returns: Formatted uncertainty string with ± prefix
    func formattedUncertainty(unit: UnitLength = .yards, precision: Int = 0) -> String {
        let value = uncertainty.converted(to: unit).value
        return String(format: "±%.\(precision)f", value)
    }
}
