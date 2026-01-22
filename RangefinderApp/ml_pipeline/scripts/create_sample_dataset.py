#!/usr/bin/env python3
"""
================================================================================
SniperScope ML Pipeline - Sample Dataset Generator
================================================================================

Creates synthetic training data for testing the ML pipeline before real
annotated images are available. This allows developers to validate the
entire training workflow without waiting for dataset preparation.

Purpose:
--------
When developing an ML pipeline, you often need to test the training code
before your actual dataset is ready. This script creates a "fake" dataset
with random images and synthetic bounding box annotations that follow the
exact format expected by YOLO training.

YOLO Annotation Format:
-----------------------
YOLO uses a specific text-based annotation format:

    class_id  center_x  center_y  width  height

Where:
- class_id: Integer class label (0-12 for SniperScope)
- center_x: Bounding box center X, normalized to [0, 1]
- center_y: Bounding box center Y, normalized to [0, 1]
- width: Bounding box width, normalized to [0, 1]
- height: Bounding box height, normalized to [0, 1]

Example annotation line:
    0 0.456789 0.234567 0.123456 0.345678

This represents a person (class 0) with center at (45.7%, 23.5%)
and size (12.3% x 34.6%) of the image dimensions.

Dataset Structure:
------------------
The script creates the standard YOLO dataset directory structure:

    output_dir/
    ├── dataset.yaml          # Dataset configuration file
    ├── images/
    │   ├── train/           # Training images (70%)
    │   │   ├── sample_000000.jpg
    │   │   ├── sample_000001.jpg
    │   │   └── ...
    │   ├── val/             # Validation images (20%)
    │   └── test/            # Test images (10%)
    └── labels/
        ├── train/           # Training annotations
        │   ├── sample_000000.txt
        │   ├── sample_000001.txt
        │   └── ...
        ├── val/             # Validation annotations
        └── test/            # Test annotations

Each image file has a corresponding .txt label file with the same base name.

SniperScope Class Mapping:
--------------------------
The 13 object classes used by SniperScope:

    ID  Class           Category
    --  -----           --------
    0   person          Human
    1   car             Vehicle (small)
    2   van             Vehicle (medium)
    3   truck           Vehicle (large)
    4   bus             Vehicle (large)
    5   motorcycle      Vehicle (small)
    6   bicycle         Vehicle (small)
    7   deer            Wildlife
    8   elk             Wildlife
    9   wild_boar       Wildlife
    10  coyote          Wildlife
    11  bear            Wildlife
    12  turkey          Wildlife

These classes are weighted in synthetic generation to approximate
real-world detection frequencies (more people/vehicles than wildlife).

Usage:
------
    # Create 100 sample images (default)
    python create_sample_dataset.py

    # Create 500 sample images in custom directory
    python create_sample_dataset.py --output datasets/my_test --num-images 500

Dependencies:
-------------
- PIL/Pillow: For creating synthetic images (optional, uses empty files if unavailable)
- NumPy: For generating random pixel data

Author: SniperScope Development Team
Created: 2025
License: Educational Use Only
================================================================================
"""

import os
import sys
import random
from pathlib import Path
import shutil

# ==============================================================================
# PATH SETUP
# ==============================================================================

# Add parent directory to Python path to enable imports from the ml_pipeline package
# This is a common pattern for scripts that need to import from sibling directories
sys.path.insert(0, str(Path(__file__).parent.parent))


# ==============================================================================
# MAIN DATASET CREATION FUNCTION
# ==============================================================================

