//
//  KnownObjectDatabase.swift
//  SniperScope
//
//  Database of real-world object sizes for passive rangefinding.
//
//  This file contains the critical lookup table that enables size-based
//  ranging. Without known object sizes, the pinhole camera model cannot
//  produce absolute distances.
//
//  Data Sources:
//  -------------
//  - Humans: ANSUR II (US Army anthropometric survey), CAESAR database
//  - Vehicles: US manufacturer specifications, EPA vehicle database
//  - Wildlife: USFWS guides, state wildlife agency data
//  - Structures: ANSI/ICC building codes, standard dimensions
//  - Signs: MUTCD (Manual on Uniform Traffic Control Devices)
//
//  Measurement Philosophy:
//  ----------------------
//  We store the most reliably measurable dimension for each object:
//  - People: Standing height (most consistent when not occluded)
//  - Vehicles: Height (visible from most angles)
//  - Wildlife: Shoulder height (visible when animal is broadside)
//  - Signs: Width or height depending on shape
//
//  Size Variability:
//  -----------------
//  Objects of the same type vary in size. We track this variability:
//  - Stop signs: ~2% (mandated standard)
//  - Adult humans: ~10% (height varies by population)
//  - Wild boar: ~25% (highly variable by age/sex)
//
//  Higher variability = lower confidence in range estimates.
//
//  Copyright (c) 2025. For educational use only.
//

import Foundation

// MARK: - Known Object Size

/// Represents a known real-world object size for ranging calculations.
///
/// Each entry in the database describes:
/// - What the object is (label, type)
/// - Its typical dimensions (size, aspect ratio)
/// - How reliable it is for ranging (variability, weight)
/// - Where the data came from (source)
struct KnownObjectSize {

    /// Category of the object (human, vehicle, etc.).
    let objectType: ObjectType

    /// Label used for lookup (matches detection model output).
    let label: String

    /// Human-readable name for display in UI.
    let displayName: String

    /// Primary dimension in meters used for ranging.
    ///
    /// This is the dimension specified by `measurementType`:
    /// - Height: vertical dimension
    /// - Width: horizontal dimension
    /// - Shoulder height: for quadruped animals
    let sizeMeters: Double

    /// Which dimension the size represents.
    let measurementType: MeasurementType

    /// Population variability (0-1).
    ///
    /// Standard deviation as a fraction of mean size.
    /// Example: 0.10 means ±10% variation is typical.
    let sizeVariability: Float       // 0-1, how much size varies in population

    /// Reliability weight for sensor fusion (0-1).
    ///
    /// Higher weights give this object type more influence in
    /// fused estimates. Based on:
    /// - How standardized the size is
    /// - How reliably we can detect it
    /// - How accurately we can measure its dimensions
    let reliabilityWeight: Float     // 0-1, how reliable for ranging

    /// Expected width/height ratio when viewed normally.
    ///
    /// Used to detect occlusion or unusual poses:
    /// - Standing person: ~0.35 (narrow and tall)
    /// - Vehicle from side: ~2.5 (wide and short)
    let expectedAspectRatio: Float   // Width/Height ratio

    /// Reference for the size data.
    ///
    /// Important for credibility and potential updates.
    let source: String               // Data source reference

    /// How the primary dimension is measured.
    enum MeasurementType: String, Codable {
        /// Vertical height from base to top.
        case height

        /// Horizontal width.
        case width

        /// Diagonal dimension (rarely used).
        case diagonal

        /// Height at shoulder level (for quadruped animals).
        ///
        /// More reliable than total height because:
        /// - Head position varies
        /// - Antlers/ears add uncertainty
        case shoulderHeight  // For animals
    }

    /// Uncertainty in meters based on variability.
    ///
    /// Calculated as: size × variability
    /// Example: 1.70m person with 0.10 variability = ±0.17m
    var sizeUncertainty: Double {
        return sizeMeters * Double(sizeVariability)
    }
}

// MARK: - Object Type

/// Categories of objects that can be detected and ranged.
///
/// Each category has different accuracy characteristics and
/// is displayed differently in the UI.
enum ObjectType: String, CaseIterable, Codable {

