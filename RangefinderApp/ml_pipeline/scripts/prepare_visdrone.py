#!/usr/bin/env python3
"""
================================================================================
SniperScope ML Pipeline - VisDrone Dataset Preparation
================================================================================

Converts the VisDrone drone imagery dataset to YOLO format with SniperScope
class mapping. VisDrone is an excellent source of high-altitude aerial images
containing people and vehicles at various distances - perfect for training
a rangefinder object detector.

About VisDrone:
---------------
VisDrone (Visual Drones) is a large-scale benchmark dataset for visual object
detection and tracking captured by drone-mounted cameras. Key characteristics:

    - Source: Chinese Universities (Tianjin University, etc.)
    - Images: ~10,000 images across train/val/test splits
    - Altitude: Various drone heights (50-300+ meters)
    - Scenes: Urban streets, crowds, parking lots, intersections
    - Objects: Pedestrians, vehicles, cyclists, etc.

VisDrone is particularly useful for SniperScope because:
    1. Objects appear at various scales (simulating different distances)
    2. Aerial perspective is similar to elevated shooting positions
    3. Contains many small objects (challenging for detection)
    4. High-quality annotations with occlusion/truncation metadata

VisDrone Annotation Format:
---------------------------
VisDrone uses CSV-style annotations with 8 fields per object:

    x, y, w, h, score, class, truncation, occlusion

Where:
    - x, y: Top-left corner coordinates (pixels)
    - w, h: Bounding box width and height (pixels)
    - score: Confidence score (usually 0 or 1)
    - class: Object category (see below)
    - truncation: Degree of truncation (0=none, 1=partial, 2=heavy)
    - occlusion: Degree of occlusion (0=none, 1=partial, 2=heavy)

VisDrone Classes:
    0: ignored regions (not objects)
    1: pedestrian (standing person)
    2: people (sitting or other pose)
    3: bicycle
    4: car
    5: van
    6: truck
    7: tricycle (three-wheeled vehicle)
    8: awning-tricycle (covered tricycle)
    9: bus
    10: motor (motorcycle)

YOLO Annotation Format:
-----------------------
YOLO uses normalized center-based coordinates:

    class_id  center_x  center_y  width  height

All values normalized to [0, 1] relative to image dimensions.

Class Mapping Strategy:
-----------------------
We map VisDrone classes to a simplified SniperScope schema:

    VisDrone           → SniperScope    Rationale
    --------           → -----------    ---------
    1 (pedestrian)     → 0 (person)     Primary ranging target
    2 (people)         → 0 (person)     Merge all humans
    4 (car)            → 2 (car)        Small vehicle
    5 (van)            → 3 (truck)      Medium vehicle → treat as truck
    6 (truck)          → 3 (truck)      Large vehicle
    9 (bus)            → 3 (truck)      Large vehicle → treat as truck

Classes NOT mapped (ignored):
    - 0 (ignored regions): Not real objects
    - 3 (bicycle): Too small for reliable ranging
    - 7, 8 (tricycles): Region-specific, not common
    - 10 (motor): Too small for reliable ranging

Directory Structure:
--------------------
Input (VisDrone raw):
    visdrone_raw/
    ├── VisDrone2019-DET-train/
    │   ├── images/
    │   │   ├── 0000001_00001_d_0000001.jpg
    │   │   └── ...
    │   └── annotations/
    │       ├── 0000001_00001_d_0000001.txt
    │       └── ...
    └── VisDrone2019-DET-val/
        ├── images/
        └── annotations/

Output (YOLO format):
    visdrone/
    ├── dataset.yaml
    ├── images/
    │   ├── train/
    │   │   ├── 0000001_00001_d_0000001.jpg
    │   │   └── ...
    │   └── val/
    └── labels/
        ├── train/
        │   ├── 0000001_00001_d_0000001.txt
        │   └── ...
        └── val/

Quality Filtering:
------------------
This script applies several quality filters:

    1. Class filtering: Only include classes we can range reliably
    2. Size filtering: Skip boxes smaller than MIN_BOX_SIZE (10px)
    3. Bounds checking: Clip boxes to image boundaries
    4. Validation: Ensure normalized coordinates are valid [0, 1]

Usage:
------
    # Process train and val splits
    python prepare_visdrone.py --visdrone-root datasets/visdrone_raw

    # Process only train split
    python prepare_visdrone.py --visdrone-root datasets/visdrone_raw --splits train

    # Custom output directory
    python prepare_visdrone.py --output datasets/my_visdrone

Dependencies:
-------------
- OpenCV (cv2): For reading image dimensions
- tqdm: Progress bar display

Download VisDrone:
------------------
    https://github.com/VisDrone/VisDrone-Dataset

Author: SniperScope Development Team
Created: 2025
License: Educational Use Only
================================================================================
"""

