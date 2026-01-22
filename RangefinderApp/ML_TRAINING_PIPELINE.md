# ML Training Pipeline Specification

## Overview

This document specifies the complete machine learning pipeline for training the SniperScope object detection and depth estimation models.

---

## Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ML Training Pipeline                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌───────────┐    ┌───────────┐    ┌───────────┐    ┌───────────┐          │
│  │  Dataset  │───▶│  Training │───▶│ Evaluation│───▶│  Export   │          │
│  │Preparation│    │           │    │           │    │  CoreML   │          │
│  └───────────┘    └───────────┘    └───────────┘    └───────────┘          │
│       │                │                │                │                   │
│       ▼                ▼                ▼                ▼                   │
│  ┌───────────┐    ┌───────────┐    ┌───────────┐    ┌───────────┐          │
│  │VisDrone   │    │ YOLO11    │    │ mAP, AR   │    │ FP16/INT8 │          │
│  │Custom Data│    │ PyTorch   │    │ Confusion │    │ Benchmark │          │
│  │Augment    │    │ W&B Track │    │ Matrix    │    │ On-Device │          │
│  └───────────┘    └───────────┘    └───────────┘    └───────────┘          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 1. Environment Setup

### Python Environment

```bash
# Create conda environment
conda create -n sniperscope python=3.10 -y
conda activate sniperscope

# Install PyTorch with CUDA (adjust for your GPU)
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118

# Install Ultralytics YOLO
pip install ultralytics

# Install coremltools for Apple conversion
pip install coremltools

# Install additional dependencies
pip install \
    opencv-python \
    albumentations \
    wandb \
    roboflow \
    supervision \
    numpy \
    pandas \
    matplotlib \
    scikit-learn \
    onnx \
    onnxruntime

# Verify installation
python -c "import torch; print(f'PyTorch: {torch.__version__}')"
python -c "from ultralytics import YOLO; print('Ultralytics installed')"
python -c "import coremltools; print(f'coremltools: {coremltools.__version__}')"
```

### Directory Structure

```
ml_pipeline/
├── configs/
│   ├── sniperscope.yaml          # Dataset config
│   ├── training_config.yaml       # Training hyperparams
│   └── augmentation_config.yaml   # Augmentation settings
├── datasets/
│   ├── visdrone/
│   ├── custom/
│   └── merged/
├── scripts/
│   ├── prepare_visdrone.py
│   ├── prepare_custom.py
│   ├── merge_datasets.py
│   ├── train.py
│   ├── evaluate.py
│   ├── export_coreml.py
│   └── benchmark.py
├── models/
│   ├── checkpoints/
│   ├── exports/
│   └── final/
├── experiments/
│   └── [experiment_name]/
└── requirements.txt
```

---

## 2. Dataset Preparation

### 2.1 VisDrone Dataset Processing

