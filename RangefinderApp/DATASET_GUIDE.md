# Dataset Preparation Guide

## Overview

This guide details all datasets needed for training SniperScope, including download instructions, preparation steps, and integration into the training pipeline.

---

## Dataset Summary

| Dataset | Purpose | Size | Distance Coverage | Download |
|---------|---------|------|-------------------|----------|
| VisDrone | Small object detection | 261K frames | N/A (altitude-based) | Public |
| DDAD | Long-range depth | 19K frames | 0-250m | Public |
| Custom Field | Ranging ground truth | 2K+ images | 50-1000 yards | Self-collected |
| CAESAR | Human sizes | 4K subjects | N/A (anthropometry) | Licensed |
| Vehicle DB | Vehicle dimensions | 15K+ entries | N/A (measurements) | Public |
| Wildlife DB | Animal sizes | 500+ species | N/A (measurements) | Compiled |

---

## 1. VisDrone Dataset

### Description
Drone-captured imagery with extensive small object annotations. Excellent for training detection of small/distant objects.

### Download

```bash
# Create directory
mkdir -p datasets/visdrone_raw
cd datasets/visdrone_raw

# Download training set
wget https://github.com/VisDrone/VisDrone-Dataset/releases/download/v1.0/VisDrone2019-DET-train.zip
unzip VisDrone2019-DET-train.zip

# Download validation set
wget https://github.com/VisDrone/VisDrone-Dataset/releases/download/v1.0/VisDrone2019-DET-val.zip
unzip VisDrone2019-DET-val.zip

# Download test-dev set (optional)
wget https://github.com/VisDrone/VisDrone-Dataset/releases/download/v1.0/VisDrone2019-DET-test-dev.zip
unzip VisDrone2019-DET-test-dev.zip
```

### Directory Structure
```
visdrone_raw/
├── VisDrone2019-DET-train/
│   ├── images/           # 6,471 images
│   └── annotations/      # Bounding box annotations
├── VisDrone2019-DET-val/
│   ├── images/           # 548 images
│   └── annotations/
└── VisDrone2019-DET-test-dev/
    ├── images/           # 1,610 images
    └── annotations/
```

### Annotation Format (VisDrone Native)
```
<bbox_left>,<bbox_top>,<bbox_width>,<bbox_height>,<score>,<object_category>,<truncation>,<occlusion>

Categories:
0: ignored regions
1: pedestrian
2: people
3: bicycle
4: car
5: van
6: truck
7: tricycle
8: awning-tricycle
9: bus
10: motor
11: others
```

### Class Mapping for SniperScope
```python
VISDRONE_TO_SNIPERSCOPE = {
    1: 0,   # pedestrian → person
    2: 0,   # people → person
    4: 2,   # car → car
    5: 3,   # van → truck
    6: 3,   # truck → truck
}
```

### Statistics
- Total images: 8,629 (train + val)
- Total annotations: ~2.6 million bounding boxes
- Average objects per image: ~54
- Small objects (<32×32 px): ~60%

---

## 2. DDAD (Dense Depth for Autonomous Driving)

### Description
Long-range depth dataset from Toyota Research Institute with LiDAR ground truth up to 250 meters.

### Download

```bash
# Requires AWS CLI
pip install awscli

# Create directory
mkdir -p datasets/ddad
cd datasets/ddad

# Download (requires accepting license at https://github.com/TRI-ML/DDAD)
aws s3 sync s3://tri-ml-public/datasets/DDAD/ddad/ . --no-sign-request
```

### Alternative: Use Hugging Face
```python
from huggingface_hub import hf_hub_download

# Download sample
hf_hub_download(repo_id="tri-ml/ddad", filename="ddad_sample.zip", repo_type="dataset")
```

### Directory Structure
```
ddad/
├── ddad_train_val/
│   ├── 000000/          # Scene directories
│   │   ├── calibration/
│   │   ├── depth/       # Dense depth maps
│   │   ├── lidar/       # Raw LiDAR points
│   │   └── rgb/         # Camera images
│   ├── 000001/
│   └── ...
└── ddad_test/
```

