# SniperScope - Passive Optical Rangefinding System

[![iOS](https://img.shields.io/badge/iOS-17.0+-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org/)
[![Python](https://img.shields.io/badge/Python-3.10+-green.svg)](https://python.org/)
[![License](https://img.shields.io/badge/License-Educational-lightgrey.svg)](#license)

A passive rangefinding iOS application that estimates distances up to **1000 yards (914 meters)** using only the iPhone camera - no laser emission required.

> **Read the full technical paper:** [TECHNICAL_PAPER.md](TECHNICAL_PAPER.md)

---

## Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
- [Key Features](#key-features)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [ML Pipeline](#ml-pipeline)
- [Size Databases](#size-databases)
- [Accuracy](#accuracy)
- [Building](#building)
- [Privacy](#privacy)
- [License](#license)

---

## Overview

SniperScope uses computer vision and known object sizes to calculate distances, replicating the techniques used by military snipers for range estimation. The system is:

- **Completely passive** - No laser, infrared, or radio emissions
- **Undetectable** - Cannot be identified by counter-surveillance equipment
- **Smartphone-based** - Uses only the built-in iPhone camera
- **Real-time** - Provides instant distance estimates at 20 FPS

---

## How It Works

### The Pinhole Camera Model

The fundamental principle is the **pinhole camera model**, which describes the geometric relationship between real-world objects and their image projections:

```
                 Real Object
                 Height = H
                    ▲
                    │
                    │ Distance = D
                    │
                    ▼
          ─────────────────────
                    │
                    │ Focal Length = f
                    │
                    ▼
               ════════════
               Image Sensor
               Height = h pixels
```

**By similar triangles:**

```
Distance = (Real_Object_Size × Focal_Length) / Pixel_Size
```

Or mathematically: **D = (H × f) / h**

### Example Calculation

For a person (1.70m tall) detected as 85 pixels in height, with a camera focal length of 2900 pixels:

```
D = (1.70 m × 2900 px) / 85 px
D = 58.0 meters ≈ 63 yards
```

### System Pipeline

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Camera    │───▶│   Object    │───▶│   Size      │───▶│   Distance  │
│   Frame     │    │   Detection │    │   Lookup    │    │   Estimate  │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
       │                  │                  │                  │
       ▼                  ▼                  ▼                  ▼
   Intrinsics        Bounding Box      Known Height       Kalman Filter
   Extraction        + Confidence      from Database       Smoothing
```

1. **Camera captures frame** with known focal length (from intrinsics matrix)
2. **ML model detects objects** (person, vehicle, deer, etc.) with bounding boxes
3. **Database lookup** retrieves real-world size for detected object type
4. **Distance calculated** using pinhole camera formula
5. **Kalman filter** smooths output for stable readings

---

## Key Features

| Feature | Description |
|---------|-------------|
| **Passive Operation** | No laser or active emissions - completely undetectable |
| **Long Range** | Designed for distances up to 1000 yards |
| **13 Object Types** | People, vehicles, wildlife, traffic signs, structures |
| **Real-time Display** | 20 FPS processing with low-latency display |
| **Confidence Indicators** | Shows estimate quality and uncertainty |
| **Multi-object Fusion** | Combines estimates from multiple detected objects |
| **Temporal Smoothing** | Kalman filter reduces jitter and noise |

---

## Architecture

```
SniperScope/
├── App/
│   └── SniperScopeApp.swift          # App entry point and lifecycle
├── Camera/
│   └── CameraManager.swift           # AVFoundation camera with intrinsics
├── Vision/
│   └── VisionPipeline.swift          # CoreML ML inference orchestration
├── Ranging/
│   └── RangingEngine.swift           # Distance calculation + Kalman fusion
├── Database/
│   └── KnownObjectDatabase.swift     # Real-world object size database
└── UI/
    ├── RangefinderView.swift         # Main rangefinder interface
    └── SettingsView.swift            # Settings and calibration UI
```

### Component Responsibilities

| Component | Purpose |
|-----------|---------|
| **CameraManager** | Configures 4K capture, extracts camera intrinsics matrix |
| **VisionPipeline** | Runs YOLOv8 detection, optional depth estimation |
| **RangingEngine** | Applies pinhole model, fuses estimates, Kalman filtering |
| **KnownObjectDatabase** | Stores 30+ object types with dimensions and uncertainties |

---

## Quick Start

### Prerequisites

- macOS with Xcode 15+
- iPhone with iOS 17+ (physical device required)
- Python 3.10+ (for ML training)

### 1. Clone and Open

```bash
git clone https://github.com/nicodemis2-web/SniperScope.git
cd SniperScope
open SniperScope.xcodeproj
```

### 2. Train or Download Model

```bash
cd ml_pipeline

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install torch torchvision ultralytics opencv-python pillow pyyaml tqdm numpy

# Quick training with sample data
python scripts/create_sample_dataset.py --num-images 200
python scripts/train.py --data datasets/sample/dataset.yaml --epochs 10 --batch 8 --device mps
```

### 3. Export to CoreML

```bash
# Requires Python 3.10-3.12 for coremltools compatibility
pip install coremltools
python scripts/convert_to_coreml.py --model sniperscope/detector_v8/weights/best.pt --half
```

### 4. Build and Run

1. Add `SniperScope_Detector_FP16.mlpackage` to Xcode project
2. Set your development team in Signing & Capabilities
3. Connect iPhone and build (Cmd+R)

---

## ML Pipeline

Located in `ml_pipeline/`, the training pipeline includes:

### Scripts

| Script | Purpose |
|--------|---------|
| `create_sample_dataset.py` | Generate synthetic data for testing |
| `download_datasets.sh` | Download VisDrone and vehicle databases |
| `prepare_visdrone.py` | Convert VisDrone to YOLO format |
| `train.py` | Train YOLOv8 with configurable parameters |
| `convert_to_coreml.py` | Export to CoreML for iOS |

### Training Configuration

```yaml
# configs/training_config.yaml
model: yolov8n.pt        # Base model
epochs: 100              # Training epochs
imgsz: 1280              # Image size (high-res for small objects)
batch: 16                # Batch size
device: mps              # Apple Silicon GPU
optimizer: AdamW         # Optimizer
lr0: 0.001               # Initial learning rate
```

### Model Architecture

| Property | Value |
|----------|-------|
| Base Model | YOLOv8-nano |
| Parameters | 3.0M |
| GFLOPs | 8.1 |
| Input Size | 640×640 |
| Classes | 13 |
| Inference Time | ~22ms on iPhone |

---

## Size Databases

JSON databases in `ml_pipeline/data/` contain real-world measurements from authoritative sources:

### Human Measurements (`human_sizes.json`)
- **Source:** ANSUR II (US Army Anthropometric Survey, 2012)
- Standing height: 1.70m ± 0.09m (combined male/female)
- Shoulder height: 1.39m ± 0.08m
- Head height: 0.23m ± 0.01m

### Vehicle Dimensions (`vehicle_sizes.json`)
- **Source:** US Car Models Database, EPA, Manufacturer specs
- Sedan height: 1.45m ± 10%
- SUV height: 1.75m ± 12%
- Pickup truck height: 1.90m ± 12%

### Wildlife (`wildlife_sizes.json`)
- **Source:** USFWS, State Wildlife Agencies
- White-tailed deer (shoulder): 0.95m ± 12%
- Elk (shoulder): 1.40m ± 10%
- Pronghorn (shoulder): 0.87m ± 8%

### Traffic Signs (`structures_signs.json`)
- **Source:** MUTCD (Manual on Uniform Traffic Control Devices)
- Stop sign: 0.762m (30") ± 2%
- Speed limit sign: 0.762m height ± 5%
- Yield sign: 0.914m (36") ± 2%

---

## Accuracy

### Expected Accuracy by Range

| Distance | Accuracy (Best) | Accuracy (Typical) | Accuracy (Poor) |
|----------|-----------------|--------------------|-----------------|
| 0-100 yd | ±2% | ±5% | ±10% |
| 100-300 yd | ±5% | ±8% | ±15% |
| 300-500 yd | ±8% | ±12% | ±20% |
| 500-1000 yd | ±15% | ±20% | ±30% |

### Factors Affecting Accuracy

**Improves accuracy:**
- Full body/object visibility
- High detection confidence (>80%)
- Standardized objects (traffic signs, doors)
- Multiple objects detected (fusion)
- Static scene (Kalman filter effective)

**Degrades accuracy:**
- Partial occlusion
- Unusual poses (crouching, sitting)
- High size variability species (wild boar)
- Small pixel count (<20 pixels)
- Motion blur

### Pixel Size vs Distance

| Distance | Person (1.7m) Pixel Height |
|----------|---------------------------|
| 50 yd | 326 pixels |
| 100 yd | 163 pixels |
| 200 yd | 82 pixels |
| 500 yd | 33 pixels |
| 1000 yd | 16 pixels |

At extreme range, objects become very small, amplifying measurement errors.

---

## Building

### Requirements

| Requirement | Version |
|-------------|---------|
| Xcode | 15.0+ |
| iOS | 17.0+ |
| Swift | 5.9+ |
| Python | 3.10-3.12 (for CoreML export) |

### Build Steps

1. **Open project:** `open SniperScope.xcodeproj`
2. **Set development team:** Project → Signing & Capabilities
3. **Add ML model:** Drag `SniperScope_Detector_FP16.mlpackage` to project
4. **Select device:** Choose connected iPhone (not simulator)
5. **Build:** Cmd+R

**Note:** Physical device required - simulator lacks camera access.

---

## Privacy

- **Camera only** - No location, accelerometer, or network required
- **No data collection** - No images or measurements stored or transmitted
- **No laser emission** - Cannot be detected by counter-surveillance
- **Local processing** - All ML inference runs on-device
- **No accounts** - No sign-in or personal information required

---

## Technical Details

For comprehensive technical documentation, see:

- **[TECHNICAL_PAPER.md](TECHNICAL_PAPER.md)** - Full paper with mathematical foundations
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - System design and component details
- **[ML_TRAINING_PIPELINE.md](ML_TRAINING_PIPELINE.md)** - Training specifications
- **[DATASET_GUIDE.md](DATASET_GUIDE.md)** - Dataset preparation instructions

---

## License

**For personal and educational use only.**

This software is provided as-is for research, learning, and personal projects. Commercial use requires explicit permission.

---

## Acknowledgments

- **ANSUR II** - US Army Research Laboratory
- **VisDrone** - Tianjin University
- **MUTCD** - Federal Highway Administration
- **Ultralytics** - YOLOv8 implementation
- **Apple** - CoreML and Vision frameworks

---

*Built with Swift, Python, and the pinhole camera model*
