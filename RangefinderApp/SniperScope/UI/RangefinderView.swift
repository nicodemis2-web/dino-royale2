//
//  RangefinderView.swift
//  SniperScope
//
//  Main rangefinder interface
//

import SwiftUI
import Combine

struct RangefinderView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var visionPipeline = VisionPipeline()
    @StateObject private var rangingEngine = RangingEngine()

    @State private var displayUnit: UnitLength = .yards
    @State private var showSettings = false
    @State private var showCalibration = false
    @State private var zoomLevel: CGFloat = 1.0

    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Camera Preview
                CameraPreviewView(cameraManager: cameraManager)
                    .ignoresSafeArea()

                // Detection Overlays
                DetectionOverlayView(
                    detections: visionPipeline.detections,
                    viewSize: geometry.size
                )

                // Crosshair
                CrosshairView(targetLocked: rangingEngine.targetLocked)

                // HUD Elements
                VStack {
                    // Top bar
                    TopHUDView(
                        confidence: rangingEngine.currentRange.confidence,
                        method: rangingEngine.currentRange.method,
                        zoomLevel: zoomLevel,
                        onSettingsTap: { showSettings = true }
                    )

                    Spacer()

                    // Bottom range display
                    RangeDisplayView(
                        estimate: rangingEngine.currentRange,
                        displayUnit: displayUnit
                    )
                    .padding(.bottom, 50)
                }

                // Zoom slider
                HStack {
                    Spacer()
                    ZoomSliderView(zoomLevel: $zoomLevel)
                        .onChange(of: zoomLevel) { _, newValue in
                            cameraManager.setZoom(newValue)
                        }
                        .padding(.trailing, 20)
                }
            }
        }
        .statusBar(hidden: true)
        .sheet(isPresented: $showSettings) {
            SettingsView(
                displayUnit: $displayUnit,
                enableDepthFusion: $rangingEngine.enableDepthFusion,
                enableTemporalSmoothing: $rangingEngine.enableTemporalSmoothing
            )
        }
        .sheet(isPresented: $showCalibration) {
            CalibrationView(rangingEngine: rangingEngine)
        }
        .task {
            await initialize()
        }
        .onDisappear {
            cameraManager.stopCapture()
        }
    }

    private func initialize() async {
        // Configure camera
        do {
            try await cameraManager.configure()
            cameraManager.startCapture()
        } catch {
            print("Camera configuration failed: \(error)")
            return
        }

        // Load ML models
        do {
            try await visionPipeline.loadModels()
        } catch {
            print("Model loading failed: \(error)")
            // Continue without models for demo
        }

        // Connect camera frames to vision pipeline
        cameraManager.framePublisher
            .receive(on: DispatchQueue.global(qos: .userInteractive))
            .sink { [weak visionPipeline] (pixelBuffer, intrinsics) in
                visionPipeline?.process(pixelBuffer: pixelBuffer, intrinsics: intrinsics)
            }
            .store(in: &cancellables)

        // Connect vision results to ranging engine
        visionPipeline.resultPublisher
            .receive(on: DispatchQueue.global(qos: .userInteractive))
            .sink { [weak rangingEngine] result in
                _ = rangingEngine?.calculateRange(from: result)
            }
            .store(in: &cancellables)
    }
}

// MARK: - Crosshair View
struct CrosshairView: View {
    let targetLocked: Bool

    @State private var animatePulse = false

    var body: some View {
        ZStack {
            // Outer ring (animates when locked)
            Circle()
                .stroke(targetLocked ? Color.green : Color.white.opacity(0.5), lineWidth: 2)
                .frame(width: 60, height: 60)
                .scaleEffect(animatePulse ? 1.1 : 1.0)
                .opacity(animatePulse ? 0.5 : 1.0)

            // Inner crosshair
            Group {
                // Horizontal line
                Rectangle()
                    .fill(Color.green)
                    .frame(width: 30, height: 2)

                // Vertical line
                Rectangle()
                    .fill(Color.green)
                    .frame(width: 2, height: 30)

                // Center dot
                Circle()
                    .fill(targetLocked ? Color.green : Color.white)
                    .frame(width: 6, height: 6)
            }

            // Mil-dot marks
            ForEach([-25, 25], id: \.self) { offset in
                // Horizontal marks
                Rectangle()
                    .fill(Color.green.opacity(0.7))
                    .frame(width: 8, height: 2)
                    .offset(x: CGFloat(offset))

                // Vertical marks
                Rectangle()
                    .fill(Color.green.opacity(0.7))
                    .frame(width: 2, height: 8)
                    .offset(y: CGFloat(offset))
            }

            // Corner brackets
            ForEach([(1, 1), (1, -1), (-1, 1), (-1, -1)], id: \.0) { (xSign, ySign) in
                CornerBracket()
                    .stroke(targetLocked ? Color.green : Color.white.opacity(0.5), lineWidth: 2)
                    .frame(width: 15, height: 15)
                    .offset(
                        x: CGFloat(xSign) * 35,
                        y: CGFloat(ySign) * 35
                    )
                    .rotationEffect(.degrees(Double((xSign + 1) / 2 * 180 + (ySign + 1) / 2 * 90)))
            }
        }
        .onChange(of: targetLocked) { _, locked in
            if locked {
                withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) {
                    animatePulse = true
                }
                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            } else {
                animatePulse = false
            }
        }
    }
}

struct CornerBracket: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        return path
    }
}

// MARK: - Range Display View
struct RangeDisplayView: View {
    let estimate: RangeEstimate
    let displayUnit: UnitLength

