//
//  SniperScopeApp.swift
//  SniperScope
//
//  Main application entry point for the passive rangefinding app.
//
//  This file defines the app's entry point, global state management, and initial
//  view hierarchy including onboarding flow for first-time users.
//
//  Architecture Overview:
//  ----------------------
//  SniperScope uses SwiftUI with a service-oriented architecture:
//  - AppState: Global observable state for app-wide concerns
//  - CameraManager: AVFoundation camera handling (Camera/CameraManager.swift)
//  - VisionPipeline: ML inference orchestration (Vision/VisionPipeline.swift)
//  - RangingEngine: Distance calculation with sensor fusion (Ranging/RangingEngine.swift)
//
//  The Pinhole Camera Model:
//  -------------------------
//  Distance = (Real_Object_Size × Focal_Length) / Pixel_Size
//
//  This formula is the core of passive rangefinding - by knowing an object's
//  real-world size and measuring its pixel size in the image, we can calculate
//  the distance using the camera's known focal length.
//
//  Copyright (c) 2025. For educational use only.
//

import SwiftUI

// MARK: - App Entry Point

/// The main entry point for the SniperScope application.
///
/// Uses the `@main` attribute to designate this as the app's starting point.
/// The app uses a single `WindowGroup` scene with dark mode enforced for
/// optimal visibility of the rangefinder UI elements.
@main
struct SniperScopeApp: App {

    // MARK: - State Objects

    /// Global application state shared across all views via environment.
    ///
    /// `@StateObject` ensures this instance persists for the app's lifetime
    /// and isn't recreated when views are re-rendered.
    @StateObject private var appState = AppState()

    // MARK: - App Body

    /// Defines the app's scene hierarchy.
    ///
    /// The `WindowGroup` provides the main window for the iOS app.
    /// We inject `appState` into the environment so all child views
    /// can access it via `@EnvironmentObject`.
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)  // Inject app state into view hierarchy
                .preferredColorScheme(.dark)  // Force dark mode for rangefinder UI
        }
    }
}

// MARK: - App State

/// Global application state management.
///
/// Tracks app initialization status, permission states, and error conditions.
/// Published as an `ObservableObject` so views can react to state changes.
///
/// ## Usage
/// ```swift
/// @EnvironmentObject var appState: AppState
///
/// if appState.isInitialized {
///     // Show main interface
/// }
/// ```
///
/// ## Properties
/// - `isInitialized`: True when app is ready to use
/// - `hasPermissions`: True when camera permission granted
/// - `currentError`: Current error state, nil if no error
class AppState: ObservableObject {

    // MARK: - Published Properties

    /// Whether the app has completed initialization.
    ///
    /// Set to `true` after:
    /// 1. Onboarding is complete (or skipped on subsequent launches)
    /// 2. Initial delay for UI smoothness has passed
    ///
    /// When `true`, `ContentView` shows `RangefinderView` instead of `LoadingView`.
    @Published var isInitialized = false

    /// Whether all required permissions (camera) have been granted.
    ///
    /// Camera permission is requested when `RangefinderView` appears.
    /// The app cannot function without camera access.
    @Published var hasPermissions = false

    /// Current error state, if any.
    ///
    /// `nil` when no error is present. Set to an `AppError` value
    /// when something goes wrong that the user needs to know about.
    @Published var currentError: AppError?

    // MARK: - Error Definitions

    /// Possible app-level errors that can occur during operation.
    ///
    /// Conforms to `LocalizedError` to provide user-friendly descriptions.
    enum AppError: LocalizedError {

        /// User denied camera access.
        ///
        /// The app cannot function without camera permission.
        /// User must go to Settings to grant access.
        case cameraPermissionDenied

        /// Failed to load CoreML models.
        ///
        /// Object detection won't work without the ML model.
        /// May indicate corrupted or missing model file.
        case modelLoadFailed