import os
import sys
import shutil
from pathlib import Path
from tqdm import tqdm
import cv2
import argparse


# ==============================================================================
# CLASS MAPPING CONFIGURATION
# ==============================================================================

# Map VisDrone class IDs to SniperScope class IDs
# Only classes useful for ranging are included
#
# VisDrone classes:
#   0=ignored, 1=pedestrian, 2=people, 3=bicycle, 4=car,
#   5=van, 6=truck, 7=tricycle, 8=awning-tricycle, 9=bus, 10=motor

VISDRONE_TO_SNIPERSCOPE = {
    1: 0,   # pedestrian → person (SniperScope class 0)
    2: 0,   # people → person (merge all humans)
    4: 2,   # car → car (SniperScope class 2)
    5: 3,   # van → truck (treat medium vehicles as trucks)
    6: 3,   # truck → truck (SniperScope class 3)
    9: 3,   # bus → truck (treat large vehicles as trucks)
}

# Minimum bounding box size in pixels
# Objects smaller than this are unreliable for ranging
# 10px minimum ensures object is at least ~0.8% of 1280px image
MIN_BOX_SIZE = 10


# ==============================================================================
# ANNOTATION CONVERSION
# ==============================================================================

def convert_visdrone_annotation(line: str, img_width: int, img_height: int) -> str:
    """
    Convert a single VisDrone annotation line to YOLO format.

    This function performs the core conversion from VisDrone's pixel-based
    top-left coordinate format to YOLO's normalized center-based format.

    Input Format (VisDrone):
        x,y,w,h,score,class,truncation,occlusion

        Where x,y is top-left corner in pixels.

    Output Format (YOLO):
        class_id center_x center_y width height

        Where all coordinates are normalized to [0, 1].

    Coordinate Conversion Math:
        YOLO center_x = (x + w/2) / image_width
        YOLO center_y = (y + h/2) / image_height
        YOLO width    = w / image_width
        YOLO height   = h / image_height

    Args:
        line: Single line from VisDrone annotation file
        img_width: Image width in pixels (for normalization)
        img_height: Image height in pixels (for normalization)

    Returns:
        YOLO format annotation string, or None if annotation should be skipped.
        Skipped annotations include:
            - Unmapped classes (not in VISDRONE_TO_SNIPERSCOPE)
            - Boxes smaller than MIN_BOX_SIZE
            - Invalid/malformed annotations

    Example:
        Input:  "100,200,50,100,1,1,0,0"  (pedestrian at x=100, y=200, 50x100px)
        Output: "0 0.097656 0.347222 0.039063 0.138889"  (for 1280x720 image)
    """
    # Parse CSV-style annotation
    parts = line.strip().split(',')

    # VisDrone annotations have exactly 8 fields
    if len(parts) < 8:
        return None

    try:
        # Extract coordinates and class
        x = int(parts[0])       # Top-left X (pixels)
        y = int(parts[1])       # Top-left Y (pixels)
        w = int(parts[2])       # Width (pixels)
        h = int(parts[3])       # Height (pixels)
        # score = int(parts[4])  # Confidence (not used)
        visdrone_class = int(parts[5])  # VisDrone class ID
        # truncation = int(parts[6])  # Truncation level (not used)
        # occlusion = int(parts[7])   # Occlusion level (not used)

    except (ValueError, IndexError):
        # Malformed line - skip it
        return None

    # ==========================================================================
    # CLASS FILTERING
    # ==========================================================================
    # Only keep classes that we can use for ranging

    if visdrone_class not in VISDRONE_TO_SNIPERSCOPE:
        return None

    # Map to SniperScope class
    sniperscope_class = VISDRONE_TO_SNIPERSCOPE[visdrone_class]

    # ==========================================================================
    # SIZE FILTERING
    # ==========================================================================
    # Skip tiny boxes that are unreliable for detection/ranging

    if w < MIN_BOX_SIZE or h < MIN_BOX_SIZE:
        return None

    # ==========================================================================
    # BOUNDS CHECKING AND CLIPPING
    # ==========================================================================
    # Handle boxes that extend outside image boundaries
    # This can happen due to annotation errors or cropping

    if x < 0 or y < 0 or x + w > img_width or y + h > img_height:
        # Clip coordinates to valid range
        x = max(0, x)
        y = max(0, y)
        w = min(w, img_width - x)
        h = min(h, img_height - y)

        # After clipping, check size again
        if w < MIN_BOX_SIZE or h < MIN_BOX_SIZE:
            return None

    # ==========================================================================
    # COORDINATE CONVERSION
    # ==========================================================================
    # Convert from top-left pixel coordinates to normalized center coordinates

    # Center X = (left + width/2) / image_width
    cx = (x + w / 2) / img_width

    # Center Y = (top + height/2) / image_height
    cy = (y + h / 2) / img_height

    # Normalized width and height
    nw = w / img_width
    nh = h / img_height

    # ==========================================================================
    # VALIDATION
    # ==========================================================================
    # Ensure all normalized values are in valid range

    if not (0 <= cx <= 1 and 0 <= cy <= 1 and 0 < nw <= 1 and 0 < nh <= 1):
        return None

    # ==========================================================================
    # FORMAT OUTPUT
    # ==========================================================================
    # YOLO format: class center_x center_y width height
    # Use 6 decimal places for precision

    return f"{sniperscope_class} {cx:.6f} {cy:.6f} {nw:.6f} {nh:.6f}"


