//
//  CameraManager.swift
//  SniperScope
//
//  Handles camera capture, configuration, and intrinsics extraction for
//  passive rangefinding applications.
//
//  This file is responsible for:
//  - Managing the AVFoundation capture session
//  - Extracting camera intrinsic parameters from frame metadata
//  - Providing a real-time frame publisher for downstream processing
//  - Handling camera controls (zoom, focus, permissions)
//
//  Camera Intrinsics Overview:
//  ---------------------------
//  The camera intrinsic matrix K encodes the internal camera parameters:
//
//      K = | fx  0   cx |
//          | 0   fy  cy |
//          | 0   0   1  |
//
//  Where:
//  - fx, fy: Focal length in pixels (horizontal and vertical)
//  - cx, cy: Principal point (optical center, usually near image center)
//
//  These parameters are essential for the pinhole camera model used in
//  passive rangefinding: Distance = (Object_Size × Focal_Length) / Pixel_Size
//
//  Modern iPhones provide intrinsics via CMSampleBuffer attachments when
//  the connection has `isCameraIntrinsicMatrixDeliveryEnabled = true`.
//
//  Copyright (c) 2025. For educational use only.
//

import AVFoundation
import CoreImage
import Combine
import simd

// MARK: - Camera Intrinsics

/// Encapsulates the camera's intrinsic parameters needed for geometric calculations.
///
/// The intrinsics describe how 3D world coordinates map to 2D pixel coordinates,
/// which is fundamental to passive rangefinding. These values are typically
/// obtained from the camera's metadata or estimated from device specifications.
///
/// ## Key Properties
/// - `focalLengthX/Y`: Focal length in pixels - determines how pixel size relates to angle
/// - `principalPointX/Y`: Image center offset - where the optical axis intersects the sensor
/// - `referenceWidth/Height`: Image dimensions these intrinsics were calculated for
///
/// ## Usage in Rangefinding
/// ```swift
/// // Calculate distance using pinhole model
/// let distance = (objectSizeMeters * focalLengthY) / pixelHeight
/// ```
struct CameraIntrinsics: Equatable {

    /// Horizontal focal length in pixels (fx from intrinsic matrix).
    ///
    /// Represents how many pixels correspond to a unit angle in the horizontal direction.
    /// Higher values indicate a more "zoomed in" field of view.
    let focalLengthX: Float      // fx in pixels

    /// Vertical focal length in pixels (fy from intrinsic matrix).
    ///
    /// For most cameras, this is very close to focalLengthX. Any difference
    /// indicates non-square pixels (rare in modern sensors).
    let focalLengthY: Float      // fy in pixels

    /// Horizontal principal point offset (cx from intrinsic matrix).
    ///
    /// The x-coordinate where the optical axis intersects the image plane.
    /// Ideally half the image width, but manufacturing tolerances cause slight offsets.
    let principalPointX: Float   // cx

    /// Vertical principal point offset (cy from intrinsic matrix).
    ///
    /// The y-coordinate where the optical axis intersects the image plane.
    /// Ideally half the image height.
    let principalPointY: Float   // cy

    /// Image width these intrinsics were calculated for.
    ///
    /// Intrinsics must be scaled if used with different resolution images.
    let referenceWidth: Int

    /// Image height these intrinsics were calculated for.
    let referenceHeight: Int

    // MARK: - Sensor Constants

    /// Approximate sensor pixel pitch in millimeters for iPhone cameras.
    ///
    /// This value (1.22 microns = 0.00122mm) is typical for iPhone 12+ sensors.
    /// Used to convert between pixel-based and physical focal lengths.
    ///
    /// Note: This is an approximation. Actual values vary by device model.
    static let sensorPixelPitch: Float = 0.00122  // 1.22 microns

    // MARK: - Computed Properties

    /// Approximate physical focal length in millimeters.
    ///
    /// Calculated by multiplying pixel focal length by sensor pixel pitch.
    /// For a typical iPhone wide camera, this is approximately 4-5mm.
    ///
    /// - Note: This is an estimate; actual value depends on sensor specifications.
    var focalLengthMM: Float {
        return focalLengthX * CameraIntrinsics.sensorPixelPitch
    }

