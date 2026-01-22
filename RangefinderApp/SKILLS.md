# Technical Skills Required for Passive Rangefinder App

## Project: SniperScope - Passive Rangefinding to 1000 Yards

This document outlines all technical skills, frameworks, and expertise needed to build a passive camera-based rangefinding application for iOS.

---

## 1. iOS Development Skills

### Core Frameworks

| Framework | Purpose | Skill Level |
|-----------|---------|-------------|
| **Swift 5.9+** | Primary development language | Expert |
| **SwiftUI** | Modern declarative UI | Advanced |
| **UIKit** | Legacy components, camera preview | Advanced |
| **Core ML** | On-device ML inference | Expert |
| **Vision** | Object detection, image analysis | Expert |
| **AVFoundation** | Camera access, video capture | Advanced |
| **Metal** | GPU compute, custom shaders | Intermediate |
| **ARKit** | Scene understanding (supplementary) | Intermediate |
| **Combine** | Reactive data flow | Advanced |

### Specific Capabilities Needed

```swift
// Camera intrinsics extraction
AVCaptureConnection.isCameraIntrinsicMatrixDeliveryEnabled
AVCameraCalibrationData.intrinsicMatrix

// Real-time ML inference
VNCoreMLRequest
VNImageRequestHandler
VNSequenceRequestHandler

// Custom model loading
MLModelConfiguration
MLModel.compileModel(at:)

// Metal compute
MTLDevice
MTLCommandQueue
MTLComputePipelineState
```

---

## 2. Machine Learning Skills

### Model Development

| Skill | Application | Tools |
|-------|-------------|-------|
| **PyTorch** | Model training, fine-tuning | PyTorch 2.0+ |
| **TensorFlow** | Alternative training, TFLite | TF 2.x |
| **coremltools** | Model conversion to Core ML | coremltools 7.0+ |
| **ONNX** | Model interchange format | onnx, onnxruntime |
| **Ultralytics** | YOLO training and export | ultralytics package |

### Model Architectures to Master

**Object Detection:**
- YOLO family (v8, v11, YOLO-NAS)
- QueryDet (small object specialist)
- EfficientDet-Lite (mobile optimized)
- RT-DETR (transformer-based)

**Depth Estimation:**
- Depth Anything V2 (primary)
- MiDaS v3.1 (fallback)
- Metric3D (metric depth)
- ZoeDepth (multi-dataset)

**Model Optimization:**
- Quantization (INT8, FP16)
- Pruning (structured/unstructured)
- Knowledge distillation
- Neural Architecture Search concepts

### Training Pipeline

```python
# Key libraries
import torch
import torchvision
from ultralytics import YOLO
import coremltools as ct
from torch.utils.data import DataLoader

# Training workflow
1. Dataset preparation (COCO format)
2. Model selection and configuration
3. Transfer learning setup
4. Training with appropriate loss functions
5. Validation and hyperparameter tuning
6. Export to ONNX → Core ML
7. Quantization and optimization
8. On-device testing
```

---

## 3. Computer Vision Skills

### Fundamental Concepts

| Concept | Application |
|---------|-------------|
| **Pinhole Camera Model** | Distance calculation from known object size |
| **Camera Calibration** | Intrinsic/extrinsic parameter extraction |
| **Lens Distortion** | Radial/tangential correction |
| **Stereo Vision** | Optional dual-camera ranging |
| **Feature Detection** | Object tracking, matching |
| **Image Preprocessing** | Normalization, augmentation |

### Mathematical Foundations

**Distance from Known Object Size:**
```
Distance = (Object_Real_Size × Focal_Length) / Object_Pixel_Size

Where:
- Object_Real_Size: Known dimension (e.g., human height = 1.75m)
- Focal_Length: From camera intrinsics (pixels)
- Object_Pixel_Size: Detected bounding box dimension (pixels)
```

**Uncertainty Propagation:**
```
σ_d/d = sqrt((σ_H/H)² + (σ_f/f)² + (σ_h/h)²)

Where:
- σ_H: Object size uncertainty (~10% for humans)
- σ_f: Focal length uncertainty (~1-2%)
- σ_h: Detection bounding box uncertainty (~2-5 pixels)
```

**Atmospheric Scattering Model:**
```
I(x) = J(x)·t(x) + A·(1 - t(x))
t(x) = exp(-β·d(x))

Where:
- I(x): Observed image
- J(x): Clear scene radiance
- t(x): Transmission map
- A: Atmospheric light
- β: Scattering coefficient
- d(x): Scene depth
```

---

## 4. Data Engineering Skills

### Dataset Management

| Skill | Tools |
|-------|-------|
| **Dataset Preparation** | Roboflow, CVAT, LabelImg |
| **Format Conversion** | COCO, YOLO, Pascal VOC |
| **Data Augmentation** | Albumentations, imgaug |
| **Dataset Version Control** | DVC, Roboflow |
| **Large Dataset Handling** | WebDataset, tfrecords |

### Key Datasets to Work With

**Object Detection:**
- VisDrone (261K frames, small objects)
- COCO (common objects)
- TinyPerson (extreme small person detection)
- Custom hunting/outdoor dataset

**Depth Estimation:**
- DDAD (250m range, dense LiDAR)
- Argoverse 2 (225m annotations)
- KITTI (80m, benchmark standard)
- NYU Depth V2 (indoor baseline)