### Depth Map Format
- Format: 16-bit PNG
- Value encoding: `depth_meters = pixel_value / 256.0`
- Maximum depth: 250 meters
- Resolution: 1936 × 1216

### Usage for Depth Scale Calibration
```python
import cv2
import numpy as np

def load_ddad_depth(depth_path):
    """Load DDAD depth map."""
    depth_raw = cv2.imread(depth_path, cv2.IMREAD_UNCHANGED)
    depth_meters = depth_raw.astype(np.float32) / 256.0
    return depth_meters

# Statistics
# - Range: 0-250m
# - Precision: <1cm
# - Valid pixels: ~80% of image
```

---

## 3. Custom Field Dataset

### Collection Protocol

#### Equipment Required
- iPhone 12 or later (primary capture device)
- Laser rangefinder (Leupold RX-2800 or equivalent)
- Tripod with phone mount
- Target silhouettes/decoys:
  - Human silhouette (IPSC target)
  - Deer decoy (full-size)
  - Vehicle (when available)
- Distance markers or measuring tape (for close ranges)
- GPS device or phone GPS

#### Distance Points
| Distance (yards) | Distance (meters) | Priority |
|-----------------|-------------------|----------|
| 50 | 45.7 | Medium |
| 100 | 91.4 | High |
| 150 | 137.2 | Medium |
| 200 | 182.9 | High |
| 300 | 274.3 | High |
| 400 | 365.8 | High |
| 500 | 457.2 | High |
| 600 | 548.6 | High |
| 800 | 731.5 | Medium |
| 1000 | 914.4 | Medium |

#### Images Per Distance Point
- Minimum: 20 images
- Target: 50 images
- Variations:
  - 5× different angles (0°, ±5°, ±10°)
  - 3× zoom levels (1x, 2x, 3x)
  - 3× different times of day
  - Multiple weather conditions

#### Capture Checklist
```markdown
## Field Capture Checklist

### Pre-Session
- [ ] Charge all devices
- [ ] Clear camera storage
- [ ] Calibrate laser rangefinder
- [ ] Check weather forecast
- [ ] Prepare targets

### Per Distance Point
- [ ] Set up target at measured distance
- [ ] Verify with laser (record: ___ yards)
- [ ] Record GPS coordinates
- [ ] Note weather conditions
- [ ] Note lighting conditions
- [ ] Capture 20+ images
- [ ] Review images for quality

### Post-Session
- [ ] Transfer images to computer
- [ ] Create metadata JSON
- [ ] Backup raw images
- [ ] Annotate with LabelImg
```

#### Naming Convention
```
{target_type}_{distance}yd_{sequence:03d}_{condition}.jpg

Examples:
person_500yd_001_sunny.jpg
deer_300yd_012_overcast.jpg
car_200yd_005_dawn.jpg
```

#### Metadata JSON Format
```json
{
  "capture_session": "2026-01-22_morning",
  "location": {
    "name": "Shooting Range XYZ",
    "gps": [40.7128, -74.0060]
  },
  "weather": {
    "condition": "clear",
    "temperature_f": 65,
    "humidity_pct": 45,
    "wind_mph": 5
  },
  "images": [
    {
      "filename": "person_500yd_001_sunny.jpg",
      "target_type": "person",
      "distance_yards": 500,
      "distance_meters": 457.2,
      "laser_reading_yards": 498,
      "timestamp": "2026-01-22T09:15:32",
      "lighting": "direct_sun",
      "zoom": "1x",
      "notes": ""
    }
  ]
}
```

### Annotation with LabelImg

#### Installation
```bash
pip install labelImg
```

#### Usage
```bash
labelImg datasets/custom/images datasets/custom/classes.txt
```

#### Classes File (classes.txt)
```
person
person_head
car
truck
suv
deer
elk
wild_boar
coyote
door
window
stop_sign
speed_limit_sign
```

#### Annotation Guidelines
1. Draw tight bounding box around visible portion
2. Include partial occlusions (mark in notes)
3. For groups, annotate each individual
4. Save in YOLO format