```python
# scripts/prepare_visdrone.py

import os
import shutil
from pathlib import Path
from tqdm import tqdm

# VisDrone to YOLO class mapping for SniperScope
VISDRONE_TO_SNIPERSCOPE = {
    0: None,   # ignored regions
    1: 0,      # pedestrian → person
    2: 0,      # people → person
    3: None,   # bicycle (skip)
    4: 2,      # car → car
    5: 3,      # van → truck
    6: 3,      # truck → truck
    7: None,   # tricycle (skip)
    8: None,   # awning-tricycle (skip)
    9: None,   # bus (skip for now)
    10: None,  # motor (skip)
}

def convert_visdrone_annotation(visdrone_line: str, img_width: int, img_height: int) -> str:
    """Convert VisDrone annotation to YOLO format."""
    parts = visdrone_line.strip().split(',')

    # VisDrone format: x,y,w,h,score,class,truncation,occlusion
    x, y, w, h = int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3])
    visdrone_class = int(parts[5])

    # Skip if not in our mapping or mapped to None
    if visdrone_class not in VISDRONE_TO_SNIPERSCOPE:
        return None
    sniperscope_class = VISDRONE_TO_SNIPERSCOPE[visdrone_class]
    if sniperscope_class is None:
        return None

    # Convert to YOLO format (normalized center x, center y, width, height)
    cx = (x + w / 2) / img_width
    cy = (y + h / 2) / img_height
    nw = w / img_width
    nh = h / img_height

    return f"{sniperscope_class} {cx:.6f} {cy:.6f} {nw:.6f} {nh:.6f}"

def process_visdrone_dataset(
    visdrone_root: Path,
    output_root: Path,
    split: str = 'train'
):
    """Process VisDrone dataset into YOLO format."""

    images_dir = visdrone_root / f'VisDrone2019-DET-{split}' / 'images'
    annotations_dir = visdrone_root / f'VisDrone2019-DET-{split}' / 'annotations'

    output_images = output_root / 'images' / split
    output_labels = output_root / 'labels' / split

    output_images.mkdir(parents=True, exist_ok=True)
    output_labels.mkdir(parents=True, exist_ok=True)

    image_files = list(images_dir.glob('*.jpg'))

    for img_path in tqdm(image_files, desc=f'Processing {split}'):
        # Get image dimensions
        import cv2
        img = cv2.imread(str(img_path))
        h, w = img.shape[:2]

        # Process annotation
        ann_path = annotations_dir / f'{img_path.stem}.txt'
        if ann_path.exists():
            yolo_lines = []
            with open(ann_path, 'r') as f:
                for line in f:
                    yolo_line = convert_visdrone_annotation(line, w, h)
                    if yolo_line:
                        yolo_lines.append(yolo_line)

            # Only save if we have valid annotations
            if yolo_lines:
                # Copy image
                shutil.copy(img_path, output_images / img_path.name)

                # Save YOLO annotation
                with open(output_labels / f'{img_path.stem}.txt', 'w') as f:
                    f.write('\n'.join(yolo_lines))

if __name__ == '__main__':
    visdrone_root = Path('datasets/visdrone_raw')
    output_root = Path('datasets/visdrone')

    process_visdrone_dataset(visdrone_root, output_root, 'train')
    process_visdrone_dataset(visdrone_root, output_root, 'val')
```

### 2.2 Custom Dataset Collection

```python
# scripts/prepare_custom.py

import os
import json
import cv2
from pathlib import Path
from dataclasses import dataclass
from typing import List, Optional
import exifread

@dataclass
class FieldCapture:
    """Represents a single field capture with ground truth."""
    image_path: Path
    distance_yards: float
    target_type: str
    weather: str
    lighting: str
    timestamp: str
    gps_coords: Optional[tuple] = None
    laser_reading: Optional[float] = None

# Target classes for SniperScope
SNIPERSCOPE_CLASSES = {
    'person': 0,
    'person_head': 1,
    'car': 2,
    'truck': 3,
    'suv': 4,
    'deer': 5,
    'elk': 6,
    'wild_boar': 7,
    'coyote': 8,
    'door': 9,
    'window': 10,
    'stop_sign': 11,
    'speed_limit_sign': 12,
}

def create_annotation_from_labelimg(
    labelimg_xml: Path,
    img_width: int,
    img_height: int
) -> List[str]:
    """Convert LabelImg XML annotation to YOLO format."""
    import xml.etree.ElementTree as ET

    tree = ET.parse(labelimg_xml)
    root = tree.getroot()

    yolo_lines = []
    for obj in root.findall('object'):
        class_name = obj.find('name').text.lower()

        if class_name not in SNIPERSCOPE_CLASSES:
            print(f"Warning: Unknown class '{class_name}'")
            continue

        class_id = SNIPERSCOPE_CLASSES[class_name]

        bbox = obj.find('bndbox')
        xmin = int(bbox.find('xmin').text)
        ymin = int(bbox.find('ymin').text)
        xmax = int(bbox.find('xmax').text)
        ymax = int(bbox.find('ymax').text)

        # Convert to YOLO format
        cx = ((xmin + xmax) / 2) / img_width
        cy = ((ymin + ymax) / 2) / img_height
        w = (xmax - xmin) / img_width
        h = (ymax - ymin) / img_height

        yolo_lines.append(f"{class_id} {cx:.6f} {cy:.6f} {w:.6f} {h:.6f}")

    return yolo_lines

def create_metadata_json(captures: List[FieldCapture], output_path: Path):
    """Create metadata JSON for distance ground truth."""
    metadata = []
    for cap in captures:
        metadata.append({
            'image': cap.image_path.name,
            'distance_yards': cap.distance_yards,
            'distance_meters': cap.distance_yards * 0.9144,
            'target_type': cap.target_type,
            'weather': cap.weather,
            'lighting': cap.lighting,
            'timestamp': cap.timestamp,
            'gps': cap.gps_coords,
            'laser_reading': cap.laser_reading
        })

    with open(output_path, 'w') as f:
        json.dump(metadata, f, indent=2)

# Field collection protocol
COLLECTION_PROTOCOL = """
# SniperScope Field Data Collection Protocol

## Equipment Required
- iPhone 12+ (data collection device)
- Laser rangefinder (Leupold RX-2800 or similar)
- Tripod for consistent positioning
- Target silhouettes (human, deer, vehicle cutouts)
- Distance markers or GPS

## Distance Points
Collect images at these distances:
- 50 yards (45.7m)
- 100 yards (91.4m)
- 150 yards (137.2m)
- 200 yards (182.9m)
- 300 yards (274.3m)
- 400 yards (365.8m)
- 500 yards (457.2m)
- 600 yards (548.6m)
- 800 yards (731.5m)
- 1000 yards (914.4m)

## Per Distance Point
1. Set up target at measured distance
2. Verify with laser rangefinder (record reading)
3. Capture 20+ images varying:
   - Slight angle changes (±10°)
   - Zoom levels (1x, 2x, 3x if available)
   - Portrait/landscape orientation
4. Record metadata:
   - Time of day
   - Weather conditions
   - Lighting (sunny, overcast, shadow)
   - Target type

## Weather Conditions to Cover
- Clear sunny
- Overcast
- Hazy/smoky
- Dawn/dusk
- Light rain (if safe)

## Naming Convention
{target}_{distance}yd_{sequence}_{condition}.jpg
Example: deer_500yd_001_sunny.jpg
"""
```