    /// Human beings (standing, seated, partial views).
    case human

    /// Motor vehicles (cars, trucks, SUVs, vans, motorcycles).
    case vehicle

    /// Wild animals (deer, elk, bear, turkey, etc.).
    case wildlife

    /// Building elements (doors, windows, garage doors).
    case structure

    /// Road signs (stop signs, speed limits, yield signs).
    case sign

    /// Human-readable name for UI display.
    var displayName: String {
        switch self {
        case .human: return "Person"
        case .vehicle: return "Vehicle"
        case .wildlife: return "Wildlife"
        case .structure: return "Structure"
        case .sign: return "Sign"
        }
    }

    /// SF Symbol icon for UI display.
    var icon: String {
        switch self {
        case .human: return "person.fill"
        case .vehicle: return "car.fill"
        case .wildlife: return "hare.fill"
        case .structure: return "building.2.fill"
        case .sign: return "signpost.right.fill"
        }
    }
}

// MARK: - Known Object Database

/// Singleton database of known object sizes for passive rangefinding.
///
/// This class provides the critical lookup function that maps detected
/// object labels to their known real-world sizes. Without this mapping,
/// the pinhole camera model cannot produce absolute distances.
///
/// ## Data Quality
/// All measurements are sourced from authoritative references:
/// - Government anthropometric surveys
/// - Manufacturing specifications
/// - Official standards (MUTCD, building codes)
///
/// ## Usage
/// ```swift
/// // Get size for a detection
/// if let size = KnownObjectDatabase.shared.getSize(for: "person") {
///     print("Expected height: \(size.sizeMeters)m")
/// }
///
/// // Fuzzy matching for model variations
/// let size = KnownObjectDatabase.shared.getSizeFuzzy(for: "pedestrian")
/// // Returns "person" size
/// ```
///
/// ## Extending the Database
/// To add new objects:
/// 1. Find authoritative size data with source
/// 2. Add entry in `init()` with all required fields
/// 3. Set appropriate variability based on population spread
/// 4. Set reliability weight based on detection/measurement accuracy
class KnownObjectDatabase {

    // MARK: - Singleton

    /// Shared instance of the database.
    static let shared = KnownObjectDatabase()

    // MARK: - Size Database

    /// Internal dictionary mapping labels to size information.
    private let sizeDatabase: [String: KnownObjectSize]

    // MARK: - Initialization