    /// Aspect ratio of the reference image (width / height).
    ///
    /// Common values:
    /// - 16:9 = 1.778 (video)
    /// - 4:3 = 1.333 (photo)
    var aspectRatio: Float {
        return Float(referenceWidth) / Float(referenceHeight)
    }

    // MARK: - Default Values

    /// Default intrinsics for iPhone 12+ wide camera at 4K resolution.
    ///
    /// These fallback values are used when the device doesn't provide
    /// intrinsics via metadata. They're approximate and may reduce accuracy.
    ///
    /// Values based on typical iPhone 12 Pro wide camera specifications:
    /// - Focal length: ~26mm equivalent (full frame)
    /// - Sensor: 12MP, 1.4μm pixels
    /// - Resolution: 3840×2160 (4K video)
    static let defaultiPhone12Wide = CameraIntrinsics(
        focalLengthX: 2900,      // Approximate fx for 4K video
        focalLengthY: 2900,      // fy typically equals fx
        principalPointX: 1920,   // Half of 3840 (horizontal center)
        principalPointY: 1080,   // Half of 2160 (vertical center)
        referenceWidth: 3840,    // 4K width
        referenceHeight: 2160    // 4K height
    )

    // MARK: - Equatable

    /// Two intrinsics are equal if their focal lengths match.
    ///
    /// Principal point and dimensions are not compared since focal length
    /// is the primary determinant for rangefinding accuracy.
    static func == (lhs: CameraIntrinsics, rhs: CameraIntrinsics) -> Bool {
        return lhs.focalLengthX == rhs.focalLengthX &&
               lhs.focalLengthY == rhs.focalLengthY
    }
}

// MARK: - Camera Error

/// Errors that can occur during camera setup and operation.
///
/// These errors represent failure conditions that prevent the camera
/// from functioning correctly. Most require user action to resolve.
enum CameraError: LocalizedError {

    /// No suitable camera device was found on this device.
    ///
    /// This typically occurs on simulators or iPod Touch devices
    /// that lack a rear camera.
    case deviceNotFound

    /// Failed to create an AVCaptureDeviceInput from the camera device.
    ///
    /// May occur if the device is already in use by another app
    /// or if there's a hardware issue.
    case inputCreationFailed

    /// Failed to configure the capture session with required inputs/outputs.
    ///
    /// Check that the session preset is supported and that
    /// inputs/outputs are compatible.
    case sessionConfigurationFailed

    /// User denied camera permission or it's restricted by MDM/parental controls.
    ///
    /// The user must grant permission in Settings > Privacy > Camera.
    case permissionDenied

    /// Camera intrinsics could not be obtained from frame metadata.
    ///
    /// The app will fall back to default intrinsics, which may reduce accuracy.
    case intrinsicsNotAvailable

    /// Human-readable error descriptions for display in UI.
    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "Camera device not found"
        case .inputCreationFailed:
            return "Failed to create camera input"
        case .sessionConfigurationFailed:
            return "Failed to configure capture session"
        case .permissionDenied:
            return "Camera permission denied"
        case .intrinsicsNotAvailable:
            return "Camera intrinsics not available"
        }
    }
}

// MARK: - Camera Manager

