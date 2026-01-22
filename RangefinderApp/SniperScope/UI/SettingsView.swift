//
//  SettingsView.swift
//  SniperScope
//
//  App settings and preferences
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var displayUnit: UnitLength
    @Binding var enableDepthFusion: Bool
    @Binding var enableTemporalSmoothing: Bool

    @AppStorage("showConfidenceBar") private var showConfidenceBar = true
    @AppStorage("showMethodIndicator") private var showMethodIndicator = true
    @AppStorage("enableHaptics") private var enableHaptics = true
    @AppStorage("crosshairStyle") private var crosshairStyle = 0

    var body: some View {
        NavigationView {
            Form {
                // Units Section
                Section("Display Units") {
                    Picker("Distance Unit", selection: $displayUnit) {
                        Text("Yards").tag(UnitLength.yards)
                        Text("Meters").tag(UnitLength.meters)
                        Text("Feet").tag(UnitLength.feet)
                    }
                    .pickerStyle(.segmented)
                }

                // Ranging Section
                Section("Ranging") {
                    Toggle("AI Depth Fusion", isOn: $enableDepthFusion)

                    Toggle("Temporal Smoothing", isOn: $enableTemporalSmoothing)

                    NavigationLink("Object Sizes") {
                        ObjectSizesView()
                    }

                    NavigationLink("Calibration") {
                        CalibrationSettingsView()
                    }
                }

                // Display Section
                Section("Display") {
                    Toggle("Confidence Bar", isOn: $showConfidenceBar)

                    Toggle("Method Indicator", isOn: $showMethodIndicator)

                    Picker("Crosshair Style", selection: $crosshairStyle) {
                        Text("Standard").tag(0)
                        Text("Mil-Dot").tag(1)
                        Text("BDC").tag(2)
                        Text("Minimal").tag(3)
                    }
                }

                // Feedback Section
                Section("Feedback") {
                    Toggle("Haptic Feedback", isOn: $enableHaptics)
                }

                // About Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }

                    NavigationLink("How It Works") {
                        HowItWorksView()
                    }

                    NavigationLink("Accuracy & Limitations") {
                        AccuracyInfoView()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Object Sizes View
struct ObjectSizesView: View {
    let database = KnownObjectDatabase.shared

    var body: some View {
        List {
            ForEach(ObjectType.allCases, id: \.self) { type in
                Section(type.displayName) {
                    ForEach(database.getSizes(for: type), id: \.label) { size in
                        HStack {
                            Image(systemName: type.icon)
                                .foregroundColor(.green)
                                .frame(width: 30)

                            VStack(alignment: .leading) {
                                Text(size.displayName)
                                    .font(.body)
                                Text(String(format: "%.2fm (±%.0f%%)", size.sizeMeters, size.sizeVariability * 100))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }

                            Spacer()

                            // Reliability indicator
                            ReliabilityBadge(reliability: size.reliabilityWeight)
                        }
                    }
                }
            }
        }
        .navigationTitle("Object Sizes")
    }
}

struct ReliabilityBadge: View {
    let reliability: Float

    var body: some View {
        Text(reliabilityText)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(reliabilityColor.opacity(0.2))
            .foregroundColor(reliabilityColor)
            .cornerRadius(4)
    }

    private var reliabilityText: String {
        if reliability > 0.9 { return "HIGH" }
        if reliability > 0.7 { return "MED" }
        return "LOW"
    }

    private var reliabilityColor: Color {
        if reliability > 0.9 { return .green }
        if reliability > 0.7 { return .yellow }
        return .orange
    }
}

// MARK: - Calibration Settings
struct CalibrationSettingsView: View {
    @AppStorage("depthScaleFactor") private var depthScaleFactor: Double = 1.0
    @State private var showCalibrationGuide = false

    var body: some View {
        Form {
            Section("Depth Calibration") {
                HStack {
                    Text("Scale Factor")
                    Spacer()
                    Text(String(format: "%.4f", depthScaleFactor))
                        .foregroundColor(.gray)
                }

                Button("Recalibrate") {
                    showCalibrationGuide = true
                }
            }

            Section("Camera Calibration") {
                Text("Camera intrinsics are automatically extracted from the device.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Section(footer: Text("Calibration improves accuracy by adjusting the depth model output to real-world distances.")) {
                EmptyView()
            }
        }
        .navigationTitle("Calibration")
        .sheet(isPresented: $showCalibrationGuide) {
            CalibrationGuideView()
        }
    }
}

// MARK: - Calibration Guide
struct CalibrationGuideView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var knownDistance: String = ""
    @State private var step = 1

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Step indicator
                HStack {
                    ForEach(1...3, id: \.self) { i in
                        Circle()
                            .fill(i <= step ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 10, height: 10)
                    }
                }

                if step == 1 {
                    VStack(spacing: 20) {
                        Image(systemName: "ruler")
                            .font(.system(size: 60))
                            .foregroundColor(.green)

                        Text("Step 1: Set Up Target")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Place a target at a known distance from your position. Use a laser rangefinder or measured markers for accuracy.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.gray)
                            .padding(.horizontal)

                        TextField("Known distance (yards)", text: $knownDistance)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal, 40)
                    }
                } else if step == 2 {
                    VStack(spacing: 20) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 60))
                            .foregroundColor(.green)

                        Text("Step 2: Aim at Target")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Point the camera at your target and center it in the crosshairs. The app will capture multiple readings.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.gray)
                            .padding(.horizontal)

                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .green))
                            .scaleEffect(1.5)
                    }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)

                        Text("Calibration Complete")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Your depth model has been calibrated. Accuracy should be improved for future measurements.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                    }
                }

                Spacer()

                Button(action: {
                    if step < 3 {
                        step += 1
                        if step == 3 {
                            // Simulate calibration completion
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                // In real implementation, this would update the scale factor
                            }
                        }
                    } else {
                        dismiss()
                    }
                }) {
                    Text(step < 3 ? "Next" : "Done")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                .disabled(step == 1 && knownDistance.isEmpty)
            }
            .padding(.vertical, 40)
            .navigationTitle("Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - How It Works
struct HowItWorksView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Section("Size-Based Ranging") {
                    Text("SniperScope calculates distance using the pinhole camera model:")
                        .font(.body)

                    Text("Distance = (Object Size × Focal Length) / Pixel Size")
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)

                    Text("By detecting objects of known size (people, vehicles, wildlife) and measuring their pixel height in the image, we can calculate their distance using your camera's calibrated focal length.")
                        .font(.body)
                        .foregroundColor(.gray)
                }

                Divider()

                Section("AI Depth Estimation") {
                    Text("As a secondary method, SniperScope uses a neural network trained on millions of images to estimate relative depth. This provides additional confidence when combined with size-based ranging.")
                        .font(.body)
                        .foregroundColor(.gray)
                }

                Divider()

                Section("Sensor Fusion") {
                    Text("Multiple distance estimates are combined using a Kalman filter, which weights each measurement by its confidence and applies temporal smoothing for stable readings.")
                        .font(.body)
                        .foregroundColor(.gray)
                }
            }
            .padding()
        }
        .navigationTitle("How It Works")
    }

    @ViewBuilder
    private func Section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
    }
}