        /// Camera calibration data unavailable.
        ///
        /// The camera intrinsics matrix couldn't be obtained.
        /// Ranging will fall back to default intrinsics which may be less accurate.
        case calibrationRequired

        /// Human-readable error descriptions for display to user.
        var errorDescription: String? {
            switch self {
            case .cameraPermissionDenied:
                return "Camera access is required for rangefinding"
            case .modelLoadFailed:
                return "Failed to load ML models"
            case .calibrationRequired:
                return "Camera calibration required"
            }
        }
    }
}

// MARK: - Content View

/// Root content view that handles initialization and navigation.
///
/// This view acts as a router, showing different content based on app state:
/// - `LoadingView`: While app is initializing
/// - `RangefinderView`: When app is ready
/// - `OnboardingView`: As a sheet on first launch
///
/// ## Initialization Flow
/// 1. View appears, triggers `checkPermissionsAndInitialize()`
/// 2. If first launch, shows onboarding sheet
/// 3. Async initialization runs (with brief delay for UI smoothness)
/// 4. `appState.isInitialized` set to `true`
/// 5. View switches to `RangefinderView`
struct ContentView: View {

    // MARK: - Environment

    /// Access to global app state for checking initialization status.
    @EnvironmentObject var appState: AppState

    // MARK: - Local State

    /// Controls presentation of onboarding sheet.
    ///
    /// Set to `true` on first launch, triggering sheet presentation.
    @State private var showOnboarding = false

    // MARK: - Body

    var body: some View {
        Group {
            // Conditional rendering based on initialization state
            if appState.isInitialized {
                // App is ready - show main rangefinder interface
                RangefinderView()
            } else {
                // Still initializing - show loading screen with animation
                LoadingView()
            }
        }
        .onAppear {
            // Begin initialization sequence when view first appears
            checkPermissionsAndInitialize()
        }
        .sheet(isPresented: $showOnboarding) {
            // First-launch onboarding presented as modal sheet
            OnboardingView(isPresented: $showOnboarding)
        }
    }

    // MARK: - Initialization Methods

    /// Checks for first launch and triggers initialization sequence.
    ///
    /// ## First Launch Behavior
    /// - Shows onboarding sheet explaining app functionality
    /// - Sets `hasLaunchedBefore` flag in UserDefaults
    ///
    /// ## Every Launch
    /// - Triggers async initialization via `initializeApp()`
    private func checkPermissionsAndInitialize() {
        // Check if this is first launch using UserDefaults persistence
        let hasLaunched = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")

        if !hasLaunched {
            // First launch - show onboarding to explain app functionality
            showOnboarding = true
            // Mark that we've launched so we don't show onboarding again
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }

        // Start async initialization
        // Note: This runs concurrently with onboarding if shown
        Task {
            await initializeApp()
        }
    }

    /// Async initialization sequence.
    ///
    /// Performs a brief delay then marks app as initialized.
    ///
    /// ## Why the delay?
    /// - Allows loading animation to be visible
    /// - Gives time for any background setup to complete
    /// - Smoother user experience than instant transition
    ///
    /// ## Note
    /// Heavy initialization (camera, ML models) happens in `RangefinderView`
    /// to avoid blocking app launch. This method just handles the UI transition.
    private func initializeApp() async {
        // Brief delay (0.5 seconds) for loading animation visibility
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Update state on main thread (required for @Published properties)
        await MainActor.run {
            appState.isInitialized = true
        }
    }
}

// MARK: - Loading View

/// Full-screen loading indicator shown during app initialization.
///
/// Features an animated scope icon that rotates continuously,
/// providing visual feedback that the app is working.
///
/// ## Visual Design
/// - Black background for consistency with main UI
/// - Green accent color matching app theme
/// - Large scope icon with rotation animation
/// - App name and "Initializing..." status text
struct LoadingView: View {

    // MARK: - Animation State

    /// Current rotation angle for the scope icon animation.
    ///
    /// Animates from 0 to 360 degrees continuously.
    @State private var rotation: Double = 0

