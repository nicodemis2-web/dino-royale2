#!/usr/bin/env python3
"""
================================================================================
SniperScope ML Pipeline - YOLO Model Training Script
================================================================================

Trains a YOLOv11 (Ultralytics) object detection model for the SniperScope
passive rangefinding application. This script handles the complete training
workflow including configuration loading, model initialization, training
execution, and optional experiment tracking.

Purpose:
--------
This script trains a custom object detector to recognize people, vehicles,
and wildlife in camera images. The trained model will be exported to Core ML
format for deployment on iOS devices in the SniperScope app.

YOLO (You Only Look Once):
--------------------------
YOLO is a real-time object detection architecture that processes images in
a single forward pass through a neural network. Key characteristics:

    - Single-shot detection: Faster than two-stage detectors (R-CNN family)
    - Multi-scale detection: Detects objects at different sizes
    - Anchor-free (YOLOv8+): No predefined anchor boxes
    - End-to-end: Outputs bounding boxes + class probabilities directly

YOLOv11/v8 Architecture Variants:
    - yolo11n.pt  (Nano)   - Smallest, fastest, ~3.2M params
    - yolo11s.pt  (Small)  - Good balance, ~9.5M params
    - yolo11m.pt  (Medium) - Better accuracy, ~21.5M params
    - yolo11l.pt  (Large)  - High accuracy, ~43.7M params
    - yolo11x.pt  (XLarge) - Maximum accuracy, ~86.7M params

For mobile deployment (SniperScope), we use yolo11s as it balances
accuracy and inference speed on mobile neural engines.

Training Configuration:
-----------------------
Training hyperparameters can be specified via:
    1. YAML configuration file (--config)
    2. Command line arguments (override config file)
    3. Default values in this script

Key Hyperparameters:
    - epochs: Number of training iterations over full dataset
    - batch: Number of images per training step (GPU memory dependent)
    - imgsz: Input image resolution (larger = better accuracy, slower)
    - lr0: Initial learning rate (typical: 0.01 for SGD, 0.001 for Adam)
    - patience: Early stopping patience (stop if no improvement)

Loss Functions:
    - box: Bounding box regression loss weight
    - cls: Classification loss weight
    - dfl: Distribution Focal Loss weight (for box refinement)

Data Augmentation:
    - hsv_h/s/v: Color space augmentation
    - degrees: Rotation augmentation
    - translate: Translation augmentation
    - scale: Scale augmentation
    - mosaic: Mosaic augmentation (combines 4 images)
    - mixup: Mixup augmentation (blends 2 images)

Weights & Biases Integration:
-----------------------------
This script optionally integrates with Weights & Biases (wandb) for
experiment tracking. When enabled, wandb logs:
    - Training/validation metrics (loss, mAP, precision, recall)
    - Learning rate schedules
    - Sample predictions
    - Model checkpoints
    - System metrics (GPU utilization, memory)

Usage:
------
    # Basic training with defaults
    python train.py --data configs/sniperscope.yaml

    # Full customization
    python train.py \\
        --data configs/sniperscope.yaml \\
        --config configs/training_config.yaml \\
        --model yolo11m.pt \\
        --epochs 200 \\
        --batch 32 \\
        --device 0 \\
        --project sniperscope \\
        --name detector_v1

    # Resume from checkpoint
    python train.py --resume runs/detect/exp/weights/last.pt

    # Disable wandb logging
    python train.py --data configs/sniperscope.yaml --no-wandb

Output:
-------
Training creates a directory structure under the project name:
    sniperscope/
    └── detector_YYYYMMDD_HHMMSS/
        ├── weights/
        │   ├── best.pt       # Best model (highest mAP)
        │   └── last.pt       # Last epoch model
        ├── results.csv       # Training metrics
        ├── results.png       # Loss/metric plots
        ├── confusion_matrix.png
        ├── F1_curve.png
        ├── PR_curve.png
        └── ...               # Additional visualizations

Dependencies:
-------------
- ultralytics: YOLO implementation
- wandb (optional): Experiment tracking
- PyYAML: Configuration file parsing
- torch: Deep learning framework (installed with ultralytics)

Author: SniperScope Development Team
Created: 2025
License: Educational Use Only
================================================================================
"""

import os
import sys
import argparse
import yaml
from pathlib import Path
from datetime import datetime

# ==============================================================================
# PATH SETUP
# ==============================================================================

# Add parent directory to Python path for imports from ml_pipeline package
sys.path.insert(0, str(Path(__file__).parent.parent))