### 2.3 Dataset Merging & Augmentation

```python
# scripts/merge_datasets.py

import os
import shutil
import random
from pathlib import Path
from typing import List, Tuple
import albumentations as A
import cv2
import numpy as np
from tqdm import tqdm

def merge_datasets(
    visdrone_path: Path,
    custom_path: Path,
    output_path: Path,
    visdrone_sample_ratio: float = 0.3  # Use 30% of VisDrone
):
    """Merge VisDrone and custom datasets with balanced sampling."""

    output_images_train = output_path / 'images' / 'train'
    output_images_val = output_path / 'images' / 'val'
    output_labels_train = output_path / 'labels' / 'train'
    output_labels_val = output_path / 'labels' / 'val'

    for d in [output_images_train, output_images_val,
              output_labels_train, output_labels_val]:
        d.mkdir(parents=True, exist_ok=True)

    # Copy all custom data (higher priority)
    print("Copying custom dataset...")
    for split in ['train', 'val']:
        custom_images = list((custom_path / 'images' / split).glob('*.jpg'))
        for img_path in tqdm(custom_images, desc=f'Custom {split}'):
            dst_img = output_path / 'images' / split / f'custom_{img_path.name}'
            dst_lbl = output_path / 'labels' / split / f'custom_{img_path.stem}.txt'

            shutil.copy(img_path, dst_img)

            lbl_path = custom_path / 'labels' / split / f'{img_path.stem}.txt'
            if lbl_path.exists():
                shutil.copy(lbl_path, dst_lbl)

    # Sample from VisDrone
    print(f"Sampling {visdrone_sample_ratio*100:.0f}% from VisDrone...")
    for split in ['train', 'val']:
        visdrone_images = list((visdrone_path / 'images' / split).glob('*.jpg'))
        sample_size = int(len(visdrone_images) * visdrone_sample_ratio)
        sampled = random.sample(visdrone_images, sample_size)

        for img_path in tqdm(sampled, desc=f'VisDrone {split}'):
            dst_img = output_path / 'images' / split / f'visdrone_{img_path.name}'
            dst_lbl = output_path / 'labels' / split / f'visdrone_{img_path.stem}.txt'

            shutil.copy(img_path, dst_img)

            lbl_path = visdrone_path / 'labels' / split / f'{img_path.stem}.txt'
            if lbl_path.exists():
                shutil.copy(lbl_path, dst_lbl)

# Augmentation pipeline for small object detection
def get_augmentation_pipeline() -> A.Compose:
    """Create augmentation pipeline optimized for rangefinding."""
    return A.Compose([
        # Geometric augmentations (mild - preserve size relationships)
        A.HorizontalFlip(p=0.5),
        A.ShiftScaleRotate(
            shift_limit=0.05,
            scale_limit=0.1,
            rotate_limit=5,
            p=0.5
        ),

        # Color/lighting augmentations (important for outdoor conditions)
        A.OneOf([
            A.RandomBrightnessContrast(
                brightness_limit=0.2,
                contrast_limit=0.2,
                p=1
            ),
            A.RandomGamma(gamma_limit=(80, 120), p=1),
        ], p=0.5),

        # Simulate atmospheric conditions
        A.OneOf([
            A.RandomFog(fog_coef_lower=0.1, fog_coef_upper=0.3, p=1),
            A.RandomSunFlare(
                flare_roi=(0, 0, 1, 0.5),
                angle_lower=0,
                angle_upper=1,
                num_flare_circles_lower=1,
                num_flare_circles_upper=3,
                src_radius=100,
                p=1
            ),
        ], p=0.2),

        # Simulate different times of day
        A.ColorJitter(
            brightness=0.2,
            contrast=0.2,
            saturation=0.2,
            hue=0.05,
            p=0.3
        ),

        # Image quality variations
        A.OneOf([
            A.GaussNoise(var_limit=(10, 50), p=1),
            A.ISONoise(color_shift=(0.01, 0.05), intensity=(0.1, 0.5), p=1),
            A.ImageCompression(quality_lower=70, quality_upper=95, p=1),
        ], p=0.3),

        # Blur (simulates motion or focus issues)
        A.OneOf([
            A.MotionBlur(blur_limit=5, p=1),
            A.GaussianBlur(blur_limit=5, p=1),
        ], p=0.1),

    ], bbox_params=A.BboxParams(
        format='yolo',
        label_fields=['class_labels'],
        min_visibility=0.3
    ))

def augment_dataset(
    input_path: Path,
    output_path: Path,
    augmentations_per_image: int = 3
):
    """Apply augmentations to expand dataset."""

    transform = get_augmentation_pipeline()

    for split in ['train']:  # Only augment training data
        images_dir = input_path / 'images' / split
        labels_dir = input_path / 'labels' / split

        output_images = output_path / 'images' / split
        output_labels = output_path / 'labels' / split
        output_images.mkdir(parents=True, exist_ok=True)
        output_labels.mkdir(parents=True, exist_ok=True)

        image_files = list(images_dir.glob('*.jpg'))

        for img_path in tqdm(image_files, desc=f'Augmenting {split}'):
            # Read image and labels
            image = cv2.imread(str(img_path))
            image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)

            label_path = labels_dir / f'{img_path.stem}.txt'
            bboxes = []
            class_labels = []

            if label_path.exists():
                with open(label_path, 'r') as f:
                    for line in f:
                        parts = line.strip().split()
                        class_labels.append(int(parts[0]))
                        bboxes.append([float(x) for x in parts[1:]])

            # Copy original
            shutil.copy(img_path, output_images / img_path.name)
            if label_path.exists():
                shutil.copy(label_path, output_labels / label_path.name)

            # Generate augmentations
            for i in range(augmentations_per_image):
                try:
                    augmented = transform(
                        image=image,
                        bboxes=bboxes,
                        class_labels=class_labels
                    )

                    aug_image = augmented['image']
                    aug_bboxes = augmented['bboxes']
                    aug_labels = augmented['class_labels']

                    if len(aug_bboxes) == 0:
                        continue

                    # Save augmented image
                    aug_img_name = f'{img_path.stem}_aug{i}.jpg'
                    aug_image_bgr = cv2.cvtColor(aug_image, cv2.COLOR_RGB2BGR)
                    cv2.imwrite(str(output_images / aug_img_name), aug_image_bgr)

                    # Save augmented labels
                    aug_lbl_name = f'{img_path.stem}_aug{i}.txt'
                    with open(output_labels / aug_lbl_name, 'w') as f:
                        for lbl, bbox in zip(aug_labels, aug_bboxes):
                            f.write(f"{lbl} {' '.join(f'{x:.6f}' for x in bbox)}\n")

                except Exception as e:
                    print(f"Augmentation failed for {img_path.name}: {e}")
                    continue
```