    var body: some View {
        VStack(spacing: 8) {
            if estimate.confidence > 0.3 {
                // Main distance
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formattedDistance)
                        .font(.system(size: 72, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)

                    Text(unitLabel)
                        .font(.title)
                        .foregroundColor(.green.opacity(0.8))
                }
                .shadow(color: .black.opacity(0.8), radius: 4)

                // Uncertainty
                HStack(spacing: 8) {
                    Text(formattedUncertainty)
                        .font(.headline)
                        .foregroundColor(.yellow)

                    Text("(\(String(format: "%.1f%%", estimate.uncertaintyPercent)))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                // Confidence bar
                ConfidenceBarView(confidence: estimate.confidence)
                    .frame(width: 200, height: 6)

                // Method indicator
                HStack(spacing: 4) {
                    Image(systemName: estimate.method.icon)
                        .font(.caption)
                    Text(estimate.method.rawValue)
                        .font(.caption)
                }
                .foregroundColor(.gray)

            } else {
                // No valid reading
                Text("---")
                    .font(.system(size: 72, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)

                Text("AIM AT TARGET")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 30)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.7))
        )
    }

    private var formattedDistance: String {
        let value = estimate.distance.converted(to: displayUnit).value
        if value >= 1000 {
            return String(format: "%.0f", value)
        } else if value >= 100 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }

    private var formattedUncertainty: String {
        let value = estimate.uncertainty.converted(to: displayUnit).value
        return String(format: "± %.0f %@", value, unitLabel)
    }

    private var unitLabel: String {
        switch displayUnit {
        case .yards: return "YDS"
        case .meters: return "M"
        case .feet: return "FT"
        default: return "YDS"
        }
    }
}

// MARK: - Confidence Bar
struct ConfidenceBarView: View {
    let confidence: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.3))

                // Fill
                RoundedRectangle(cornerRadius: 3)
                    .fill(confidenceGradient)
                    .frame(width: geometry.size.width * CGFloat(confidence))
            }
        }
    }

    private var confidenceGradient: LinearGradient {
        let color: Color
        if confidence > 0.7 {
            color = .green
        } else if confidence > 0.5 {
            color = .yellow
        } else {
            color = .orange
        }

        return LinearGradient(
            colors: [color.opacity(0.8), color],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Top HUD
struct TopHUDView: View {
    let confidence: Float
    let method: RangingMethod
    let zoomLevel: CGFloat
    let onSettingsTap: () -> Void

    var body: some View {
        HStack {
            // Left: Method and quality
            HStack(spacing: 8) {
                Image(systemName: method.icon)
                    .font(.caption)

                if confidence > 0.3 {
                    Circle()
                        .fill(qualityColor)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(8)
            .background(Color.black.opacity(0.6))
            .cornerRadius(8)

            Spacer()

            // Center: Zoom indicator
            if zoomLevel > 1.0 {
                Text(String(format: "%.1fx", zoomLevel))
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
            }

            Spacer()

            // Right: Settings button
            Button(action: onSettingsTap) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }

    private var qualityColor: Color {
        if confidence > 0.7 { return .green }
        if confidence > 0.5 { return .yellow }
        return .orange
    }
}

// MARK: - Detection Overlay
struct DetectionOverlayView: View {
    let detections: [Detection]
    let viewSize: CGSize

    var body: some View {
        ForEach(detections) { detection in
            DetectionBoxView(detection: detection, viewSize: viewSize)
        }
    }
}

struct DetectionBoxView: View {
    let detection: Detection
    let viewSize: CGSize

    var body: some View {
        let rect = CGRect(
            x: detection.boundingBox.origin.x * viewSize.width,
            y: (1 - detection.boundingBox.origin.y - detection.boundingBox.height) * viewSize.height,
            width: detection.boundingBox.width * viewSize.width,
            height: detection.boundingBox.height * viewSize.height
        )

        ZStack(alignment: .topLeading) {
            // Bounding box
            RoundedRectangle(cornerRadius: 4)
                .stroke(boxColor, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)

            // Label
            Text(detection.label)
                .font(.caption2)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(boxColor)
                .foregroundColor(.black)
                .cornerRadius(2)
                .offset(y: -18)
        }
        .position(x: rect.midX, y: rect.midY)
    }

    private var boxColor: Color {
        if detection.confidence > 0.7 {
            return .green
        } else if detection.confidence > 0.5 {
            return .yellow
        } else {
            return .orange
        }
    }
}

// MARK: - Zoom Slider
struct ZoomSliderView: View {
    @Binding var zoomLevel: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            // Plus button
            Button(action: { zoomLevel = min(zoomLevel + 0.5, 10.0) }) {
                Image(systemName: "plus")
                    .font(.title3)
                    .foregroundColor(.white)
            }

            // Slider track
            ZStack {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 30, height: 150)

                // Fill level
                VStack {
                    Spacer()
                    Capsule()
                        .fill(Color.green)
                        .frame(width: 30, height: 150 * (zoomLevel - 1) / 9)
                }
                .frame(height: 150)
                .clipShape(Capsule())
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let normalized = 1 - (value.location.y / 150)
                        zoomLevel = max(1.0, min(10.0, 1.0 + normalized * 9))
                    }
            )

            // Minus button
            Button(action: { zoomLevel = max(zoomLevel - 0.5, 1.0) }) {
                Image(systemName: "minus")
                    .font(.title3)
                    .foregroundColor(.white)
            }

            // Reset button
            Button(action: { zoomLevel = 1.0 }) {
                Text("1x")
                    .font(.caption)
                    .foregroundColor(.white)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 5)
        .background(Color.black.opacity(0.5))
        .cornerRadius(20)
    }
}