# ==============================================================================
# IMPORT YOLO
# ==============================================================================

from ultralytics import YOLO

# ==============================================================================
# OPTIONAL: WEIGHTS & BIASES INTEGRATION
# ==============================================================================

# Attempt to import wandb for experiment tracking
# wandb is optional - training works without it
try:
    import wandb
    WANDB_AVAILABLE = True
except ImportError:
    WANDB_AVAILABLE = False
    print("Warning: wandb not available, logging will be local only")


# ==============================================================================
# CONFIGURATION LOADING
# ==============================================================================

def load_config(config_path: str) -> dict:
    """
    Load training configuration from a YAML file.

    YAML configuration files allow storing complex hyperparameter settings
    that can be version controlled and shared between experiments.

    Args:
        config_path: Path to the YAML configuration file.

    Returns:
        Dictionary containing configuration key-value pairs.

    Example config file (training_config.yaml):
        epochs: 100
        batch: 16
        imgsz: 1280
        optimizer: AdamW
        lr0: 0.001
        patience: 30

    Raises:
        FileNotFoundError: If config file doesn't exist
        yaml.YAMLError: If config file is malformed
    """
    with open(config_path, 'r') as f:
        return yaml.safe_load(f)


# ==============================================================================
# MAIN TRAINING FUNCTION
# ==============================================================================