---

## 3. Training Configuration

### 3.1 Dataset Configuration

```yaml
# configs/sniperscope.yaml

# Dataset paths
path: ./datasets/merged
train: images/train
val: images/val
test: images/test

# Class names (must match preprocessing)
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

# Number of classes
nc: 13
```

### 3.2 Training Configuration

```yaml
# configs/training_config.yaml

# Model
model: yolo11s.pt  # Start with small, upgrade if accuracy insufficient
imgsz: 1280        # Higher resolution for small objects

# Training
epochs: 150
batch: 16          # Adjust based on GPU memory
patience: 30       # Early stopping patience
workers: 8

# Optimizer
optimizer: AdamW
lr0: 0.001         # Initial learning rate
lrf: 0.01          # Final learning rate factor
momentum: 0.937
weight_decay: 0.0005
warmup_epochs: 3
warmup_momentum: 0.8
warmup_bias_lr: 0.1

# Loss weights
box: 7.5           # Box loss weight
cls: 0.5           # Classification loss weight
dfl: 1.5           # Distribution focal loss weight

# Augmentation (additional to albumentations)
hsv_h: 0.015       # Hue augmentation
hsv_s: 0.7         # Saturation augmentation
hsv_v: 0.4         # Value augmentation
degrees: 5.0       # Rotation
translate: 0.1     # Translation
scale: 0.3         # Scale
shear: 2.0         # Shear
perspective: 0.0   # Keep 0 for ranging (preserves geometry)
flipud: 0.0        # No vertical flip
fliplr: 0.5        # Horizontal flip
mosaic: 0.5        # Reduced mosaic (can hurt small objects)
mixup: 0.0         # No mixup (alters apparent sizes)
copy_paste: 0.0    # No copy-paste

# Hardware
device: 0          # GPU device
amp: true          # Automatic mixed precision

# Logging
project: sniperscope
name: detector_v1
exist_ok: true
```