    /// Initializes the database with all known object sizes.
    ///
    /// This is private to enforce singleton pattern.
    private init() {
        var database: [String: KnownObjectSize] = [:]

        // =====================================================================
        // MARK: Humans
        // =====================================================================
        // Source: ANSUR II / CAESAR anthropometric databases
        // These are the largest, most authoritative human measurement studies.

        database["person"] = KnownObjectSize(
            objectType: .human,
            label: "person",
            displayName: "Person (Standing)",
            sizeMeters: 1.70,            // Combined male/female average
            measurementType: .height,
            sizeVariability: 0.10,       // ~10% variation (5th-95th percentile)
            reliabilityWeight: 0.90,     // Very reliable when unoccluded
            expectedAspectRatio: 0.35,   // Shoulder width / height
            source: "ANSUR II Combined Average"
        )

        // Alias for same data
        database["person_standing"] = database["person"]

        database["person_head"] = KnownObjectSize(
            objectType: .human,
            label: "person_head",
            displayName: "Person (Head Only)",
            sizeMeters: 0.23,            // Menton-to-top of head
            measurementType: .height,
            sizeVariability: 0.08,       // Less variation than full height
            reliabilityWeight: 0.85,
            expectedAspectRatio: 0.85,   // Head is roughly round
            source: "ANSUR II Head Height"
        )

        database["person_torso"] = KnownObjectSize(
            objectType: .human,
            label: "person_torso",
            displayName: "Person (Torso)",
            sizeMeters: 0.60,            // Shoulder to waist
            measurementType: .height,
            sizeVariability: 0.12,
            reliabilityWeight: 0.80,     // Less reliable (pose-dependent)
            expectedAspectRatio: 0.75,
            source: "ANSUR II Torso Estimate"
        )

        // =====================================================================
        // MARK: Vehicles
        // =====================================================================
        // Source: US Car Models Database, manufacturer specifications
        // Heights are used because they're visible from most viewing angles.

        database["car"] = KnownObjectSize(
            objectType: .vehicle,
            label: "car",
            displayName: "Sedan/Compact Car",
            sizeMeters: 1.45,            // Average sedan height
            measurementType: .height,
            sizeVariability: 0.10,       // Sedans vary from compact to full-size
            reliabilityWeight: 0.85,
            expectedAspectRatio: 2.8,    // Length/Height when viewed from side
            source: "US Car Models DB - Sedan Average"
        )

        database["suv"] = KnownObjectSize(
            objectType: .vehicle,
            label: "suv",
            displayName: "SUV/Crossover",
            sizeMeters: 1.75,            // Taller than sedans
            measurementType: .height,
            sizeVariability: 0.12,       // Wide range from compact to full-size
            reliabilityWeight: 0.82,
            expectedAspectRatio: 2.2,
            source: "US Car Models DB - SUV Average"
        )

        database["truck"] = KnownObjectSize(
            objectType: .vehicle,
            label: "truck",
            displayName: "Pickup Truck",
            sizeMeters: 1.90,            // F-150 class
            measurementType: .height,
            sizeVariability: 0.12,
            reliabilityWeight: 0.80,
            expectedAspectRatio: 2.5,
            source: "US Car Models DB - Truck Average"
        )

        database["van"] = KnownObjectSize(
            objectType: .vehicle,
            label: "van",
            displayName: "Van/Minivan",
            sizeMeters: 1.85,
            measurementType: .height,
            sizeVariability: 0.10,
            reliabilityWeight: 0.82,
            expectedAspectRatio: 2.0,
            source: "US Car Models DB - Van Average"
        )

        // =====================================================================
        // MARK: Wildlife
        // =====================================================================
        // Sources: USFWS, State Wildlife Agencies
        // Shoulder height is used because it's consistent regardless of head position.

        database["deer"] = KnownObjectSize(
            objectType: .wildlife,
            label: "deer",
            displayName: "White-tailed Deer",
            sizeMeters: 0.95,            // Shoulder height, adult average
            measurementType: .shoulderHeight,
            sizeVariability: 0.12,       // Bucks larger than does
            reliabilityWeight: 0.85,
            expectedAspectRatio: 1.6,    // Body length / shoulder height
            source: "USFWS Wildlife Guide"
        )

        database["elk"] = KnownObjectSize(
            objectType: .wildlife,
            label: "elk",
            displayName: "Rocky Mountain Elk",
            sizeMeters: 1.50,            // Shoulder height, adult bull
            measurementType: .shoulderHeight,
            sizeVariability: 0.10,       // Bulls much larger than cows
            reliabilityWeight: 0.88,     // Large target, reliable
            expectedAspectRatio: 1.4,
            source: "Rocky Mountain Elk Foundation"
        )

        database["wild_boar"] = KnownObjectSize(
            objectType: .wildlife,
            label: "wild_boar",
            displayName: "Wild Boar/Feral Hog",
            sizeMeters: 0.75,
            measurementType: .shoulderHeight,
            sizeVariability: 0.25,       // HIGH variability - wide size range
            reliabilityWeight: 0.65,     // Lower reliability due to variability
            expectedAspectRatio: 2.0,
            source: "Texas Parks & Wildlife"
        )

        database["coyote"] = KnownObjectSize(
            objectType: .wildlife,
            label: "coyote",
            displayName: "Coyote",
            sizeMeters: 0.58,
            measurementType: .shoulderHeight,
            sizeVariability: 0.12,
            reliabilityWeight: 0.70,     // Small target, harder to measure
            expectedAspectRatio: 1.8,
            source: "National Park Service"
        )

        database["bear"] = KnownObjectSize(
            objectType: .wildlife,
            label: "bear",
            displayName: "Black Bear",
            sizeMeters: 0.90,            // On all fours
            measurementType: .shoulderHeight,
            sizeVariability: 0.20,       // High variation by sex/season
            reliabilityWeight: 0.70,
            expectedAspectRatio: 1.5,
            source: "North American Bear Center"
        )

        database["turkey"] = KnownObjectSize(
            objectType: .wildlife,
            label: "turkey",
            displayName: "Wild Turkey",
            sizeMeters: 0.90,            // Standing tom
            measurementType: .height,
            sizeVariability: 0.20,       // Toms much larger than hens
            reliabilityWeight: 0.60,     // Pose-dependent height
            expectedAspectRatio: 0.6,
            source: "National Wild Turkey Federation"
        )

        database["antelope"] = KnownObjectSize(
            objectType: .wildlife,
            label: "antelope",
            displayName: "Pronghorn Antelope",
            sizeMeters: 0.87,
            measurementType: .shoulderHeight,
            sizeVariability: 0.08,       // Fairly uniform size
            reliabilityWeight: 0.85,
            expectedAspectRatio: 1.5,
            source: "Wyoming Game & Fish"
        )

        // =====================================================================
        // MARK: Structures
        // =====================================================================
        // Source: ANSI/ICC building codes, standard dimensions
        // These are highly standardized and excellent for ranging.

        database["door"] = KnownObjectSize(
            objectType: .structure,
            label: "door",
            displayName: "Standard Door",
            sizeMeters: 2.03,            // 80 inches (US standard)
            measurementType: .height,
            sizeVariability: 0.03,       // Very standardized
            reliabilityWeight: 0.95,     // Excellent reference
            expectedAspectRatio: 0.45,   // 36"/80"
            source: "ANSI Standard Door Dimensions"
        )

        database["window"] = KnownObjectSize(
            objectType: .structure,
            label: "window",
            displayName: "Residential Window",
            sizeMeters: 1.20,
            measurementType: .height,
            sizeVariability: 0.25,       // High variability - many sizes
            reliabilityWeight: 0.65,     // Less reliable
            expectedAspectRatio: 0.75,
            source: "Common Residential Sizes"
        )

        database["garage_door"] = KnownObjectSize(
            objectType: .structure,
            label: "garage_door",
            displayName: "Single Garage Door",
            sizeMeters: 2.13,            // 7 feet (standard)
            measurementType: .height,
            sizeVariability: 0.05,
            reliabilityWeight: 0.90,
            expectedAspectRatio: 1.14,   // 8'/7'
            source: "Standard Garage Dimensions"
        )

        // =====================================================================
        // MARK: Signs
        // =====================================================================
        // Source: MUTCD (Manual on Uniform Traffic Control Devices)
        // These are federally mandated standards - highly reliable.

        database["stop_sign"] = KnownObjectSize(
            objectType: .sign,
            label: "stop_sign",
            displayName: "Stop Sign",
            sizeMeters: 0.762,           // 30 inches (standard)
            measurementType: .width,     // Octagon width
            sizeVariability: 0.02,       // Highly standardized
            reliabilityWeight: 0.98,     // Excellent reference
            expectedAspectRatio: 1.0,    // Octagon is symmetric
            source: "MUTCD R1-1"
        )

        database["speed_limit_sign"] = KnownObjectSize(
            objectType: .sign,
            label: "speed_limit_sign",
            displayName: "Speed Limit Sign",
            sizeMeters: 0.762,           // 30 inches height
            measurementType: .height,
            sizeVariability: 0.05,       // Some size variations exist
            reliabilityWeight: 0.95,
            expectedAspectRatio: 0.8,    // 24"×30" (W×H)
            source: "MUTCD R2-1"
        )

        database["yield_sign"] = KnownObjectSize(
            objectType: .sign,
            label: "yield_sign",
            displayName: "Yield Sign",
            sizeMeters: 0.914,           // 36 inches
            measurementType: .width,
            sizeVariability: 0.02,
            reliabilityWeight: 0.95,
            expectedAspectRatio: 1.15,   // Equilateral triangle
            source: "MUTCD R1-2"
        )

        self.sizeDatabase = database
    }

