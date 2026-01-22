# SniperScope Development Plan

## Project Overview

**Product:** SniperScope - Passive Rangefinding App for iOS
**Target Range:** 0 - 1000 yards (914 meters)
**Target Accuracy:** ±5% at short range (<200 yards), ±10-15% at long range (>500 yards)
**Platform:** iOS 17+ (iPhone 12 and later)

---

## Development Phases

```
Phase 1: Foundation (Weeks 1-3)
    │
    ▼
Phase 2: ML Pipeline (Weeks 4-8)
    │
    ▼
Phase 3: Core App Development (Weeks 9-14)
    │
    ▼
Phase 4: Integration & Optimization (Weeks 15-18)
    │
    ▼
Phase 5: Testing & Validation (Weeks 19-22)
    │
    ▼
Phase 6: Polish & Launch (Weeks 23-26)
```

---

## Phase 1: Foundation (Weeks 1-3)

### Goals
- Set up development environment
- Establish project structure
- Create basic camera capture pipeline
- Verify camera intrinsics extraction

### Week 1: Environment Setup

| Task | Description | Deliverable |
|------|-------------|-------------|
| 1.1 | Set up Xcode project with SwiftUI | Project template |
| 1.2 | Configure Git repository | .gitignore, README |
| 1.3 | Set up Python ML environment | requirements.txt, conda env |
| 1.4 | Install Ultralytics, coremltools, PyTorch | Working ML pipeline |
| 1.5 | Create project documentation structure | SKILLS.md, ARCHITECTURE.md |

**Python Environment Setup:**
```bash
conda create -n sniperscope python=3.10
conda activate sniperscope
pip install torch torchvision
pip install ultralytics
pip install coremltools
pip install opencv-python
pip install albumentations
pip install wandb  # Experiment tracking
```

**Xcode Project Configuration:**
- Deployment target: iOS 17.0
- Swift version: 5.9
- Enable Camera usage permission
- Add Core ML and Vision frameworks

### Week 2: Camera Pipeline

| Task | Description | Deliverable |
|------|-------------|-------------|
| 2.1 | Implement AVFoundation camera capture | CameraManager.swift |
| 2.2 | Configure 4K capture at 30fps | High-res frame buffer |
| 2.3 | Extract camera intrinsics per frame | CameraIntrinsics struct |
| 2.4 | Create camera preview view | CameraPreviewView.swift |
| 2.5 | Verify intrinsics on multiple iPhone models | Calibration data |

**Verification Test:**
```swift
// Log intrinsics for each frame
print("Focal Length X: \(intrinsics.focalLengthX)")
print("Focal Length Y: \(intrinsics.focalLengthY)")
print("Principal Point: (\(intrinsics.principalPointX), \(intrinsics.principalPointY))")
```

### Week 3: Basic UI Shell

| Task | Description | Deliverable |
|------|-------------|-------------|
| 3.1 | Create main RangefinderView | SwiftUI view |
| 3.2 | Implement crosshair overlay | CrosshairView.swift |
| 3.3 | Create range display placeholder | RangeDisplayView.swift |
| 3.4 | Add settings screen shell | SettingsView.swift |
| 3.5 | Test on physical devices | Working camera app |

### Phase 1 Deliverables
- [ ] Working iOS project with camera capture
- [ ] Camera intrinsics extraction verified
- [ ] Basic UI shell with crosshair
- [ ] Documentation complete

---

## Phase 2: ML Pipeline (Weeks 4-8)

### Goals
- Prepare training datasets
- Train custom object detection model
- Convert and optimize models for Core ML
- Benchmark on-device performance

### Week 4: Dataset Preparation

| Task | Description | Deliverable |
|------|-------------|-------------|
| 4.1 | Download VisDrone dataset | Raw data |
| 4.2 | Download DDAD depth dataset | Raw data |
| 4.3 | Acquire vehicle dimension database | JSON/CSV |
| 4.4 | Create COCO-format annotations | Annotation files |
| 4.5 | Set up data augmentation pipeline | Augmentation config |

**Dataset Structure:**
```
datasets/
├── visdrone/
│   ├── images/
│   │   ├── train/
│   │   └── val/
│   └── labels/
│       ├── train/
│       └── val/
├── custom_ranging/
│   ├── images/
│   └── labels/
├── depth/
│   ├── ddad/
│   └── kitti/
└── size_databases/
    ├── humans.json
    ├── vehicles.json
    └── wildlife.json
```