def create_sample_dataset(output_dir: str, num_images: int = 100):
    """
    Create a sample YOLO-format dataset with placeholder images.

    This function generates synthetic training data for testing the ML pipeline.
    The images contain random noise (no actual objects), and the annotations
    contain random bounding boxes. This is NOT for actual model training but
    rather for testing that the training pipeline works correctly.

    Args:
        output_dir: Path where the dataset will be created.
                   Will be created if it doesn't exist.
        num_images: Total number of images to generate across all splits.
                   Default is 100 for quick testing.

    Dataset Split Ratios:
        - Training: 70% of images
        - Validation: 20% of images
        - Test: 10% of images

    Example:
        >>> create_sample_dataset('datasets/sample', num_images=100)
        # Creates 70 training, 20 validation, 10 test images

    Generated Files:
        - Random noise JPEG images (1280x720 resolution)
        - YOLO format annotation text files
        - dataset.yaml configuration file
    """
    output_path = Path(output_dir)

    # ==========================================================================
    # CREATE DIRECTORY STRUCTURE
    # ==========================================================================
    # YOLO expects a specific directory layout with parallel images/ and labels/
    # directories, each containing train/, val/, and test/ subdirectories

    for split in ['train', 'val', 'test']:
        # Create image directories
        (output_path / 'images' / split).mkdir(parents=True, exist_ok=True)
        # Create label directories (must mirror image directory structure)
        (output_path / 'labels' / split).mkdir(parents=True, exist_ok=True)

    # ==========================================================================
    # DEFINE CLASS MAPPING
    # ==========================================================================
    # These classes match the sniperscope.yaml configuration file
    # The order matters - class IDs are assigned based on list index

    classes = [
        'person',       # 0: Human targets (most common)
        'car',          # 1: Small vehicles
        'van',          # 2: Medium vehicles
        'truck',        # 3: Large vehicles
        'bus',          # 4: Large vehicles
        'motorcycle',   # 5: Small vehicles
        'bicycle',      # 6: Small vehicles
        'deer',         # 7: Wildlife - North American deer
        'elk',          # 8: Wildlife - Large cervid
        'wild_boar',    # 9: Wildlife - Wild pig
        'coyote',       # 10: Wildlife - Canid
        'bear',         # 11: Wildlife - Large predator
        'turkey',       # 12: Wildlife - Game bird
    ]

    # ==========================================================================
    # ATTEMPT TO IMPORT IMAGE GENERATION LIBRARIES
    # ==========================================================================
    # We prefer generating actual images with random pixels, but if PIL/NumPy
    # aren't available, we fall back to creating empty placeholder files

    try:
        from PIL import Image
        import numpy as np
    except ImportError:
        print("PIL not available, creating empty files instead")
        # Fall back to simpler placeholder generation
        create_placeholder_files(output_path, num_images, classes)
        return

    # ==========================================================================
    # CALCULATE SPLIT SIZES
    # ==========================================================================
    # Standard ML split: 70% train, 20% validation, 10% test
    # This ratio provides enough training data while maintaining meaningful
    # validation and test sets

    train_count = int(num_images * 0.7)  # 70% for training
    val_count = int(num_images * 0.2)    # 20% for validation
    test_count = num_images - train_count - val_count  # Remainder for test

    counts = {
        'train': train_count,
        'val': val_count,
        'test': test_count
    }

    # ==========================================================================
    # GENERATE IMAGES AND ANNOTATIONS
    # ==========================================================================

    image_id = 0  # Global counter for unique filenames

    for split, count in counts.items():
        for i in range(count):
            # ------------------------------------------------------------------
            # CREATE SYNTHETIC IMAGE
            # ------------------------------------------------------------------
            # Generate random noise image at standard resolution
            # 1280x720 is chosen because:
            # - It's a common 16:9 aspect ratio
            # - Similar to typical mobile camera output
            # - Large enough for meaningful bounding boxes

            img_width, img_height = 1280, 720

            # Create random pixel data with values 50-200 (avoiding pure black/white)
            # Shape is (height, width, channels) for PIL/NumPy
            img_array = np.random.randint(
                50,                              # Min pixel value
                200,                             # Max pixel value
                (img_height, img_width, 3),      # Shape: HxWx3 (RGB)
                dtype=np.uint8                   # 8-bit color depth
            )

            # Convert NumPy array to PIL Image
            img = Image.fromarray(img_array)

            # ------------------------------------------------------------------
            # SAVE IMAGE
            # ------------------------------------------------------------------
            # Use zero-padded 6-digit naming for consistent sorting
            # e.g., sample_000000.jpg, sample_000001.jpg, etc.

            img_name = f'sample_{image_id:06d}.jpg'
            img_path = output_path / 'images' / split / img_name

            # Save as JPEG with 85% quality (good balance of size and quality)
            img.save(str(img_path), quality=85)

            # ------------------------------------------------------------------
            # CREATE ANNOTATION FILE
            # ------------------------------------------------------------------
            # Each image needs a corresponding .txt file with the same base name
            # containing YOLO format annotations

            label_name = f'sample_{image_id:06d}.txt'
            label_path = output_path / 'labels' / split / label_name

            # Generate 1-5 random bounding boxes per image
            # Real images typically have varying numbers of objects
            num_boxes = random.randint(1, 5)

            with open(label_path, 'w') as f:
                for _ in range(num_boxes):
                    # ----------------------------------------------------------
                    # WEIGHTED CLASS SELECTION
                    # ----------------------------------------------------------
                    # Real-world detection scenarios have non-uniform class
                    # distributions. We simulate this with weighted random selection:
                    # - 60% chance: Common classes (person, car, van, truck, bus)
                    # - 20% chance: Two-wheeled vehicles (motorcycle, bicycle)
                    # - 20% chance: Wildlife classes (deer through turkey)

                    if random.random() < 0.6:
                        # Most common: people and cars (classes 0-4)
                        class_id = random.randint(0, 4)
                    elif random.random() < 0.8:
                        # Less common: motorcycles and bicycles (classes 5-6)
                        class_id = random.randint(5, 6)
                    else:
                        # Rare: wildlife (classes 7-12)
                        class_id = random.randint(7, 12)

                    # ----------------------------------------------------------
                    # GENERATE RANDOM BOUNDING BOX
                    # ----------------------------------------------------------
                    # YOLO format: center_x, center_y, width, height (all normalized)
                    # We generate boxes that are reasonably sized and positioned

                    # Random center position (keeping away from edges)
                    # Range [0.1, 0.9] ensures box won't be cut off at edges
                    cx = random.uniform(0.1, 0.9)
                    cy = random.uniform(0.1, 0.9)

                    # Random box size
                    # Width: 5% to 30% of image width
                    # Height: 5% to 40% of image height
                    w = random.uniform(0.05, 0.3)
                    h = random.uniform(0.05, 0.4)

                    # ----------------------------------------------------------
                    # CLAMP BOX TO IMAGE BOUNDS
                    # ----------------------------------------------------------
                    # Ensure the box doesn't extend outside the image
                    # For a centered box, max half-width is min(cx, 1-cx)
                    # So max full width is 2 * min(cx, 1-cx)

                    w = min(w, min(cx, 1-cx) * 2)
                    h = min(h, min(cy, 1-cy) * 2)

                    # ----------------------------------------------------------
                    # WRITE ANNOTATION LINE
                    # ----------------------------------------------------------
                    # Format: class_id center_x center_y width height
                    # Use 6 decimal places for precision
                    f.write(f'{class_id} {cx:.6f} {cy:.6f} {w:.6f} {h:.6f}\n')

            # Increment global image counter
            image_id += 1

            # ------------------------------------------------------------------
            # PROGRESS REPORTING
            # ------------------------------------------------------------------
            # Print progress every 20 images to show the script is working
            if (image_id) % 20 == 0:
                print(f'Created {image_id}/{num_images} samples')

    # ==========================================================================
    # CREATE DATASET CONFIGURATION FILE
    # ==========================================================================
    # YOLO training requires a dataset.yaml file that specifies:
    # - Path to the dataset root
    # - Relative paths to train/val/test image directories
    # - Class names and count

    yaml_content = f"""# SniperScope Sample Dataset
# Auto-generated for testing

path: {output_path.absolute()}
train: images/train
val: images/val
test: images/test

names:
  0: person
  1: car
  2: van
  3: truck
  4: bus
  5: motorcycle
  6: bicycle
  7: deer
  8: elk
  9: wild_boar
  10: coyote
  11: bear
  12: turkey

nc: 13
"""

    # Write the YAML configuration
    with open(output_path / 'dataset.yaml', 'w') as f:
        f.write(yaml_content)

    # ==========================================================================
    # PRINT SUMMARY
    # ==========================================================================
    print(f'\nSample dataset created at: {output_path}')
    print(f'  Train: {train_count} images')
    print(f'  Val: {val_count} images')
    print(f'  Test: {test_count} images')
    print(f'\nDataset config: {output_path / "dataset.yaml"}')