/// Manages the device camera for real-time frame capture and intrinsics extraction.
///
/// `CameraManager` is the bridge between the hardware camera and the vision/ranging
/// pipeline. It handles all AVFoundation complexity and provides a clean Combine-based
/// interface for consuming camera frames.
///
/// ## Responsibilities
/// - Camera permission handling
/// - Capture session configuration (resolution, format, stabilization)
/// - Frame delivery via `framePublisher`
/// - Intrinsics extraction from frame metadata
/// - Camera controls (zoom, focus)
///
/// ## Usage
/// ```swift
/// let cameraManager = CameraManager()
///
/// // Configure and start
/// try await cameraManager.configure()
/// cameraManager.startCapture()
///
/// // Subscribe to frames
/// cameraManager.framePublisher
///     .sink { (pixelBuffer, intrinsics) in
///         // Process frame
///     }
///     .store(in: &cancellables)
/// ```
///
/// ## Threading
/// - Frame processing occurs on a dedicated high-priority queue
/// - Published properties are updated on the main thread
/// - Configuration must be performed before starting capture
class CameraManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    /// Whether the capture session is currently running.
    ///
    /// Observe this to show/hide camera UI appropriately.
    @Published var isRunning = false

    /// The most recent frame from the camera.
    ///
    /// Updated periodically (not every frame) to avoid overwhelming SwiftUI.
    /// For real-time processing, use `framePublisher` instead.
    @Published var currentFrame: CVPixelBuffer?

    /// Current camera intrinsics extracted from frame metadata.
    ///
    /// May be `nil` if intrinsics haven't been extracted yet or
    /// if the device doesn't support intrinsics delivery.
    @Published var cameraIntrinsics: CameraIntrinsics?

    /// Current error state, if any.
    ///
    /// `nil` when operating normally. Set when an error prevents
    /// proper camera operation.
    @Published var error: CameraError?

    /// Current optical/digital zoom factor.
    ///
    /// Range: 1.0 (no zoom) to device maximum (typically 10-15x).
    /// Higher zoom reduces field of view but can improve detection of distant objects.
    @Published var zoomFactor: CGFloat = 1.0

    // MARK: - Frame Publisher

    /// Publishes every processed camera frame with its intrinsics.
    ///
    /// Subscribers receive `(CVPixelBuffer, CameraIntrinsics)` tuples
    /// at approximately 15-30 FPS (depending on `processEveryNthFrame`).
    ///
    /// The pixel buffer is in BGRA format and should be processed quickly
    /// or copied if needed beyond the callback scope.
    let framePublisher = PassthroughSubject<(CVPixelBuffer, CameraIntrinsics), Never>()

    // MARK: - Private Properties

    /// The AVFoundation capture session managing camera hardware.
    private let captureSession = AVCaptureSession()

    /// Output for receiving video frames as sample buffers.
    private let videoOutput = AVCaptureVideoDataOutput()

    /// Dedicated queue for camera frame processing.
    ///
    /// Uses `.userInteractive` QoS for low-latency frame delivery.
    private let processingQueue = DispatchQueue(label: "com.sniperscope.camera", qos: .userInteractive)

    /// Reference to the active camera device for zoom/focus control.
    private var videoDevice: AVCaptureDevice?

    // MARK: - Frame Throttling

    /// Counter for implementing frame skipping.
    private var frameCount = 0

    /// Process every Nth frame to reduce CPU load.
    ///
    /// Value of 2 means ~30 FPS input becomes ~15 FPS processing.
    /// Adjust based on performance requirements.
    private let processEveryNthFrame = 2

    // MARK: - Initialization

    /// Creates a new camera manager.
    ///
    /// The manager is created in an unconfigured state. Call `configure()`
    /// before attempting to start capture.
    override init() {
        super.init()
    }

    // MARK: - Permission Check

    /// Checks and requests camera permission if needed.
    ///
    /// This method handles all permission states:
    /// - `.authorized`: Returns `true` immediately
    /// - `.notDetermined`: Prompts user, returns result
    /// - `.denied`/`.restricted`: Returns `false`
    ///
    /// - Returns: `true` if camera access is granted, `false` otherwise.
    func checkPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            // Prompt user for permission (suspends until user responds)
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Configuration

    /// Configures the capture session for high-resolution video capture.
    ///
    /// This method must be called before `startCapture()`. It:
    /// 1. Verifies camera permission
    /// 2. Selects the rear wide-angle camera
    /// 3. Configures for 4K or 1080p resolution
    /// 4. Sets up continuous autofocus and exposure
    /// 5. Enables camera intrinsics delivery
    /// 6. Disables video stabilization (preserves geometry for ranging)
    ///
    /// - Throws: `CameraError` if configuration fails.
    func configure() async throws {
        // Check permission first
        guard await checkPermission() else {
            await MainActor.run {
                self.error = .permissionDenied
            }
            throw CameraError.permissionDenied
        }

        // Configure on processing queue to avoid blocking main thread
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            processingQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: CameraError.sessionConfigurationFailed)
                    return
                }

                do {
                    try self.configureSession()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Internal session configuration (runs on processing queue).
    ///
    /// - Throws: `CameraError` for various configuration failures.
    private func configureSession() throws {
        // Begin atomic configuration block
        captureSession.beginConfiguration()

        // Set session preset for highest supported resolution
        // 4K provides more pixels for accurate size measurement
        if captureSession.canSetSessionPreset(.hd4K3840x2160) {
            captureSession.sessionPreset = .hd4K3840x2160
        } else if captureSession.canSetSessionPreset(.hd1920x1080) {
            captureSession.sessionPreset = .hd1920x1080
        }

        // Get the rear wide-angle camera (best for ranging)
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            captureSession.commitConfiguration()
            throw CameraError.deviceNotFound
        }

        videoDevice = device

        // Configure device-level settings
        do {
            try device.lockForConfiguration()

            // Enable continuous autofocus for tracking moving targets
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }

            // Enable continuous auto-exposure for changing lighting
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }

            // Note: Video stabilization is disabled on the connection (below)
            // to preserve geometric accuracy for ranging calculations

            device.unlockForConfiguration()
        } catch {
            print("Warning: Could not configure device: \(error)")
            // Continue anyway - these are optimizations, not requirements
        }

        // Create input from device
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            captureSession.commitConfiguration()
            throw CameraError.inputCreationFailed
        }

        // Add input to session
        guard captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            throw CameraError.sessionConfigurationFailed
        }
        captureSession.addInput(input)

        // Configure video output
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true  // Prioritize freshness over completeness
        videoOutput.videoSettings = [
            // BGRA format is efficient for both display and ML processing
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        // Add output to session
        guard captureSession.canAddOutput(videoOutput) else {
            captureSession.commitConfiguration()
            throw CameraError.sessionConfigurationFailed
        }
        captureSession.addOutput(videoOutput)

        // Configure the connection between input and output
        if let connection = videoOutput.connection(with: .video) {

            // CRITICAL: Enable camera intrinsics delivery
            // This provides the accurate focal length needed for ranging
            if connection.isCameraIntrinsicMatrixDeliverySupported {
                connection.isCameraIntrinsicMatrixDeliveryEnabled = true
            }

            // Set video orientation to portrait (most common use case)
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }

            // CRITICAL: Disable video stabilization
            // Stabilization crops and transforms the image, which would
            // invalidate the intrinsics and corrupt ranging calculations
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .off
            }
        }

        // Commit all configuration changes atomically
        captureSession.commitConfiguration()
    }

    // MARK: - Session Control

    /// Starts the camera capture session.
    ///
    /// Call this after `configure()` has completed successfully.
    /// Frames will begin arriving via `framePublisher`.
    func startCapture() {
        processingQueue.async { [weak self] in
            guard let self = self else { return }

            if !self.captureSession.isRunning {
                self.captureSession.startRunning()

                // Update published property on main thread
                DispatchQueue.main.async {
                    self.isRunning = true
                }
            }
        }
    }

    /// Stops the camera capture session.
    ///
    /// Call this when the rangefinder view disappears or the app
    /// enters the background to conserve battery.
    func stopCapture() {
        processingQueue.async { [weak self] in
            guard let self = self else { return }

            if self.captureSession.isRunning {
                self.captureSession.stopRunning()

                DispatchQueue.main.async {
                    self.isRunning = false
                }
            }
        }
    }

    // MARK: - Zoom Control

    /// Sets the camera zoom factor.
    ///
    /// Zoom affects the effective focal length and field of view:
    /// - Higher zoom = larger pixel size for distant objects = better accuracy at range
    /// - Higher zoom = smaller field of view = harder to find/track targets
    ///
    /// - Parameter factor: Desired zoom factor (1.0 = no zoom).
    ///   Values are clamped to the device's supported range.
    func setZoom(_ factor: CGFloat) {
        guard let device = videoDevice else { return }

        // Clamp to device's supported range
        let clampedFactor = max(1.0, min(factor, device.maxAvailableVideoZoomFactor))

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clampedFactor
            device.unlockForConfiguration()

            DispatchQueue.main.async {
                self.zoomFactor = clampedFactor
            }
        } catch {
            print("Failed to set zoom: \(error)")
        }
    }

    // MARK: - Focus Control

    /// Sets a specific focus point in the image.
    ///
    /// Use this when the user taps on a specific target to ensure
    /// it's in sharp focus for accurate detection.
    ///
    /// - Parameter point: Normalized point (0-1 range for both x and y).
    func setFocusPoint(_ point: CGPoint) {
        guard let device = videoDevice else { return }

        guard device.isFocusPointOfInterestSupported else { return }

        do {
            try device.lockForConfiguration()
            device.focusPointOfInterest = point
            device.focusMode = .autoFocus  // One-shot focus at this point
            device.unlockForConfiguration()
        } catch {
            print("Failed to set focus point: \(error)")
        }
    }

    /// Locks the current focus distance.
    ///
    /// Use this after focusing on a target to prevent the camera
    /// from refocusing on other objects in the scene.
    func lockFocus() {
        guard let device = videoDevice else { return }

        guard device.isFocusModeSupported(.locked) else { return }

        do {
            try device.lockForConfiguration()
            device.focusMode = .locked
            device.unlockForConfiguration()
        } catch {
            print("Failed to lock focus: \(error)")
        }
    }

    // MARK: - Intrinsics Extraction

    /// Extracts camera intrinsics from a sample buffer's metadata.
    ///
    /// iOS provides the camera intrinsic matrix as a buffer attachment
    /// when `isCameraIntrinsicMatrixDeliveryEnabled` is true.
    ///
    /// - Parameter sampleBuffer: The camera frame sample buffer.
    /// - Returns: Extracted intrinsics, or `nil` if not available.
    private func extractIntrinsics(from sampleBuffer: CMSampleBuffer) -> CameraIntrinsics? {
        // Get all attachments from the buffer
        guard let attachments = CMCopyDictionaryOfAttachments(
            allocator: kCFAllocatorDefault,
            target: sampleBuffer,
            attachmentMode: kCMAttachmentMode_ShouldPropagate
        ) as? [String: Any] else {
            return nil
        }

        // Look for the intrinsic matrix attachment
        // Key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix
        if let matrixData = attachments[kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix as String] as? Data {
            return parseIntrinsicMatrix(matrixData, sampleBuffer: sampleBuffer)
        }

        return nil
    }

    /// Parses the raw intrinsic matrix data into a CameraIntrinsics struct.
    ///
    /// The matrix is provided as a 3x3 float matrix in row-major order:
    /// ```
    /// | fx  0   cx |
    /// | 0   fy  cy |
    /// | 0   0   1  |
    /// ```
    ///
    /// - Parameters:
    ///   - data: Raw bytes containing the matrix_float3x3.
    ///   - sampleBuffer: Used to get image dimensions.
    /// - Returns: Parsed intrinsics, or `nil` if parsing fails.
    private func parseIntrinsicMatrix(_ data: Data, sampleBuffer: CMSampleBuffer) -> CameraIntrinsics? {
        // Verify we have enough data for a 3x3 float matrix
        guard data.count >= MemoryLayout<matrix_float3x3>.size else {
            return nil
        }

        // Reinterpret the data as a simd matrix
        let matrix = data.withUnsafeBytes { ptr -> matrix_float3x3 in
            ptr.load(as: matrix_float3x3.self)
        }

        // Get image dimensions from the format description
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return nil
        }

        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)

        // Extract values from the matrix
        // column 0, row 0 = fx (horizontal focal length)
        // column 1, row 1 = fy (vertical focal length)
        // column 2, row 0 = cx (principal point x)
        // column 2, row 1 = cy (principal point y)
        return CameraIntrinsics(
            focalLengthX: matrix.columns.0.x,     // fx
            focalLengthY: matrix.columns.1.y,     // fy
            principalPointX: matrix.columns.2.x,  // cx
            principalPointY: matrix.columns.2.y,  // cy
            referenceWidth: Int(dimensions.width),
            referenceHeight: Int(dimensions.height)
        )
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