### 3.3 Training Script

```python
# scripts/train.py

import os
import argparse
import yaml
from pathlib import Path
from ultralytics import YOLO
import wandb

def train(
    data_config: str,
    training_config: str,
    resume: str = None
):
    """Train YOLO model for SniperScope."""

    # Load configs
    with open(training_config, 'r') as f:
        train_cfg = yaml.safe_load(f)

    # Initialize W&B
    wandb.init(
        project='sniperscope',
        name=train_cfg.get('name', 'detector'),
        config=train_cfg
    )

    # Load model
    if resume:
        model = YOLO(resume)
    else:
        model = YOLO(train_cfg['model'])

    # Train
    results = model.train(
        data=data_config,
        epochs=train_cfg['epochs'],
        imgsz=train_cfg['imgsz'],
        batch=train_cfg['batch'],
        patience=train_cfg['patience'],
        workers=train_cfg['workers'],
        optimizer=train_cfg['optimizer'],
        lr0=train_cfg['lr0'],
        lrf=train_cfg['lrf'],
        momentum=train_cfg['momentum'],
        weight_decay=train_cfg['weight_decay'],
        warmup_epochs=train_cfg['warmup_epochs'],
        box=train_cfg['box'],
        cls=train_cfg['cls'],
        dfl=train_cfg['dfl'],
        hsv_h=train_cfg['hsv_h'],
        hsv_s=train_cfg['hsv_s'],
        hsv_v=train_cfg['hsv_v'],
        degrees=train_cfg['degrees'],
        translate=train_cfg['translate'],
        scale=train_cfg['scale'],
        flipud=train_cfg['flipud'],
        fliplr=train_cfg['fliplr'],
        mosaic=train_cfg['mosaic'],
        mixup=train_cfg['mixup'],
        device=train_cfg['device'],
        amp=train_cfg['amp'],
        project=train_cfg['project'],
        name=train_cfg['name'],
        exist_ok=train_cfg['exist_ok'],
    )

    wandb.finish()

    return results

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--data', default='configs/sniperscope.yaml')
    parser.add_argument('--config', default='configs/training_config.yaml')
    parser.add_argument('--resume', default=None)
    args = parser.parse_args()

    train(args.data, args.config, args.resume)
```

---

## 4. Evaluation

### 4.1 Standard Metrics