    // MARK: - Body

    var body: some View {
        ZStack {
            // Black background filling entire screen including safe areas
            Color.black.ignoresSafeArea()

            VStack(spacing: 30) {
                // Animated scope icon - represents the rangefinding concept
                Image(systemName: "scope")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        // Start continuous rotation animation when view appears
                        // linear(duration: 2) = one full rotation every 2 seconds
                        // repeatForever = animation loops indefinitely
                        // autoreverses: false = always rotates same direction
                        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }

                // App title
                Text("SniperScope")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                // Status text indicating what's happening
                Text("Initializing...")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                // Circular progress indicator (indeterminate)
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .green))
                    .scaleEffect(1.5)  // Make it larger for visibility
            }
        }
    }
}

// MARK: - Onboarding View

/// First-launch onboarding flow explaining app functionality.
///
/// Presents a three-page paged interface using `TabView`:
/// 1. **Passive Rangefinding**: Explains the core concept
/// 2. **Object Detection**: Explains how detection works
/// 3. **Camera Access**: Prepares user for permission request
///
/// ## Navigation
/// - "Next" button advances through pages
/// - "Get Started" on final page dismisses the onboarding
/// - Page dots show current position
struct OnboardingView: View {

    // MARK: - Bindings

    /// Controls dismissal of the onboarding sheet.
    ///
    /// Set to `false` to dismiss when user taps "Get Started".
    @Binding var isPresented: Bool

    // MARK: - Local State

    /// Currently displayed page index (0, 1, or 2).
    @State private var currentPage = 0

    // MARK: - Body

    var body: some View {
        ZStack {
            // Black background matching app theme
            Color.black.ignoresSafeArea()

            VStack {
                // Paged tab view with horizontal swipe navigation
                TabView(selection: $currentPage) {

                    // Page 1: Explain passive rangefinding concept
                    OnboardingPage(
                        icon: "scope",
                        title: "Passive Rangefinding",
                        description: "Estimate distances up to 1000 yards using only your camera - no laser required."
                    )
                    .tag(0)

                    // Page 2: Explain object detection
                    OnboardingPage(
                        icon: "person.fill",
                        title: "Object Detection",
                        description: "Automatically detects people, vehicles, and wildlife to calculate distance based on known sizes."
                    )
                    .tag(1)

                    // Page 3: Prepare for camera permission
                    OnboardingPage(
                        icon: "camera.fill",
                        title: "Camera Access",
                        description: "SniperScope needs camera access to analyze the scene and estimate distances."
                    )
                    .tag(2)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))  // Show page dots

                // Navigation button - changes text based on current page
                Button(action: {
                    if currentPage < 2 {
                        // Not on last page - advance to next
                        withAnimation {
                            currentPage += 1
                        }
                    } else {
                        // On last page - dismiss onboarding
                        isPresented = false
                    }
                }) {
                    Text(currentPage < 2 ? "Next" : "Get Started")
                        .font(.headline)
                        .foregroundColor(.black)  // Dark text on green button
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Onboarding Page

/// Single page component for onboarding flow.
///
/// Displays vertically centered content:
/// - Large SF Symbol icon
/// - Bold title text
/// - Gray description text
///
/// Used by `OnboardingView` to create consistent page layouts.
struct OnboardingPage: View {

    // MARK: - Properties

    /// SF Symbol name for the page icon.
    ///
    /// Examples: "scope", "person.fill", "camera.fill"
    let icon: String

    /// Page title displayed below the icon.
    let title: String

    /// Detailed description explaining the feature.
    ///
    /// Displayed in gray, centered, with horizontal padding.
    let description: String

    // MARK: - Body

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // Large icon representing the page's concept
            Image(systemName: icon)
                .font(.system(size: 100))
                .foregroundColor(.green)

            // Bold title
            Text(title)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)

            // Description with centered alignment
            Text(description)
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
            Spacer()  // Extra spacer to push content up slightly
        }
    }
}