---

## 4. Human Anthropometric Data

### CAESAR Database (Licensed)

#### Access
- Institution license required
- Contact: SAE International
- URL: https://www.sae.org/standardsdev/tsb/cooperative/caesar.htm

#### Alternative: ANSUR II (Free)

```bash
# Download ANSUR II data
mkdir -p datasets/anthropometry
cd datasets/anthropometry

# From: https://www.openlab.psu.edu/ansur2/
wget https://www.openlab.psu.edu/files/ANSUR2_Data.zip
unzip ANSUR2_Data.zip
```

#### Key Measurements for Ranging

```python
# human_sizes.json

{
  "adult_male": {
    "standing_height_m": {
      "mean": 1.756,
      "std": 0.070,
      "p5": 1.640,
      "p95": 1.872
    },
    "shoulder_breadth_m": {
      "mean": 0.465,
      "std": 0.025,
      "p5": 0.423,
      "p95": 0.507
    },
    "head_height_m": {
      "mean": 0.238,
      "std": 0.012,
      "p5": 0.218,
      "p95": 0.258
    },
    "head_breadth_m": {
      "mean": 0.156,
      "std": 0.008,
      "p5": 0.143,
      "p95": 0.169
    }
  },
  "adult_female": {
    "standing_height_m": {
      "mean": 1.622,
      "std": 0.063,
      "p5": 1.516,
      "p95": 1.728
    },
    "shoulder_breadth_m": {
      "mean": 0.421,
      "std": 0.023,
      "p5": 0.383,
      "p95": 0.459
    },
    "head_height_m": {
      "mean": 0.224,
      "std": 0.011,
      "p5": 0.206,
      "p95": 0.242
    }
  },
  "combined_average": {
    "standing_height_m": 1.70,
    "shoulder_breadth_m": 0.45,
    "head_height_m": 0.23
  }
}
```

---

## 5. Vehicle Dimensions Database

### Download from GitHub

```bash
# US Car Models Data (free)
mkdir -p datasets/vehicles
cd datasets/vehicles

git clone https://github.com/abhionlyone/us-car-models-data.git
```

### Data Format
```json
{
  "make": "Toyota",
  "model": "Camry",
  "year": 2024,
  "body_style": "Sedan",
  "length_mm": 4885,
  "width_mm": 1840,
  "height_mm": 1445,
  "wheelbase_mm": 2825,
  "weight_kg": 1575
}
```

### Processing Script

```python
# scripts/process_vehicle_data.py

import json
import pandas as pd
from pathlib import Path

def create_vehicle_size_database(input_dir: Path, output_file: Path):
    """Process vehicle data into ranging-ready format."""

    # Load data
    df = pd.read_csv(input_dir / 'us-car-models-data/us_car_models.csv')

    # Aggregate by body style
    size_by_style = {}

    for style in df['body_style'].unique():
        style_df = df[df['body_style'] == style]

        # Convert to meters
        size_by_style[style.lower()] = {
            "height_m": {
                "mean": style_df['height_mm'].mean() / 1000,
                "std": style_df['height_mm'].std() / 1000,
                "min": style_df['height_mm'].min() / 1000,
                "max": style_df['height_mm'].max() / 1000,
            },
            "width_m": {
                "mean": style_df['width_mm'].mean() / 1000,
                "std": style_df['width_mm'].std() / 1000,
            },
            "length_m": {
                "mean": style_df['length_mm'].mean() / 1000,
                "std": style_df['length_mm'].std() / 1000,
            },
            "count": len(style_df)
        }

    # Create simplified database for app
    app_database = {
        "car": {
            "label": "Sedan/Compact",
            "height_m": 1.45,
            "height_variability": 0.08,
            "reliability_weight": 0.85
        },
        "suv": {
            "label": "SUV/Crossover",
            "height_m": 1.75,
            "height_variability": 0.12,
            "reliability_weight": 0.80
        },
        "truck": {
            "label": "Pickup/Van",
            "height_m": 1.90,
            "height_variability": 0.15,
            "reliability_weight": 0.75
        }
    }

    with open(output_file, 'w') as f:
        json.dump({
            "detailed": size_by_style,
            "simplified": app_database
        }, f, indent=2)

    print(f"Vehicle database saved to {output_file}")
```