### Week 5: Custom Dataset Collection

| Task | Description | Deliverable |
|------|-------------|-------------|
| 5.1 | Define target classes for ranging | Class list |
| 5.2 | Collect field images at known distances | 500+ images |
| 5.3 | Annotate with bounding boxes | YOLO format labels |
| 5.4 | Record ground truth distances | Distance metadata |
| 5.5 | Split into train/val/test sets | Dataset splits |

**Target Classes:**
```yaml
# classes.yaml
names:
  0: person
  1: person_head
  2: car
  3: truck
  4: suv
  5: deer
  6: elk
  7: wild_boar
  8: coyote
  9: door
  10: window
  11: stop_sign
  12: speed_limit_sign
```

**Field Collection Protocol:**
1. Set up laser rangefinder reference
2. Place/find targets at: 50, 100, 200, 300, 400, 500, 600, 800, 1000 yards
3. Capture 20+ images per distance
4. Vary: lighting, angle, partial occlusion
5. Record: distance, weather, time of day

### Week 6: Object Detection Training

| Task | Description | Deliverable |
|------|-------------|-------------|
| 6.1 | Configure YOLO11 training | Config file |
| 6.2 | Train on VisDrone + custom data | Initial model |
| 6.3 | Evaluate on validation set | mAP metrics |
| 6.4 | Fine-tune hyperparameters | Optimized model |
| 6.5 | Train specialized small-object head | Enhanced model |

**Training Command:**
```bash
yolo detect train \
    data=sniperscope.yaml \
    model=yolo11s.pt \
    epochs=100 \
    imgsz=1280 \
    batch=16 \
    device=0 \
    project=sniperscope \
    name=detector_v1
```

**Target Metrics:**
- mAP@0.5: >0.7 for primary classes
- mAP@0.5 small objects: >0.5
- Inference time: <50ms on A14 Bionic

### Week 7: Model Conversion & Optimization

| Task | Description | Deliverable |
|------|-------------|-------------|
| 7.1 | Export YOLO to ONNX | .onnx file |
| 7.2 | Convert ONNX to Core ML | .mlpackage |
| 7.3 | Apply FP16 quantization | Quantized model |
| 7.4 | Test INT8 quantization | Size comparison |
| 7.5 | Benchmark on iPhone | Performance data |

**Conversion Script:**
```python
import coremltools as ct
from ultralytics import YOLO

# Load trained model
model = YOLO('runs/detect/detector_v1/weights/best.pt')

# Export to Core ML
model.export(format='coreml', nms=True, imgsz=1280)

# Further optimization
mlmodel = ct.models.MLModel('best.mlpackage')

# Quantize to FP16
mlmodel_fp16 = ct.models.neural_network.quantization_utils.quantize_weights(
    mlmodel, nbits=16
)
mlmodel_fp16.save('SniperScope_Detector_FP16.mlpackage')
```

### Week 8: Depth Model Integration

| Task | Description | Deliverable |
|------|-------------|-------------|
| 8.1 | Download Depth Anything V2 Core ML | Pre-trained model |
| 8.2 | Test depth inference on iPhone | Working depth |
| 8.3 | Calibrate depth scale factor | Scale parameters |
| 8.4 | Create depth extraction utilities | Swift code |
| 8.5 | Benchmark combined pipeline | Total latency |

**Depth Model Source:**
- Apple Core ML Models: https://developer.apple.com/machine-learning/models/
- HuggingFace: https://huggingface.co/apple/coreml-depth-anything-v2-small

### Phase 2 Deliverables
- [ ] Trained object detection model (mAP >0.7)
- [ ] Core ML converted and optimized models
- [ ] Depth estimation integrated
- [ ] On-device benchmarks (<150ms total)

---

## Phase 3: Core App Development (Weeks 9-14)

### Goals
- Implement complete Vision Pipeline
- Build Ranging Engine with all methods
- Create Known Object Database
- Develop full UI

### Week 9: Vision Pipeline