def train(
    data_config: str,
    training_config: str = None,
    model_path: str = None,
    resume: str = None,
    epochs: int = None,
    batch: int = None,
    device: str = None,
    project: str = None,
    name: str = None,
    use_wandb: bool = True,
):
    """
    Train a YOLO model for SniperScope object detection.

    This function handles the complete training workflow:
    1. Load and merge configurations (file + CLI overrides)
    2. Initialize or resume model
    3. Optionally setup wandb experiment tracking
    4. Execute training loop
    5. Save results and model checkpoints

    Args:
        data_config: Path to dataset YAML config (required).
                    Specifies train/val/test image paths and class names.
        training_config: Path to training YAML config (optional).
                        Contains hyperparameters like epochs, batch size, etc.
        model_path: Path to base model or pretrained weights.
                   Defaults to 'yolo11s.pt' (downloads automatically).
        resume: Path to checkpoint to resume training from.
               Overrides model_path if specified.
        epochs: Number of training epochs (overrides config).
        batch: Batch size (overrides config). Reduce if OOM.
        device: Training device - '0' for GPU 0, 'cpu' for CPU.
        project: Project name for organizing runs.
        name: Run name within project. Auto-generated if not specified.
        use_wandb: Enable Weights & Biases logging.

    Returns:
        Ultralytics Results object containing training metrics.

    Training Flow:
        1. For each epoch:
           a. Forward pass through all training batches
           b. Compute loss (box + cls + dfl)
           c. Backward pass (gradient computation)
           d. Optimizer step (weight update)
           e. Validate on validation set
           f. Save checkpoint if best model
        2. Apply learning rate schedule
        3. Early stopping if no improvement for 'patience' epochs

    GPU Memory Considerations:
        - Batch size directly affects GPU memory usage
        - Larger imgsz requires more memory
        - If OOM errors occur, reduce batch size or imgsz
        - Mixed precision (AMP) reduces memory by ~30%
    """
    # ==========================================================================
    # LOAD AND MERGE CONFIGURATIONS
    # ==========================================================================

    # Start with empty config dict
    train_cfg = {}

    # Load from YAML file if provided
    if training_config and Path(training_config).exists():
        train_cfg = load_config(training_config)
        print(f"Loaded training config from: {training_config}")

    # Apply command line overrides (take precedence over config file)
    # This allows quick experimentation without editing config files
    if epochs:
        train_cfg['epochs'] = epochs
    if batch:
        train_cfg['batch'] = batch
    if device:
        train_cfg['device'] = device
    if project:
        train_cfg['project'] = project
    if name:
        train_cfg['name'] = name

    # ==========================================================================
    # SET DEFAULTS FOR MISSING VALUES
    # ==========================================================================
    # These defaults are tuned for SniperScope training on typical hardware
    # setdefault() only sets the value if the key doesn't exist

    # Model architecture: yolo11s is good balance for mobile deployment
    train_cfg.setdefault('model', 'yolo11s.pt')

    # Training duration: 100 epochs is usually sufficient with early stopping
    train_cfg.setdefault('epochs', 100)

    # Batch size: 16 works on most GPUs with 8GB+ VRAM
    train_cfg.setdefault('batch', 16)

    # Image size: 1280 for high-resolution detection (rangefinding needs precision)
    train_cfg.setdefault('imgsz', 1280)

    # Device: GPU 0 by default
    train_cfg.setdefault('device', 0)

    # Output organization
    train_cfg.setdefault('project', 'sniperscope')
    train_cfg.setdefault('name', f'detector_{datetime.now().strftime("%Y%m%d_%H%M%S")}')

    # ==========================================================================
    # INITIALIZE WEIGHTS & BIASES (OPTIONAL)
    # ==========================================================================
    # wandb provides experiment tracking, visualization, and model versioning

    if use_wandb and WANDB_AVAILABLE:
        wandb.init(
            project=train_cfg['project'],  # Group related experiments
            name=train_cfg['name'],         # Unique run identifier
            config=train_cfg,               # Log all hyperparameters
        )
        print("Weights & Biases logging enabled")

    # ==========================================================================
    # LOAD MODEL
    # ==========================================================================

    if resume:
        # Resume from checkpoint - continues training from saved state
        # Includes optimizer state, epoch number, best metrics
        print(f"Resuming from: {resume}")
        model = YOLO(resume)
    else:
        # Load base model (pretrained on COCO or from scratch)
        model_to_load = model_path or train_cfg['model']
        print(f"Loading base model: {model_to_load}")
        model = YOLO(model_to_load)

    # ==========================================================================
    # PRINT TRAINING CONFIGURATION
    # ==========================================================================
    # Display key settings for verification before training starts

    print(f"\nTraining Configuration:")
    print(f"  Data: {data_config}")
    print(f"  Epochs: {train_cfg['epochs']}")
    print(f"  Batch: {train_cfg['batch']}")
    print(f"  Image Size: {train_cfg['imgsz']}")
    print(f"  Device: {train_cfg['device']}")
    print()

    # ==========================================================================
    # EXECUTE TRAINING
    # ==========================================================================
    # The model.train() method handles the entire training loop

    results = model.train(
        # ======================================================================
        # DATASET CONFIGURATION
        # ======================================================================
        data=data_config,  # Path to dataset.yaml

        # ======================================================================
        # TRAINING DURATION
        # ======================================================================
        epochs=train_cfg.get('epochs', 100),       # Total training epochs
        patience=train_cfg.get('patience', 30),     # Early stopping patience

        # ======================================================================
        # BATCH AND IMAGE SIZE
        # ======================================================================
        imgsz=train_cfg.get('imgsz', 1280),        # Input image size
        batch=train_cfg.get('batch', 16),           # Batch size

        # ======================================================================
        # DATA LOADING
        # ======================================================================
        workers=train_cfg.get('workers', 8),        # Dataloader workers

        # ======================================================================
        # OPTIMIZER CONFIGURATION
        # ======================================================================
        # AdamW is recommended for most cases - stable and effective
        optimizer=train_cfg.get('optimizer', 'AdamW'),

        # Learning rate schedule
        lr0=train_cfg.get('lr0', 0.001),           # Initial learning rate
        lrf=train_cfg.get('lrf', 0.01),             # Final LR as fraction of lr0

        # Momentum (for SGD, not used with Adam)
        momentum=train_cfg.get('momentum', 0.937),

        # L2 regularization to prevent overfitting
        weight_decay=train_cfg.get('weight_decay', 0.0005),

        # Warmup: gradually increase LR at start to prevent instability
        warmup_epochs=train_cfg.get('warmup_epochs', 3),

        # ======================================================================
        # LOSS FUNCTION WEIGHTS
        # ======================================================================
        # Balance between different loss components
        box=train_cfg.get('box', 7.5),    # Box regression loss weight
        cls=train_cfg.get('cls', 0.5),    # Classification loss weight
        dfl=train_cfg.get('dfl', 1.5),    # Distribution Focal Loss weight

        # ======================================================================
        # DATA AUGMENTATION
        # ======================================================================
        # These augmentations improve model generalization

        # Color augmentation (HSV space)
        hsv_h=train_cfg.get('hsv_h', 0.015),  # Hue shift
        hsv_s=train_cfg.get('hsv_s', 0.7),    # Saturation shift
        hsv_v=train_cfg.get('hsv_v', 0.4),    # Value (brightness) shift

        # Geometric augmentation
        degrees=train_cfg.get('degrees', 5.0),     # Rotation range
        translate=train_cfg.get('translate', 0.1),  # Translation fraction
        scale=train_cfg.get('scale', 0.3),          # Scale range

        # Flip augmentation
        flipud=train_cfg.get('flipud', 0.0),  # Vertical flip (disabled)
        fliplr=train_cfg.get('fliplr', 0.5),  # Horizontal flip

        # Advanced augmentation
        mosaic=train_cfg.get('mosaic', 0.5),  # Mosaic probability
        mixup=train_cfg.get('mixup', 0.0),    # Mixup probability (disabled)

        # ======================================================================
        # HARDWARE AND PERFORMANCE
        # ======================================================================
        device=train_cfg.get('device', 0),   # GPU device ID
        amp=train_cfg.get('amp', True),       # Automatic Mixed Precision

        # ======================================================================
        # OUTPUT CONFIGURATION
        # ======================================================================
        project=train_cfg.get('project', 'sniperscope'),  # Parent directory
        name=train_cfg.get('name', 'detector'),            # Run directory
        exist_ok=train_cfg.get('exist_ok', True),          # Allow overwrite

        # Checkpointing
        save=train_cfg.get('save', True),           # Save checkpoints
        save_period=train_cfg.get('save_period', 10),  # Save every N epochs

        # Visualization
        plots=train_cfg.get('plots', True),  # Generate metric plots
    )

    # ==========================================================================
    # CLEANUP WANDB SESSION
    # ==========================================================================

    if use_wandb and WANDB_AVAILABLE:
        wandb.finish()

    # ==========================================================================
    # PRINT TRAINING SUMMARY
    # ==========================================================================

    print("\n" + "=" * 60)
    print("Training Complete!")
    print("=" * 60)
    print(f"Best model saved to: {results.save_dir}/weights/best.pt")
    print(f"Last model saved to: {results.save_dir}/weights/last.pt")

    return results