# ==============================================================================
# FALLBACK PLACEHOLDER GENERATION
# ==============================================================================

def create_placeholder_files(output_path: Path, num_images: int, classes: list):
    """
    Create placeholder files when PIL is not available.

    This is a fallback function that creates empty image files and simple
    annotation files. The resulting "dataset" won't actually train a model
    but will allow testing the pipeline's file handling code.

    Args:
        output_path: Root directory for the dataset
        num_images: Total number of placeholder files to create
        classes: List of class names (used to determine valid class IDs)

    Note:
        The empty .jpg files created by this function are not valid JPEG images.
        They're just empty files with .jpg extensions for testing file paths.
    """
    # Calculate split sizes (same ratios as main function)
    train_count = int(num_images * 0.7)
    val_count = int(num_images * 0.2)
    test_count = num_images - train_count - val_count

    counts = {'train': train_count, 'val': val_count, 'test': test_count}

    image_id = 0

    for split, count in counts.items():
        for i in range(count):
            # Create empty image placeholder
            # Path.touch() creates an empty file if it doesn't exist
            img_name = f'sample_{image_id:06d}.jpg'
            img_path = output_path / 'images' / split / img_name
            img_path.touch()

            # Create minimal label file with a single annotation
            label_name = f'sample_{image_id:06d}.txt'
            label_path = output_path / 'labels' / split / label_name

            with open(label_path, 'w') as f:
                # Random class with centered bounding box
                class_id = random.randint(0, len(classes) - 1)
                # Simple centered box: 50% x, 50% y, 20% width, 30% height
                f.write(f'{class_id} 0.5 0.5 0.2 0.3\n')

            image_id += 1

    print(f'Created {num_images} placeholder files')