---

## 6. Wildlife Size Database

### Compiled from Multiple Sources

```python
# wildlife_sizes.json

{
  "deer": {
    "species": "White-tailed Deer",
    "scientific_name": "Odocoileus virginianus",
    "shoulder_height_m": {
      "male": {"mean": 1.0, "range": [0.9, 1.1]},
      "female": {"mean": 0.85, "range": [0.75, 0.95]}
    },
    "body_length_m": {
      "male": {"mean": 1.8, "range": [1.6, 2.1]},
      "female": {"mean": 1.5, "range": [1.4, 1.7]}
    },
    "default_height_m": 0.95,
    "size_variability": 0.12,
    "reliability_weight": 0.85,
    "source": "USFWS Wildlife Guide"
  },
  "elk": {
    "species": "Rocky Mountain Elk",
    "scientific_name": "Cervus canadensis",
    "shoulder_height_m": {
      "male": {"mean": 1.5, "range": [1.4, 1.6]},
      "female": {"mean": 1.3, "range": [1.2, 1.4]}
    },
    "default_height_m": 1.4,
    "size_variability": 0.10,
    "reliability_weight": 0.88,
    "source": "Rocky Mountain Elk Foundation"
  },
  "wild_boar": {
    "species": "Wild Boar / Feral Hog",
    "scientific_name": "Sus scrofa",
    "shoulder_height_m": {
      "adult": {"mean": 0.75, "range": [0.55, 1.0]}
    },
    "default_height_m": 0.75,
    "size_variability": 0.25,
    "reliability_weight": 0.65,
    "source": "Texas Parks & Wildlife"
  },
  "coyote": {
    "species": "Coyote",
    "scientific_name": "Canis latrans",
    "shoulder_height_m": {
      "adult": {"mean": 0.58, "range": [0.50, 0.66]}
    },
    "default_height_m": 0.58,
    "size_variability": 0.12,
    "reliability_weight": 0.70,
    "source": "National Park Service"
  },
  "black_bear": {
    "species": "American Black Bear",
    "scientific_name": "Ursus americanus",
    "shoulder_height_m": {
      "adult": {"mean": 0.90, "range": [0.70, 1.05]}
    },
    "default_height_m": 0.90,
    "size_variability": 0.18,
    "reliability_weight": 0.70,
    "source": "North American Bear Center"
  },
  "turkey": {
    "species": "Wild Turkey",
    "scientific_name": "Meleagris gallopavo",
    "standing_height_m": {
      "male": {"mean": 1.0, "range": [0.9, 1.2]},
      "female": {"mean": 0.75, "range": [0.65, 0.85]}
    },
    "default_height_m": 0.90,
    "size_variability": 0.20,
    "reliability_weight": 0.60,
    "source": "National Wild Turkey Federation"
  },
  "antelope": {
    "species": "Pronghorn Antelope",
    "scientific_name": "Antilocapra americana",
    "shoulder_height_m": {
      "adult": {"mean": 0.87, "range": [0.80, 0.95]}
    },
    "default_height_m": 0.87,
    "size_variability": 0.08,
    "reliability_weight": 0.85,
    "source": "Wyoming Game & Fish"
  }
}
```

---

## 7. Standard Object Sizes

### Signs and Street Furniture