| Task | Description | Deliverable |
|------|-------------|-------------|
| 9.1 | Implement VNCoreMLRequest for detection | ObjectDetector.swift |
| 9.2 | Implement VNCoreMLRequest for depth | DepthEstimator.swift |
| 9.3 | Create frame processor with async dispatch | VisionPipeline.swift |
| 9.4 | Handle detection results parsing | Detection struct |
| 9.5 | Extract depth values from MLMultiArray | Depth utilities |

### Week 10: Size-Based Ranging

| Task | Description | Deliverable |
|------|-------------|-------------|
| 10.1 | Implement pinhole camera model | Distance calculation |
| 10.2 | Create Known Object Database | KnownObjectDatabase.swift |
| 10.3 | Add human size variations | HumanSizes.swift |
| 10.4 | Add vehicle dimensions | VehicleSizes.swift |
| 10.5 | Add wildlife sizes | WildlifeSizes.swift |

**Size Database Example:**
```swift
// Load from JSON
let humanSizes: [String: KnownObjectSize] = [
    "person": KnownObjectSize(
        sizeMeters: 1.75,
        measurementType: .height,
        sizeVariability: 0.12,
        source: "CAESAR anthropometric database"
    ),
    // ... more entries
]
```

### Week 11: Ranging Engine Core

| Task | Description | Deliverable |
|------|-------------|-------------|
| 11.1 | Implement SizeBasedRanger | Core algorithm |
| 11.2 | Implement DepthBasedRanger | Depth sampling |
| 11.3 | Add confidence calculation | Uncertainty estimation |
| 11.4 | Create RangeEstimate struct | Data model |
| 11.5 | Unit tests for ranging math | Test coverage |

**Ranging Math Tests:**
```swift
func testSizeBasedRanging() {
    // Known: 1.75m person, focal length 3000px, appears 100px tall
    // Expected: (1.75 * 3000) / 100 = 52.5m
    let calculator = SizeBasedRanger()
    let result = calculator.calculate(
        objectSize: 1.75,
        focalLength: 3000,
        pixelSize: 100
    )
    XCTAssertEqual(result.distance, 52.5, accuracy: 0.1)
}
```

### Week 12: Sensor Fusion

| Task | Description | Deliverable |
|------|-------------|-------------|
| 12.1 | Implement Kalman filter | KalmanFilter.swift |
| 12.2 | Create weighted fusion algorithm | FusionEngine.swift |
| 12.3 | Add temporal smoothing | Noise reduction |
| 12.4 | Implement confidence weighting | Adaptive fusion |
| 12.5 | Test fusion accuracy | Validation data |

**Kalman Filter Implementation:**
```swift
class KalmanFilter {
    var state: Double = 0      // Estimated distance
    var covariance: Double = 1 // Uncertainty
    let processNoise: Double = 0.1
    let measurementNoise: Double = 1.0

    func update(measurement: Double) -> Double {
        // Predict
        let predictedCovariance = covariance + processNoise

        // Update
        let kalmanGain = predictedCovariance / (predictedCovariance + measurementNoise)
        state = state + kalmanGain * (measurement - state)
        covariance = (1 - kalmanGain) * predictedCovariance

        return state
    }
}
```

### Week 13: User Interface

| Task | Description | Deliverable |
|------|-------------|-------------|
| 13.1 | Implement detection overlay view | Bounding boxes |
| 13.2 | Create range display with units | Distance readout |
| 13.3 | Add confidence indicator | Visual feedback |
| 13.4 | Build settings view | Preferences |
| 13.5 | Add calibration workflow | User calibration |

### Week 14: UI Polish & Refinement

| Task | Description | Deliverable |
|------|-------------|-------------|
| 14.1 | Add haptic feedback | Target lock feel |
| 14.2 | Implement dark/light modes | Theme support |
| 14.3 | Add VoiceOver accessibility | Accessibility |
| 14.4 | Create onboarding flow | First-run experience |
| 14.5 | Add usage tips | Help system |

### Phase 3 Deliverables
- [ ] Complete Vision Pipeline
- [ ] Working Ranging Engine with all methods
- [ ] Populated Known Object Database
- [ ] Full UI implementation
- [ ] Calibration workflow

---

## Phase 4: Integration & Optimization (Weeks 15-18)

### Goals
- Integrate all components
- Optimize for real-time performance
- Reduce battery consumption
- Memory optimization