# ==============================================================================
# COMMAND LINE INTERFACE
# ==============================================================================

def main():
    """
    Parse command line arguments and run training.

    This function provides a flexible CLI interface that allows:
    1. Specifying configuration files
    2. Overriding specific hyperparameters
    3. Resuming training from checkpoints
    4. Controlling logging behavior

    All arguments are optional except --data, which specifies the dataset.
    """
    parser = argparse.ArgumentParser(
        description='Train SniperScope YOLO model'
    )

    # ==========================================================================
    # CONFIGURATION FILE ARGUMENTS
    # ==========================================================================

    parser.add_argument(
        '--data',
        type=str,
        default='configs/sniperscope.yaml',
        help='Path to dataset config'
    )
    parser.add_argument(
        '--config',
        type=str,
        default='configs/training_config.yaml',
        help='Path to training config'
    )

    # ==========================================================================
    # MODEL ARGUMENTS
    # ==========================================================================

    parser.add_argument(
        '--model',
        type=str,
        default=None,
        help='Path to base model'
    )
    parser.add_argument(
        '--resume',
        type=str,
        default=None,
        help='Path to checkpoint to resume'
    )

    # ==========================================================================
    # TRAINING HYPERPARAMETER OVERRIDES
    # ==========================================================================

    parser.add_argument(
        '--epochs',
        type=int,
        default=None,
        help='Override epochs'
    )
    parser.add_argument(
        '--batch',
        type=int,
        default=None,
        help='Override batch size'
    )
    parser.add_argument(
        '--device',
        type=str,
        default=None,
        help='Device (0, 1, cpu)'
    )

    # ==========================================================================
    # OUTPUT CONFIGURATION
    # ==========================================================================

    parser.add_argument(
        '--project',
        type=str,
        default=None,
        help='Project name'
    )
    parser.add_argument(
        '--name',
        type=str,
        default=None,
        help='Run name'
    )

    # ==========================================================================
    # LOGGING CONFIGURATION
    # ==========================================================================

    parser.add_argument(
        '--no-wandb',
        action='store_true',
        help='Disable wandb logging'
    )

    # Parse arguments
    args = parser.parse_args()

    # Execute training with parsed arguments
    train(
        data_config=args.data,
        training_config=args.config,
        model_path=args.model,
        resume=args.resume,
        epochs=args.epochs,
        batch=args.batch,
        device=args.device,
        project=args.project,
        name=args.name,
        use_wandb=not args.no_wandb,  # Note: flag inverts boolean
    )


# ==============================================================================
# SCRIPT ENTRY POINT
# ==============================================================================

if __name__ == '__main__':
    main()