    // MARK: - Lookup Methods

    /// Gets size information for an exact label match.
    ///
    /// - Parameter label: Detection label to look up (case-insensitive).
    /// - Returns: Size information, or nil if not found.
    func getSize(for label: String) -> KnownObjectSize? {
        return sizeDatabase[label.lowercased()]
    }

    /// Gets size information with fuzzy/partial matching.
    ///
    /// This method handles variations in detection model output:
    /// - "pedestrian" → matches "person"
    /// - "automobile" → matches "car"
    /// - "white_tailed_deer" → matches "deer"
    ///
    /// Search order:
    /// 1. Exact match
    /// 2. Label contains key or key contains label
    /// 3. Display name contains label
    /// 4. Common category fallbacks
    ///
    /// - Parameter label: Detection label to look up.
    /// - Returns: Best matching size information, or nil if no match.
    func getSizeFuzzy(for label: String) -> KnownObjectSize? {
        let normalizedLabel = label.lowercased()

        // Exact match first
        if let exact = sizeDatabase[normalizedLabel] {
            return exact
        }

        // Fuzzy match: check containment both ways
        for (key, size) in sizeDatabase {
            // Check if label contains key or key contains label
            if normalizedLabel.contains(key) || key.contains(normalizedLabel) {
                return size
            }

            // Check display name
            if size.displayName.lowercased().contains(normalizedLabel) {
                return size
            }
        }

        // Default fallback for common category aliases
        if normalizedLabel.contains("person") || normalizedLabel.contains("human") ||
           normalizedLabel.contains("pedestrian") || normalizedLabel.contains("people") {
            return sizeDatabase["person"]
        }

        if normalizedLabel.contains("car") || normalizedLabel.contains("vehicle") ||
           normalizedLabel.contains("automobile") {
            return sizeDatabase["car"]
        }

        return nil
    }