### Week 15: Full Integration

| Task | Description | Deliverable |
|------|-------------|-------------|
| 15.1 | Connect all pipeline stages | End-to-end flow |
| 15.2 | Implement frame rate management | FPS control |
| 15.3 | Add error handling | Robust pipeline |
| 15.4 | Create diagnostic logging | Debug output |
| 15.5 | Integration testing | Test suite |

### Week 16: Performance Profiling

| Task | Description | Deliverable |
|------|-------------|-------------|
| 16.1 | Profile with Instruments | Bottleneck report |
| 16.2 | Identify memory hotspots | Memory analysis |
| 16.3 | Measure battery drain | Energy profile |
| 16.4 | GPU utilization analysis | Metal trace |
| 16.5 | Create performance baseline | Metrics document |

**Performance Targets:**
| Metric | Current | Target | Method |
|--------|---------|--------|--------|
| FPS | - | 30 | Pipeline optimization |
| Latency | - | <150ms | Async processing |
| Memory | - | <500MB | Buffer management |
| Battery | - | <15%/hr | Neural Engine usage |

### Week 17: Optimization Implementation

| Task | Description | Deliverable |
|------|-------------|-------------|
| 17.1 | Optimize model loading | Faster startup |
| 17.2 | Implement frame skipping | Adaptive processing |
| 17.3 | Add model caching | Reduced latency |
| 17.4 | Memory pool for buffers | Less allocation |
| 17.5 | Background processing | UI responsiveness |

### Week 18: Battery & Thermal

| Task | Description | Deliverable |
|------|-------------|-------------|
| 18.1 | Implement power modes | Low/balanced/high |
| 18.2 | Add thermal monitoring | Throttling |
| 18.3 | Optimize sensor usage | Minimal polling |
| 18.4 | Test extended sessions | 1-hour battery test |
| 18.5 | Document power guidelines | User guidance |

### Phase 4 Deliverables
- [ ] Fully integrated application
- [ ] Performance targets met
- [ ] Battery optimization complete
- [ ] Thermal management implemented

---

## Phase 5: Testing & Validation (Weeks 19-22)

### Goals
- Validate accuracy against laser rangefinder
- Test across environmental conditions
- Beta testing program
- Bug fixing

### Week 19: Accuracy Validation

| Task | Description | Deliverable |
|------|-------------|-------------|
| 19.1 | Create test protocol | Test methodology |
| 19.2 | Set up test range with markers | Physical setup |
| 19.3 | Collect comparison data | Ground truth |
| 19.4 | Statistical analysis | Accuracy report |
| 19.5 | Identify error patterns | Error analysis |

**Test Protocol:**
```
Test Distances: 50, 100, 150, 200, 300, 400, 500, 600, 800, 1000 yards
Targets: Human silhouette, vehicle, deer decoy
Conditions: Clear day, overcast, dawn/dusk, hazy
Repetitions: 10 measurements per combination
Reference: Laser rangefinder (Leupold RX-2800)

Record:
- App distance reading
- Laser distance reading
- Confidence score
- Environmental conditions
- Target type
```

### Week 20: Environmental Testing

| Task | Description | Deliverable |
|------|-------------|-------------|
| 20.1 | Test in various lighting | Lighting report |
| 20.2 | Test in different weather | Weather report |
| 20.3 | Test at different altitudes | Altitude effects |
| 20.4 | Test with partial occlusion | Occlusion handling |
| 20.5 | Document limitations | User guidelines |

### Week 21: Beta Testing

| Task | Description | Deliverable |
|------|-------------|-------------|
| 21.1 | Set up TestFlight | Beta distribution |
| 21.2 | Recruit beta testers | 50+ testers |
| 21.3 | Create feedback mechanism | Feedback forms |
| 21.4 | Monitor crash reports | Stability data |
| 21.5 | Collect usage analytics | Usage patterns |

### Week 22: Bug Fixes & Refinement

| Task | Description | Deliverable |
|------|-------------|-------------|
| 22.1 | Triage beta feedback | Priority list |
| 22.2 | Fix critical bugs | Bug fixes |
| 22.3 | Address accuracy issues | Model updates |
| 22.4 | UI/UX improvements | Polish |
| 22.5 | Performance fixes | Optimization |