```python
# standard_objects.json

{
  "signs": {
    "stop_sign": {
      "type": "MUTCD R1-1",
      "shape": "octagon",
      "width_m": 0.762,
      "height_m": 0.762,
      "variability": 0.02,
      "reliability_weight": 0.98,
      "notes": "US standard 30 inches"
    },
    "speed_limit_sign": {
      "type": "MUTCD R2-1",
      "shape": "rectangle",
      "width_m": 0.610,
      "height_m": 0.762,
      "variability": 0.05,
      "reliability_weight": 0.95,
      "notes": "US standard 24x30 inches"
    },
    "yield_sign": {
      "type": "MUTCD R1-2",
      "shape": "triangle",
      "width_m": 0.914,
      "height_m": 0.914,
      "variability": 0.02,
      "reliability_weight": 0.95
    }
  },
  "structures": {
    "standard_door": {
      "type": "residential",
      "width_m": 0.914,
      "height_m": 2.032,
      "variability": 0.03,
      "reliability_weight": 0.95,
      "notes": "US standard 36x80 inches"
    },
    "commercial_door": {
      "type": "commercial",
      "width_m": 0.914,
      "height_m": 2.134,
      "variability": 0.05,
      "reliability_weight": 0.90
    },
    "garage_door_single": {
      "width_m": 2.438,
      "height_m": 2.134,
      "variability": 0.10,
      "reliability_weight": 0.80
    },
    "standard_window": {
      "type": "double_hung",
      "width_m": 0.914,
      "height_m": 1.219,
      "variability": 0.20,
      "reliability_weight": 0.65
    }
  },
  "utilities": {
    "fire_hydrant": {
      "height_m": 0.76,
      "variability": 0.10,
      "reliability_weight": 0.80
    },
    "parking_meter": {
      "height_m": 1.22,
      "variability": 0.15,
      "reliability_weight": 0.70
    },
    "mailbox_standard": {
      "height_m": 1.07,
      "variability": 0.10,
      "reliability_weight": 0.75
    }
  }
}
```

---

## 8. Dataset Integration Script

### Final Merge and Validation