```python
# scripts/evaluate.py

import os
from pathlib import Path
from ultralytics import YOLO
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from typing import Dict, List
import json

def evaluate_model(
    model_path: str,
    data_config: str,
    output_dir: str = 'evaluation_results'
):
    """Comprehensive model evaluation."""

    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    model = YOLO(model_path)

    # Run validation
    results = model.val(
        data=data_config,
        imgsz=1280,
        batch=16,
        conf=0.25,
        iou=0.5,
        save_json=True,
        save_hybrid=True,
        plots=True
    )

    # Extract metrics
    metrics = {
        'mAP50': float(results.box.map50),
        'mAP50-95': float(results.box.map),
        'precision': float(results.box.mp),
        'recall': float(results.box.mr),
        'per_class_ap50': {
            name: float(ap)
            for name, ap in zip(results.names.values(), results.box.ap50)
        },
        'per_class_ap': {
            name: float(ap)
            for name, ap in zip(results.names.values(), results.box.ap)
        }
    }

    # Save metrics
    with open(output_path / 'metrics.json', 'w') as f:
        json.dump(metrics, f, indent=2)

    # Generate report
    generate_evaluation_report(metrics, output_path)

    return metrics

def evaluate_by_object_size(
    model_path: str,
    data_config: str,
    output_dir: str = 'evaluation_results'
):
    """Evaluate model performance by object pixel size."""

    # Size categories (in pixels at 1280 resolution)
    SIZE_CATEGORIES = {
        'tiny': (0, 32),      # <32px (roughly >600 yards)
        'small': (32, 64),    # 32-64px (300-600 yards)
        'medium': (64, 128),  # 64-128px (150-300 yards)
        'large': (128, 256),  # 128-256px (75-150 yards)
        'xlarge': (256, 1280) # >256px (<75 yards)
    }

    model = YOLO(model_path)

    # Custom evaluation loop
    # ... implementation details

    return size_metrics

def generate_evaluation_report(metrics: Dict, output_path: Path):
    """Generate visual evaluation report."""

    # Per-class AP plot
    fig, ax = plt.subplots(figsize=(12, 6))
    classes = list(metrics['per_class_ap50'].keys())
    ap50_values = list(metrics['per_class_ap50'].values())

    bars = ax.bar(classes, ap50_values, color='steelblue')
    ax.axhline(y=0.7, color='r', linestyle='--', label='Target (0.7)')
    ax.set_xlabel('Class')
    ax.set_ylabel('AP@0.5')
    ax.set_title('Per-Class Average Precision')
    ax.set_xticklabels(classes, rotation=45, ha='right')
    ax.legend()

    plt.tight_layout()
    plt.savefig(output_path / 'per_class_ap.png', dpi=150)
    plt.close()

    # Summary metrics
    summary = f"""
    # SniperScope Model Evaluation Report

    ## Overall Metrics
    - mAP@0.5: {metrics['mAP50']:.4f}
    - mAP@0.5:0.95: {metrics['mAP50-95']:.4f}
    - Precision: {metrics['precision']:.4f}
    - Recall: {metrics['recall']:.4f}

    ## Per-Class Performance
    | Class | AP@0.5 | Status |
    |-------|--------|--------|
    """

    for cls, ap in metrics['per_class_ap50'].items():
        status = '✓' if ap >= 0.7 else '✗'
        summary += f"| {cls} | {ap:.4f} | {status} |\n"

    with open(output_path / 'report.md', 'w') as f:
        f.write(summary)
```

---

## 5. Model Export

### 5.1 Core ML Conversion