### Phase 5 Deliverables
- [ ] Accuracy validation report
- [ ] Environmental testing complete
- [ ] Beta feedback incorporated
- [ ] Critical bugs fixed

---

## Phase 6: Polish & Launch (Weeks 23-26)

### Goals
- Final polish
- App Store submission
- Marketing materials
- Launch

### Week 23: Final Polish

| Task | Description | Deliverable |
|------|-------------|-------------|
| 23.1 | Final UI review | Design sign-off |
| 23.2 | Accessibility audit | A11y compliance |
| 23.3 | Localization (if needed) | Translations |
| 23.4 | Final performance pass | Optimization |
| 23.5 | Code cleanup | Clean codebase |

### Week 24: App Store Preparation

| Task | Description | Deliverable |
|------|-------------|-------------|
| 24.1 | Create App Store screenshots | Marketing assets |
| 24.2 | Write App Store description | Copy |
| 24.3 | Create app preview video | Video asset |
| 24.4 | Prepare privacy policy | Legal document |
| 24.5 | Set up pricing | Pricing strategy |

### Week 25: Submission & Review

| Task | Description | Deliverable |
|------|-------------|-------------|
| 25.1 | Submit to App Store | Submission |
| 25.2 | Respond to review feedback | Revisions |
| 25.3 | Prepare support documentation | Help docs |
| 25.4 | Set up support email | Support channel |
| 25.5 | Plan launch announcement | Marketing plan |

### Week 26: Launch

| Task | Description | Deliverable |
|------|-------------|-------------|
| 26.1 | App Store release | Live app |
| 26.2 | Monitor initial reviews | Feedback tracking |
| 26.3 | Address urgent issues | Hot fixes |
| 26.4 | Collect v1.1 feedback | Roadmap input |
| 26.5 | Post-launch retrospective | Lessons learned |

### Phase 6 Deliverables
- [ ] App Store listing complete
- [ ] App approved and live
- [ ] Support infrastructure ready
- [ ] Launch successful

---

## Risk Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| ML accuracy insufficient | Medium | High | Fallback to size-only ranging |
| Core ML conversion issues | Medium | Medium | Use ONNX intermediate format |
| Battery drain too high | Medium | Medium | Implement power modes |
| App Store rejection | Low | High | Follow guidelines strictly |
| Object detection fails at range | High | High | Train on more long-range data |
| Camera intrinsics inaccurate | Medium | High | Manual calibration option |

---

## Resource Requirements

### Hardware
- iPhone 12 or later (development)
- iPhone 15 Pro (primary test device)
- iPad Pro with M-series (model training)
- Mac with Apple Silicon (development)
- Laser rangefinder (ground truth)
- Tripod and test targets

### Software
- Xcode 15+
- Python 3.10+
- PyTorch 2.0+
- Ultralytics
- coremltools 7.0+
- Weights & Biases

### Services
- Apple Developer Program ($99/year)
- TestFlight (included)
- Firebase (free tier)
- W&B (free tier)

### Budget Estimate

| Category | Item | Cost |
|----------|------|------|
| Hardware | Test devices | $2,000 |
| Hardware | Laser rangefinder | $500 |
| Software | Apple Developer | $99/year |
| Services | Cloud compute (training) | $500 |
| Testing | Range access/targets | $300 |
| **Total** | | **~$3,400** |

---

## Success Metrics

### Technical
- Detection mAP >0.7 on target classes
- Range accuracy ±5% at <200 yards
- Range accuracy ±15% at >500 yards
- Latency <150ms end-to-end
- Battery drain <15%/hour

### User Experience
- App Store rating >4.0 stars
- Crash rate <1%
- Session length >5 minutes average
- Return user rate >30%

### Business
- 10,000 downloads in first month
- 1,000 paying users (if paid)
- Positive reviews from hunting/shooting community

---

## Post-Launch Roadmap

### Version 1.1
- Additional animal species (turkey, antelope, bear)
- Improved low-light performance
- Apple Watch companion app

### Version 1.2
- Ballistic calculator integration
- Wind and elevation compensation
- Export to other apps

### Version 2.0
- Dual-camera stereo ranging (wider baseline)
- AR overlay with target tracking
- Cloud model updates

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-22 | Initial development plan |