# ==============================================================================
# COMMAND LINE INTERFACE
# ==============================================================================

def main():
    """
    Main entry point for command-line execution.

    Parses command line arguments and invokes the dataset creation function.

    Command Line Arguments:
        --output: Output directory path (default: 'datasets/sample')
        --num-images: Number of images to create (default: 100)

    Examples:
        # Use defaults (100 images in datasets/sample)
        python create_sample_dataset.py

        # Custom settings
        python create_sample_dataset.py --output datasets/test --num-images 500
    """
    import argparse

    # Create argument parser with description
    parser = argparse.ArgumentParser(
        description='Create sample dataset for testing'
    )

    # Define command line arguments
    parser.add_argument(
        '--output',
        type=str,
        default='datasets/sample',
        help='Output directory'
    )
    parser.add_argument(
        '--num-images',
        type=int,
        default=100,
        help='Number of sample images to create'
    )

    # Parse arguments
    args = parser.parse_args()

    # Change working directory to ml_pipeline root
    # This ensures relative paths in the output work correctly
    script_dir = Path(__file__).parent
    ml_pipeline_dir = script_dir.parent
    os.chdir(ml_pipeline_dir)

    # Create the dataset
    create_sample_dataset(args.output, args.num_images)


# ==============================================================================
# SCRIPT ENTRY POINT
# ==============================================================================

if __name__ == '__main__':
    main()