```python
# scripts/export_coreml.py

import os
import argparse
from pathlib import Path
from ultralytics import YOLO
import coremltools as ct
import torch

def export_to_coreml(
    model_path: str,
    output_dir: str = 'models/exports',
    imgsz: int = 1280,
    quantize: str = 'fp16'
):
    """Export YOLO model to Core ML format."""

    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    # Load model
    model = YOLO(model_path)

    # Export to Core ML via Ultralytics
    model.export(
        format='coreml',
        imgsz=imgsz,
        nms=True,  # Include NMS in model
        half=True if quantize == 'fp16' else False,
    )

    # Get exported path
    exported_path = Path(model_path).with_suffix('.mlpackage')

    # Additional optimization with coremltools
    mlmodel = ct.models.MLModel(str(exported_path))

    # Set metadata
    mlmodel.author = 'SniperScope'
    mlmodel.short_description = 'Object detection for passive rangefinding'
    mlmodel.version = '1.0'

    # Quantization
    if quantize == 'fp16':
        print("Applying FP16 quantization...")
        # Already done via half=True
        final_path = output_path / 'SniperScope_Detector_FP16.mlpackage'

    elif quantize == 'int8':
        print("Applying INT8 quantization...")
        from coremltools.models.neural_network import quantization_utils
        mlmodel_int8 = quantization_utils.quantize_weights(mlmodel, nbits=8)
        mlmodel = mlmodel_int8
        final_path = output_path / 'SniperScope_Detector_INT8.mlpackage'

    else:
        final_path = output_path / 'SniperScope_Detector_FP32.mlpackage'

    # Save
    mlmodel.save(str(final_path))
    print(f"Model saved to: {final_path}")

    # Print model info
    spec = mlmodel.get_spec()
    print(f"\nModel Input: {spec.description.input[0]}")
    print(f"Model Output: {spec.description.output}")

    return final_path

def benchmark_coreml_model(model_path: str, iterations: int = 100):
    """Benchmark Core ML model performance."""
    import numpy as np
    import time

    mlmodel = ct.models.MLModel(model_path)

    # Get input shape
    spec = mlmodel.get_spec()
    input_name = spec.description.input[0].name

    # Assuming image input
    dummy_input = {
        input_name: np.random.rand(1, 3, 1280, 1280).astype(np.float32)
    }

    # Warmup
    for _ in range(10):
        mlmodel.predict(dummy_input)

    # Benchmark
    times = []
    for _ in range(iterations):
        start = time.time()
        mlmodel.predict(dummy_input)
        times.append(time.time() - start)

    print(f"\nBenchmark Results ({iterations} iterations):")
    print(f"  Mean: {np.mean(times)*1000:.2f} ms")
    print(f"  Std:  {np.std(times)*1000:.2f} ms")
    print(f"  Min:  {np.min(times)*1000:.2f} ms")
    print(f"  Max:  {np.max(times)*1000:.2f} ms")

    return np.mean(times)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--model', required=True, help='Path to trained model')
    parser.add_argument('--output', default='models/exports')
    parser.add_argument('--imgsz', type=int, default=1280)
    parser.add_argument('--quantize', choices=['fp32', 'fp16', 'int8'], default='fp16')
    parser.add_argument('--benchmark', action='store_true')
    args = parser.parse_args()

    exported_path = export_to_coreml(
        args.model, args.output, args.imgsz, args.quantize
    )

    if args.benchmark:
        benchmark_coreml_model(str(exported_path))
```

---

## 6. Depth Model Setup

### 6.1 Depth Anything V2 Integration

```python
# scripts/setup_depth_model.py

import os
from pathlib import Path
import urllib.request
import coremltools as ct

DEPTH_MODEL_URLS = {
    'small': 'https://ml-assets.apple.com/coreml/models/Image/DepthEstimation/depth-anything-v2-small/depth-anything-v2-small.mlpackage.zip',
    'base': 'https://ml-assets.apple.com/coreml/models/Image/DepthEstimation/depth-anything-v2-base/depth-anything-v2-base.mlpackage.zip',
}

def download_depth_model(variant: str = 'small', output_dir: str = 'models'):
    """Download Depth Anything V2 Core ML model."""

    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    url = DEPTH_MODEL_URLS[variant]
    zip_path = output_path / f'depth-anything-v2-{variant}.zip'

    print(f"Downloading Depth Anything V2 {variant}...")
    urllib.request.urlretrieve(url, zip_path)

    # Extract
    import zipfile
    with zipfile.ZipFile(zip_path, 'r') as zip_ref:
        zip_ref.extractall(output_path)

    # Cleanup
    zip_path.unlink()

    print(f"Model downloaded to: {output_path}")

def calibrate_depth_scale(
    model_path: str,
    calibration_images: str,
    ground_truth_distances: str
):
    """Calibrate depth model scale factor using known distances."""

    import json
    import cv2
    import numpy as np

    mlmodel = ct.models.MLModel(model_path)

    # Load ground truth
    with open(ground_truth_distances, 'r') as f:
        ground_truth = json.load(f)

    scale_factors = []

    for item in ground_truth:
        img_path = os.path.join(calibration_images, item['image'])
        true_distance = item['distance_meters']

        # Load and preprocess image
        image = cv2.imread(img_path)
        image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        image = cv2.resize(image, (518, 518))  # DA V2 input size
        image = image.astype(np.float32) / 255.0
        image = np.transpose(image, (2, 0, 1))
        image = np.expand_dims(image, 0)

        # Run inference
        depth_map = mlmodel.predict({'image': image})['depth']

        # Get depth at target location (center of image for simplicity)
        h, w = depth_map.shape[-2:]
        center_depth = depth_map[0, 0, h//2, w//2]

        # Calculate scale factor
        # Depth Anything outputs inverse depth, so:
        # true_distance = scale / predicted_depth
        scale = true_distance * center_depth
        scale_factors.append(scale)

    # Use median scale factor
    calibrated_scale = np.median(scale_factors)

    print(f"Calibrated depth scale factor: {calibrated_scale:.4f}")
    print(f"Scale factor std: {np.std(scale_factors):.4f}")

    # Save calibration
    calibration = {
        'scale_factor': float(calibrated_scale),
        'scale_std': float(np.std(scale_factors)),
        'num_samples': len(scale_factors)
    }

    with open('depth_calibration.json', 'w') as f:
        json.dump(calibration, f, indent=2)

    return calibrated_scale

if __name__ == '__main__':
    download_depth_model('small', 'models/depth')
```