**Size References:**
- CAESAR/ANSUR (human anthropometrics)
- Vehicle dimension databases
- Wildlife size databases

---

## 5. Signal Processing & Sensor Fusion

### Kalman Filtering

```python
# Fuse multiple distance estimates
class DistanceFusion:
    def __init__(self):
        self.kf = KalmanFilter(dim_x=2, dim_z=1)  # state: [distance, velocity]

    def update(self, measurements, confidences):
        # Weighted fusion of:
        # - Size-based ranging
        # - Monocular depth estimation
        # - Atmospheric analysis
        # - Temporal consistency
        pass
```

### Confidence Estimation

- Detection confidence from object detector
- Visibility/occlusion scoring
- Atmospheric condition assessment
- Temporal consistency metrics

---

## 6. Performance Optimization

### iOS-Specific Optimization

| Technique | Impact | Tools |
|-----------|--------|-------|
| **Neural Engine targeting** | 10-100x faster than CPU | MLModelConfiguration |
| **FP16 inference** | 2x faster, minimal accuracy loss | coremltools |
| **Model caching** | Faster startup | MLModel compilation |
| **Batch processing** | Higher throughput | Vision framework |
| **Memory management** | Prevent crashes | Instruments |

### Profiling Tools

- Xcode Instruments (Time Profiler, Allocations, Energy)
- Core ML Performance Report
- Metal System Trace
- Custom timing instrumentation

---

## 7. UI/UX Design Skills

### Rangefinder-Specific UI

- Crosshair/reticle overlay
- Distance readout with units
- Confidence indicator
- Target lock feedback
- Quick calibration workflow
- Settings for object types

### Accessibility

- VoiceOver support for distance readout
- High contrast modes
- Haptic feedback for target lock

---

## 8. Testing & Validation

### Testing Methodology

| Test Type | Purpose |
|-----------|---------|
| **Unit Tests** | Algorithm verification |
| **Integration Tests** | Pipeline validation |
| **Field Testing** | Real-world accuracy |
| **A/B Testing** | Model comparison |
| **Regression Testing** | Prevent accuracy degradation |

### Accuracy Validation

- Ground truth from laser rangefinder
- Known distance markers
- Statistical analysis (MAE, RMSE, percentile errors)
- Environmental condition logging

---

## 9. DevOps & MLOps

### Development Pipeline

```
Git → CI/CD → Model Training → Validation → Core ML Export → TestFlight → App Store
```

### Tools

| Tool | Purpose |
|------|---------|
| **GitHub Actions** | CI/CD |
| **Weights & Biases** | Experiment tracking |
| **MLflow** | Model registry |
| **TestFlight** | Beta distribution |
| **Firebase** | Analytics, crash reporting |

---

## 10. Domain Knowledge

### Ballistics & Ranging

- Mil-dot/MOA calculations
- Angle compensation (uphill/downhill)
- Environmental factors (wind, altitude, temperature)
- Common target sizes (humans, vehicles, wildlife)

### Hunting/Shooting Sports

- User expectations and workflows
- Competition with laser rangefinders
- Legal/ethical considerations
- Weather and lighting conditions

### Photography/Optics

- Lens characteristics
- Depth of field
- Atmospheric effects on imaging
- Sensor technology

---

## Team Composition Recommendation

| Role | Count | Key Skills |
|------|-------|------------|
| **iOS Lead Developer** | 1 | Swift, Core ML, AVFoundation |
| **ML Engineer** | 1-2 | PyTorch, computer vision, model optimization |
| **Computer Vision Specialist** | 1 | Depth estimation, camera geometry |
| **UI/UX Designer** | 1 | Mobile design, AR interfaces |
| **QA Engineer** | 1 | Field testing, accuracy validation |
| **Data Engineer** | 0.5 | Dataset preparation, pipeline |

### Solo Developer Path

If building alone, prioritize:
1. iOS + Core ML integration (primary)
2. Model fine-tuning with Ultralytics (efficient)
3. Use pre-trained models where possible
4. Leverage Roboflow for dataset management
5. Iterative field testing

---

## Learning Resources

### iOS/Core ML
- [Apple Core ML Documentation](https://developer.apple.com/documentation/coreml)
- [WWDC Core ML Sessions](https://developer.apple.com/videos/frameworks/machine-learning)
- [Hollance Neural Engine Guide](https://github.com/hollance/neural-engine)

### Object Detection
- [Ultralytics Documentation](https://docs.ultralytics.com/)
- [Roboflow Blog](https://blog.roboflow.com/)
- [Papers With Code - Object Detection](https://paperswithcode.com/task/object-detection)

### Depth Estimation
- [Depth Anything V2 GitHub](https://github.com/DepthAnything/Depth-Anything-V2)
- [MiDaS GitHub](https://github.com/isl-org/MiDaS)
- [Monocular Depth Estimation Survey](https://arxiv.org/abs/2003.06620)

### Computer Vision Math
- [Multiple View Geometry in Computer Vision](http://www.robots.ox.ac.uk/~vgg/hzbook/)
- [OpenCV Camera Calibration Tutorial](https://docs.opencv.org/4.x/dc/dbb/tutorial_py_calibration.html)

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-22 | Initial skills assessment |