/// Extension handling the delegate callbacks for video frame delivery.
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    /// Called when a new video frame is captured.
    ///
    /// This is the main entry point for frame processing. It:
    /// 1. Implements frame skipping for performance
    /// 2. Extracts the pixel buffer
    /// 3. Extracts or provides default intrinsics
    /// 4. Publishes the frame for downstream processing
    ///
    /// - Parameters:
    ///   - output: The capture output that produced the frame.
    ///   - sampleBuffer: The captured frame data.
    ///   - connection: The connection that delivered the frame.
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Implement frame skipping for performance
        // Only process every Nth frame to reduce CPU/GPU load
        frameCount += 1
        guard frameCount % processEveryNthFrame == 0 else { return }

        // Extract the pixel buffer (raw image data)
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // Extract intrinsics from metadata, or use defaults
        let intrinsics = extractIntrinsics(from: sampleBuffer) ?? CameraIntrinsics.defaultiPhone12Wide

        // Update published properties periodically (not every frame)
        // to avoid overwhelming SwiftUI with updates
        if frameCount % (processEveryNthFrame * 5) == 0 {
            DispatchQueue.main.async { [weak self] in
                self?.currentFrame = pixelBuffer
                self?.cameraIntrinsics = intrinsics
            }
        }

        // Publish frame for vision pipeline processing
        framePublisher.send((pixelBuffer, intrinsics))
    }

    /// Called when a video frame was dropped due to processing backlog.
    ///
    /// This can happen if downstream processing is too slow.
    /// Consider increasing `processEveryNthFrame` if this happens frequently.
    ///
    /// - Parameters:
    ///   - output: The capture output.
    ///   - sampleBuffer: The dropped frame.
    ///   - connection: The connection.
    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Frame was dropped due to processing backlog
        // Uncomment for debugging performance issues:
        // print("Frame dropped")
    }
}