```python
# scripts/prepare_final_dataset.py

import os
import json
import shutil
from pathlib import Path
from collections import defaultdict
import random

def prepare_final_dataset(
    visdrone_path: Path,
    custom_path: Path,
    output_path: Path,
    train_split: float = 0.8,
    val_split: float = 0.15,
    test_split: float = 0.05
):
    """Prepare final merged and split dataset."""

    assert abs(train_split + val_split + test_split - 1.0) < 0.001

    # Create output directories
    for split in ['train', 'val', 'test']:
        (output_path / 'images' / split).mkdir(parents=True, exist_ok=True)
        (output_path / 'labels' / split).mkdir(parents=True, exist_ok=True)

    # Collect all images and labels
    all_samples = []

    # Add VisDrone samples (with subsampling)
    visdrone_samples = list((visdrone_path / 'images' / 'train').glob('*.jpg'))
    visdrone_samples += list((visdrone_path / 'images' / 'val').glob('*.jpg'))
    visdrone_samples = random.sample(visdrone_samples, min(len(visdrone_samples), 5000))

    for img_path in visdrone_samples:
        label_path = visdrone_path / 'labels' / img_path.parent.name / f'{img_path.stem}.txt'
        if label_path.exists():
            all_samples.append(('visdrone', img_path, label_path))

    # Add all custom samples (prioritized)
    for split in ['train', 'val', 'test']:
        split_path = custom_path / 'images' / split
        if split_path.exists():
            for img_path in split_path.glob('*.jpg'):
                label_path = custom_path / 'labels' / split / f'{img_path.stem}.txt'
                if label_path.exists():
                    all_samples.append(('custom', img_path, label_path))

    # Shuffle
    random.shuffle(all_samples)

    # Split
    n_total = len(all_samples)
    n_train = int(n_total * train_split)
    n_val = int(n_total * val_split)

    train_samples = all_samples[:n_train]
    val_samples = all_samples[n_train:n_train + n_val]
    test_samples = all_samples[n_train + n_val:]

    # Copy files
    def copy_samples(samples, split):
        for source, img_path, label_path in samples:
            new_name = f'{source}_{img_path.name}'
            shutil.copy(img_path, output_path / 'images' / split / new_name)
            shutil.copy(label_path, output_path / 'labels' / split / f'{source}_{img_path.stem}.txt')

    copy_samples(train_samples, 'train')
    copy_samples(val_samples, 'val')
    copy_samples(test_samples, 'test')

    # Generate dataset config
    config = {
        'path': str(output_path),
        'train': 'images/train',
        'val': 'images/val',
        'test': 'images/test',
        'names': {
            0: 'person',
            1: 'person_head',
            2: 'car',
            3: 'truck',
            4: 'suv',
            5: 'deer',
            6: 'elk',
            7: 'wild_boar',
            8: 'coyote',
            9: 'door',
            10: 'window',
            11: 'stop_sign',
            12: 'speed_limit_sign'
        },
        'nc': 13
    }

    import yaml
    with open(output_path / 'dataset.yaml', 'w') as f:
        yaml.dump(config, f, default_flow_style=False)

    # Print statistics
    print(f"\nDataset Statistics:")
    print(f"  Train: {len(train_samples)} samples")
    print(f"  Val: {len(val_samples)} samples")
    print(f"  Test: {len(test_samples)} samples")
    print(f"  Total: {n_total} samples")

    # Class distribution
    class_counts = defaultdict(int)
    for _, _, label_path in all_samples:
        with open(label_path, 'r') as f:
            for line in f:
                class_id = int(line.strip().split()[0])
                class_counts[class_id] += 1

    print(f"\nClass Distribution:")
    for class_id, count in sorted(class_counts.items()):
        class_name = config['names'].get(class_id, 'unknown')
        print(f"  {class_name}: {count}")

def validate_dataset(dataset_path: Path):
    """Validate dataset integrity."""

    errors = []

    for split in ['train', 'val', 'test']:
        images_dir = dataset_path / 'images' / split
        labels_dir = dataset_path / 'labels' / split

        for img_path in images_dir.glob('*.jpg'):
            label_path = labels_dir / f'{img_path.stem}.txt'

            # Check label exists
            if not label_path.exists():
                errors.append(f"Missing label: {label_path}")
                continue

            # Validate label format
            with open(label_path, 'r') as f:
                for i, line in enumerate(f):
                    parts = line.strip().split()
                    if len(parts) != 5:
                        errors.append(f"Invalid format in {label_path}:{i+1}")
                        continue

                    try:
                        class_id = int(parts[0])
                        coords = [float(x) for x in parts[1:]]

                        if class_id < 0 or class_id > 12:
                            errors.append(f"Invalid class {class_id} in {label_path}:{i+1}")

                        for coord in coords:
                            if coord < 0 or coord > 1:
                                errors.append(f"Invalid coord {coord} in {label_path}:{i+1}")

                    except ValueError as e:
                        errors.append(f"Parse error in {label_path}:{i+1}: {e}")

    if errors:
        print(f"\nValidation Errors ({len(errors)}):")
        for error in errors[:20]:
            print(f"  - {error}")
        if len(errors) > 20:
            print(f"  ... and {len(errors) - 20} more")
    else:
        print("\nDataset validation passed!")

    return len(errors) == 0

if __name__ == '__main__':
    output = Path('datasets/final')

    prepare_final_dataset(
        Path('datasets/visdrone'),
        Path('datasets/custom'),
        output
    )

    validate_dataset(output)
```

---

## 9. Quick Start Checklist

```markdown
## Dataset Preparation Checklist

### Downloads
- [ ] VisDrone2019-DET-train.zip
- [ ] VisDrone2019-DET-val.zip
- [ ] DDAD dataset (optional for depth calibration)
- [ ] Vehicle dimensions database

### Processing
- [ ] Convert VisDrone to YOLO format
- [ ] Collect custom field images (minimum 500)
- [ ] Annotate custom images with LabelImg
- [ ] Create metadata JSON with distances
- [ ] Merge datasets
- [ ] Apply augmentations
- [ ] Validate final dataset

### Size Databases
- [ ] Create human_sizes.json
- [ ] Create vehicle_sizes.json
- [ ] Create wildlife_sizes.json
- [ ] Create standard_objects.json

### Final Verification
- [ ] Class distribution balanced
- [ ] Small objects adequately represented
- [ ] Distance metadata complete
- [ ] Annotation quality verified
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-22 | Initial dataset guide |