# ==============================================================================
# SPLIT PROCESSING
# ==============================================================================

def process_split(visdrone_root: Path, output_root: Path, split: str):
    """
    Process a single data split (train, val, or test) of the VisDrone dataset.

    This function iterates through all images in a split, reads their
    dimensions, converts annotations, and copies valid image/label pairs
    to the output directory.

    Processing Steps:
        1. Locate image and annotation directories
        2. For each image:
           a. Read image to get dimensions
           b. Find corresponding annotation file
           c. Convert each annotation line
           d. If valid annotations exist, copy image and save labels
        3. Report statistics

    Args:
        visdrone_root: Root directory containing VisDrone dataset
        output_root: Output directory for converted dataset
        split: Split name ('train', 'val', or 'test')

    Returns:
        Tuple of (processed_count, skipped_count):
            - processed_count: Number of images successfully converted
            - skipped_count: Number of images skipped (no valid annotations)

    Directory Expectations:
        Input:  visdrone_root/VisDrone2019-DET-{split}/images/
                visdrone_root/VisDrone2019-DET-{split}/annotations/
        Output: output_root/images/{split}/
                output_root/labels/{split}/
    """
    # ==========================================================================
    # LOCATE INPUT DIRECTORIES
    # ==========================================================================
    # VisDrone uses naming convention: VisDrone2019-DET-{split}

    images_dir = visdrone_root / f'VisDrone2019-DET-{split}' / 'images'
    annotations_dir = visdrone_root / f'VisDrone2019-DET-{split}' / 'annotations'

    # Check if split exists
    if not images_dir.exists():
        print(f"Warning: {images_dir} does not exist, skipping {split}")
        return 0, 0

    # ==========================================================================
    # CREATE OUTPUT DIRECTORIES
    # ==========================================================================
    # YOLO expects images/{split}/ and labels/{split}/ structure

    output_images = output_root / 'images' / split
    output_labels = output_root / 'labels' / split

    # Create directories (parents=True creates intermediate directories)
    output_images.mkdir(parents=True, exist_ok=True)
    output_labels.mkdir(parents=True, exist_ok=True)

    # ==========================================================================
    # PROCESS ALL IMAGES
    # ==========================================================================

    # Get list of all JPEG images in the split
    image_files = list(images_dir.glob('*.jpg'))

    processed = 0  # Successfully converted images
    skipped = 0    # Images without valid annotations

    # Process with progress bar
    for img_path in tqdm(image_files, desc=f'Processing {split}'):
        # ----------------------------------------------------------------------
        # READ IMAGE FOR DIMENSIONS
        # ----------------------------------------------------------------------
        # We need image dimensions to normalize bounding box coordinates

        img = cv2.imread(str(img_path))
        if img is None:
            skipped += 1
            continue

        # OpenCV returns (height, width, channels)
        img_height, img_width = img.shape[:2]

        # ----------------------------------------------------------------------
        # FIND ANNOTATION FILE
        # ----------------------------------------------------------------------
        # Annotation files have same name as images but .txt extension

        ann_path = annotations_dir / f'{img_path.stem}.txt'

        if not ann_path.exists():
            skipped += 1
            continue

        # ----------------------------------------------------------------------
        # CONVERT ANNOTATIONS
        # ----------------------------------------------------------------------
        # Read all annotation lines and convert valid ones

        yolo_lines = []

        with open(ann_path, 'r') as f:
            for line in f:
                yolo_line = convert_visdrone_annotation(line, img_width, img_height)
                if yolo_line:
                    yolo_lines.append(yolo_line)

        # ----------------------------------------------------------------------
        # SAVE IF VALID ANNOTATIONS EXIST
        # ----------------------------------------------------------------------
        # Only copy image and save labels if we have at least one valid annotation

        if yolo_lines:
            # Copy image to output directory
            shutil.copy(img_path, output_images / img_path.name)

            # Save YOLO format annotations
            with open(output_labels / f'{img_path.stem}.txt', 'w') as f:
                f.write('\n'.join(yolo_lines))

            processed += 1
        else:
            skipped += 1

    return processed, skipped