    /// Gets all sizes for a specific object type.
    ///
    /// Useful for displaying available objects in settings UI.
    ///
    /// - Parameter type: Object category to filter by.
    /// - Returns: Array of all sizes in that category.
    func getSizes(for type: ObjectType) -> [KnownObjectSize] {
        return sizeDatabase.values.filter { $0.objectType == type }
    }

    /// All available labels in the database, sorted alphabetically.
    var allLabels: [String] {
        return Array(sizeDatabase.keys).sorted()
    }

    /// All sizes sorted by reliability (most reliable first).
    var allSizesByReliability: [KnownObjectSize] {
        return sizeDatabase.values.sorted { $0.reliabilityWeight > $1.reliabilityWeight }
    }

    // MARK: - Statistics

    /// Gets statistical information about size variability.
    ///
    /// Useful for understanding uncertainty in range estimates.
    ///
    /// - Parameter label: Object label to analyze.
    /// - Returns: Statistics struct with mean, std dev, and confidence intervals.
    func getStatistics(for label: String) -> SizeStatistics? {
        guard let size = getSize(for: label) else { return nil }

        return SizeStatistics(
            mean: size.sizeMeters,
            standardDeviation: size.sizeMeters * Double(size.sizeVariability),
            min: size.sizeMeters * (1 - Double(size.sizeVariability)),
            max: size.sizeMeters * (1 + Double(size.sizeVariability)),
            confidence95Range: (
                // 95% CI = mean ± 1.96 × std dev
                size.sizeMeters * (1 - 1.96 * Double(size.sizeVariability)),
                size.sizeMeters * (1 + 1.96 * Double(size.sizeVariability))
            )
        )
    }

    /// Statistical summary of object size distribution.
    struct SizeStatistics {
        /// Mean (average) size in meters.
        let mean: Double

        /// Standard deviation of size in meters.
        let standardDeviation: Double

        /// Minimum expected size (mean - 1 std dev).
        let min: Double

        /// Maximum expected size (mean + 1 std dev).
        let max: Double

        /// 95% confidence interval (mean ± 1.96 std dev).
        let confidence95Range: (Double, Double)
    }
}

// MARK: - Codable Support for Persistence

/// Allows KnownObjectSize to be serialized/deserialized.
///
/// Enables saving custom object sizes to UserDefaults or files.
extension KnownObjectSize: Codable {
    enum CodingKeys: String, CodingKey {
        case objectType, label, displayName, sizeMeters
        case measurementType, sizeVariability, reliabilityWeight
        case expectedAspectRatio, source
    }
}