---

## 7. Complete Pipeline Script

```python
# scripts/run_pipeline.py

"""
Complete ML training pipeline for SniperScope.
Run with: python scripts/run_pipeline.py --all
"""

import argparse
from pathlib import Path

def run_full_pipeline(args):
    """Execute complete training pipeline."""

    # Step 1: Prepare datasets
    if args.prepare or args.all:
        print("\n" + "="*50)
        print("STEP 1: Dataset Preparation")
        print("="*50)

        from prepare_visdrone import process_visdrone_dataset
        from prepare_custom import create_metadata_json
        from merge_datasets import merge_datasets, augment_dataset

        # Process VisDrone
        process_visdrone_dataset(
            Path('datasets/visdrone_raw'),
            Path('datasets/visdrone'),
            'train'
        )
        process_visdrone_dataset(
            Path('datasets/visdrone_raw'),
            Path('datasets/visdrone'),
            'val'
        )

        # Merge datasets
        merge_datasets(
            Path('datasets/visdrone'),
            Path('datasets/custom'),
            Path('datasets/merged'),
            visdrone_sample_ratio=0.3
        )

        # Augment training data
        augment_dataset(
            Path('datasets/merged'),
            Path('datasets/augmented'),
            augmentations_per_image=3
        )

    # Step 2: Train model
    if args.train or args.all:
        print("\n" + "="*50)
        print("STEP 2: Model Training")
        print("="*50)

        from train import train
        train(
            'configs/sniperscope.yaml',
            'configs/training_config.yaml'
        )

    # Step 3: Evaluate
    if args.evaluate or args.all:
        print("\n" + "="*50)
        print("STEP 3: Model Evaluation")
        print("="*50)

        from evaluate import evaluate_model
        evaluate_model(
            'runs/detect/detector_v1/weights/best.pt',
            'configs/sniperscope.yaml',
            'evaluation_results'
        )

    # Step 4: Export to Core ML
    if args.export or args.all:
        print("\n" + "="*50)
        print("STEP 4: Core ML Export")
        print("="*50)

        from export_coreml import export_to_coreml, benchmark_coreml_model

        model_path = export_to_coreml(
            'runs/detect/detector_v1/weights/best.pt',
            'models/exports',
            imgsz=1280,
            quantize='fp16'
        )

        benchmark_coreml_model(str(model_path))

    # Step 5: Setup depth model
    if args.depth or args.all:
        print("\n" + "="*50)
        print("STEP 5: Depth Model Setup")
        print("="*50)

        from setup_depth_model import download_depth_model
        download_depth_model('small', 'models/depth')

    print("\n" + "="*50)
    print("PIPELINE COMPLETE")
    print("="*50)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='SniperScope ML Pipeline')
    parser.add_argument('--all', action='store_true', help='Run all steps')
    parser.add_argument('--prepare', action='store_true', help='Prepare datasets')
    parser.add_argument('--train', action='store_true', help='Train model')
    parser.add_argument('--evaluate', action='store_true', help='Evaluate model')
    parser.add_argument('--export', action='store_true', help='Export to Core ML')
    parser.add_argument('--depth', action='store_true', help='Setup depth model')
    args = parser.parse_args()

    if not any([args.all, args.prepare, args.train, args.evaluate, args.export, args.depth]):
        parser.print_help()
    else:
        run_full_pipeline(args)
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-22 | Initial ML pipeline specification |