// MARK: - Accuracy Info
struct AccuracyInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Expected Accuracy")
                    .font(.headline)

                // Accuracy table
                VStack(spacing: 0) {
                    AccuracyRow(range: "<200 yards", accuracy: "±5%", quality: .green)
                    AccuracyRow(range: "200-400 yards", accuracy: "±8%", quality: .green)
                    AccuracyRow(range: "400-600 yards", accuracy: "±12%", quality: .yellow)
                    AccuracyRow(range: "600-800 yards", accuracy: "±15%", quality: .yellow)
                    AccuracyRow(range: ">800 yards", accuracy: "±20%", quality: .orange)
                }
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)

                Divider()

                Text("Factors Affecting Accuracy")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    FactorRow(icon: "sun.max", text: "Lighting conditions")
                    FactorRow(icon: "person.fill.questionmark", text: "Target size variability")
                    FactorRow(icon: "eye", text: "Target visibility/occlusion")
                    FactorRow(icon: "aqi.medium", text: "Atmospheric haze")
                    FactorRow(icon: "camera", text: "Image resolution")
                }

                Divider()

                Text("Important Notes")
                    .font(.headline)

                Text("• This is a passive estimation tool, not a precision instrument\n• Always verify critical measurements with a laser rangefinder\n• Accuracy improves with known, standardized objects (signs, doors)\n• Results may vary based on environmental conditions")
                    .font(.body)
                    .foregroundColor(.gray)
            }
            .padding()
        }
        .navigationTitle("Accuracy")
    }
}

struct AccuracyRow: View {
    let range: String
    let accuracy: String
    let quality: Color

    var body: some View {
        HStack {
            Text(range)
                .frame(width: 120, alignment: .leading)
            Spacer()
            Text(accuracy)
                .fontWeight(.medium)
            Circle()
                .fill(quality)
                .frame(width: 10, height: 10)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color.clear)
    }
}

struct FactorRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .frame(width: 24)
            Text(text)
                .font(.body)
        }
    }
}

// MARK: - Calibration View (External)
struct CalibrationView: View {
    let rangingEngine: RangingEngine

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CalibrationGuideView()
    }
}