// MARK: - Camera Preview View

import SwiftUI

/// SwiftUI wrapper for displaying the camera preview layer.
///
/// This view provides a live camera preview by wrapping an AVCaptureVideoPreviewLayer.
/// It automatically handles the connection to the capture session.
///
/// ## Usage
/// ```swift
/// CameraPreviewView(cameraManager: cameraManager)
///     .ignoresSafeArea()
/// ```
struct CameraPreviewView: UIViewRepresentable {

    /// The camera manager providing the capture session.
    let cameraManager: CameraManager

    /// Creates the UIKit view for the preview.
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.session = cameraManager.captureSession
        return view
    }

    /// Updates the view when SwiftUI state changes.
    ///
    /// No updates needed since the session reference doesn't change.
    func updateUIView(_ uiView: PreviewView, context: Context) {
        // No updates needed - session is set once
    }

    /// Custom UIView subclass that uses AVCaptureVideoPreviewLayer as its backing layer.
    ///
    /// By overriding `layerClass`, we get a preview layer automatically
    /// that fills the entire view bounds.
    class PreviewView: UIView {

        /// Specifies that this view's backing layer should be a preview layer.
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        /// Typed access to the preview layer.
        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        /// The capture session to display.
        ///
        /// Setting this connects the preview layer to the camera output.
        var session: AVCaptureSession? {
            get { previewLayer.session }
            set {
                previewLayer.session = newValue
                // Fill the entire view while maintaining aspect ratio
                previewLayer.videoGravity = .resizeAspectFill
            }
        }
    }
}