# ==============================================================================
# MAIN ENTRY POINT
# ==============================================================================

def main():
    """
    Parse arguments and execute dataset conversion.

    This function:
        1. Parses command line arguments
        2. Prints configuration summary
        3. Processes each requested split
        4. Creates dataset.yaml configuration
        5. Prints final statistics
    """
    # ==========================================================================
    # ARGUMENT PARSING
    # ==========================================================================

    parser = argparse.ArgumentParser(
        description='Prepare VisDrone dataset for SniperScope'
    )

    parser.add_argument(
        '--visdrone-root',
        type=str,
        default='datasets/visdrone_raw',
        help='Path to raw VisDrone dataset'
    )

    parser.add_argument(
        '--output',
        type=str,
        default='datasets/visdrone',
        help='Output directory for processed dataset'
    )

    parser.add_argument(
        '--splits',
        nargs='+',  # Accept multiple values
        default=['train', 'val'],
        help='Splits to process'
    )

    args = parser.parse_args()

    # Convert to Path objects for easier manipulation
    visdrone_root = Path(args.visdrone_root)
    output_root = Path(args.output)

    # ==========================================================================
    # PRINT CONFIGURATION
    # ==========================================================================

    print("=" * 60)
    print("VisDrone to SniperScope Dataset Converter")
    print("=" * 60)
    print(f"\nSource: {visdrone_root}")
    print(f"Output: {output_root}")
    print(f"Splits: {args.splits}")

    # Print class mapping for verification
    print(f"\nClass mapping:")
    for vd_cls, ss_cls in VISDRONE_TO_SNIPERSCOPE.items():
        # Human-readable names
        vd_names = {1: 'pedestrian', 2: 'people', 4: 'car', 5: 'van', 6: 'truck', 9: 'bus'}
        ss_names = {0: 'person', 2: 'car', 3: 'truck'}
        print(f"  {vd_names.get(vd_cls, vd_cls)} → {ss_names.get(ss_cls, ss_cls)}")
    print()

    # ==========================================================================
    # PROCESS EACH SPLIT
    # ==========================================================================

    total_processed = 0
    total_skipped = 0

    for split in args.splits:
        print(f"\nProcessing {split}...")
        processed, skipped = process_split(visdrone_root, output_root, split)
        total_processed += processed
        total_skipped += skipped
        print(f"  Processed: {processed}, Skipped: {skipped}")

    # ==========================================================================
    # PRINT SUMMARY
    # ==========================================================================

    print("\n" + "=" * 60)
    print(f"Total processed: {total_processed}")
    print(f"Total skipped: {total_skipped}")
    print("=" * 60)

    # ==========================================================================
    # CREATE DATASET CONFIGURATION FILE
    # ==========================================================================
    # YOLO requires a dataset.yaml file specifying paths and classes

    dataset_yaml = output_root / 'dataset.yaml'

    with open(dataset_yaml, 'w') as f:
        f.write(f"""# VisDrone subset for SniperScope
# Auto-generated by prepare_visdrone.py

# Dataset root path (absolute)
path: {output_root.absolute()}

# Relative paths to image directories
train: images/train
val: images/val

# Number of classes
nc: 4

# Class names (indices must match)
# Note: SniperScope uses sparse indices (0, 2, 3) for compatibility
# with the full class set (person=0, car=2, truck=3)
names:
  0: person
  2: car
  3: truck
""")

    print(f"\nDataset config saved to: {dataset_yaml}")


# ==============================================================================
# SCRIPT ENTRY POINT
# ==============================================================================

if __name__ == '__main__':
    main()
