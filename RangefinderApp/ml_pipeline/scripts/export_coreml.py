#!/usr/bin/env python3
"""
================================================================================
SniperScope ML Pipeline - Core ML Export Script
================================================================================

Exports trained YOLO PyTorch models (.pt) to Apple Core ML format (.mlpackage)
for deployment on iOS devices. This script handles the complete export workflow
including quantization, optimization, and benchmarking.

Purpose:
--------
The SniperScope iOS app runs object detection inference on-device using the
Apple Neural Engine (ANE). This requires converting the PyTorch model to
Core ML format, which Apple's hardware can accelerate efficiently.

Core ML Overview:
-----------------
Core ML is Apple's machine learning framework that enables:

    - On-device inference (no network required)
    - Hardware acceleration via:
        * Neural Engine (ANE) - dedicated ML accelerator
        * GPU - graphics processor
        * CPU - general purpose (fallback)
    - Privacy (data never leaves device)
    - Low latency (no network round-trip)

Core ML Model Formats:
    .mlmodel   - Legacy format (deprecated)
    .mlpackage - Modern format (directory containing model + metadata)

Export Pipeline:
----------------
    1. Load trained PyTorch model (.pt)
    2. Export via Ultralytics to Core ML
    3. Optionally apply quantization (FP16, INT8)
    4. Optimize for specific compute units (ANE/GPU/CPU)
    5. Benchmark inference speed
    6. Save with standardized naming

Quantization Options:
---------------------
Quantization reduces model size and can improve inference speed:

    FP32 (Full Precision):
        - Original 32-bit floating point weights
        - Highest accuracy
        - Largest model size (~4x INT8)
        - Slowest inference on ANE

    FP16 (Half Precision):
        - 16-bit floating point weights
        - Minimal accuracy loss (<0.1%)
        - Half the size of FP32
        - Native ANE support (recommended)

    INT8 (Integer Quantization):
        - 8-bit integer weights
        - Small accuracy loss (0.1-1%)
        - Smallest model size (1/4 of FP32)
        - Fastest inference

For SniperScope, FP16 is recommended as it provides:
    - Good accuracy for bounding box precision
    - Small model size for app distribution
    - Fast ANE inference

NMS (Non-Maximum Suppression):
------------------------------
NMS is a post-processing step that removes overlapping detections.
Including NMS in the Core ML model:

    Advantages:
        - Simpler Swift code (no manual NMS)
        - Single model prediction call
        - Consistent behavior across platforms

    Disadvantages:
        - Less flexibility in threshold tuning
        - Slightly larger model
        - May be slower than native Swift NMS

SniperScope includes NMS in the model for simplicity.

Usage:
------
    # Basic export (FP16, with NMS)
    python export_coreml.py --model runs/detect/best.pt

    # Full precision, no NMS
    python export_coreml.py --model best.pt --quantize fp32 --no-nms

    # INT8 quantization for smallest model
    python export_coreml.py --model best.pt --quantize int8

    # Custom output directory
    python export_coreml.py --model best.pt --output models/ios

    # Skip benchmarking
    python export_coreml.py --model best.pt --no-benchmark

Output:
-------
    models/exports/
    └── SniperScope_Detector_FP16.mlpackage/
        ├── Data/
        │   └── com.apple.CoreML/
        │       └── weights/           # Model weights
        └── Manifest.json              # Model metadata

iOS Integration:
----------------
To use in Swift:

    import CoreML
    import Vision

    // Load model
    let config = MLModelConfiguration()
    config.computeUnits = .all  // Use ANE when available
    let model = try SniperScope_Detector_FP16(configuration: config)

    // Run inference
    let handler = VNImageRequestHandler(cgImage: image)
    let request = VNCoreMLRequest(model: visionModel)
    try handler.perform([request])

Dependencies:
-------------
- ultralytics: Model loading and export
- coremltools: Advanced Core ML operations (optional, for INT8)
- numpy: Benchmarking data generation

Author: SniperScope Development Team
Created: 2025
License: Educational Use Only
================================================================================
"""

import os
import sys
import argparse
import time
from pathlib import Path

import numpy as np

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
# OPTIONAL: COREMLTOOLS FOR ADVANCED QUANTIZATION
# ==============================================================================

# coremltools provides additional Core ML functionality beyond Ultralytics export
# It's optional - basic export works without it
try:
    import coremltools as ct
    COREML_AVAILABLE = True
except ImportError:
    COREML_AVAILABLE = False
    print("Warning: coremltools not available")


# ==============================================================================
# MAIN EXPORT FUNCTION
# ==============================================================================

def export_to_coreml(
    model_path: str,
    output_dir: str = 'models/exports',
    imgsz: int = 1280,
    quantize: str = 'fp16',
    nms: bool = True,
    benchmark: bool = True,
):
    """
    Export YOLO model to Core ML format for iOS deployment.

    This function performs the complete export pipeline:
        1. Load trained PyTorch model
        2. Export to Core ML via Ultralytics
        3. Apply optional quantization
        4. Save with standardized naming
        5. Run optional benchmarks

    Args:
        model_path: Path to trained .pt model file.
                   This should be the best.pt from training.
        output_dir: Directory to save exported model.
                   Will be created if it doesn't exist.
        imgsz: Input image size for the model.
              Should match training imgsz (default 1280).
        quantize: Quantization mode:
                 - 'fp32': Full precision (largest, most accurate)
                 - 'fp16': Half precision (recommended for iOS)
                 - 'int8': Integer quantization (smallest, fastest)
        nms: Whether to include Non-Maximum Suppression in model.
            True = simpler inference code, recommended.
        benchmark: Whether to run inference benchmarks after export.
                  Requires coremltools.

    Returns:
        Path to exported .mlpackage file, or None if export failed.

    Export Flow:
        1. model.export() - Ultralytics handles PyTorch → Core ML conversion
        2. If INT8 requested, apply additional quantization via coremltools
        3. Copy to output directory with standardized naming
        4. Optionally benchmark on CPU (ANE not available in Python)

    Model Naming Convention:
        SniperScope_Detector_{QUANTIZE}.mlpackage
        Examples:
            SniperScope_Detector_FP16.mlpackage
            SniperScope_Detector_INT8.mlpackage
    """
    # Create output directory
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    # ==========================================================================
    # PRINT EXPORT CONFIGURATION
    # ==========================================================================

    print("=" * 60)
    print("SniperScope Model Export to Core ML")
    print("=" * 60)
    print(f"\nSource: {model_path}")
    print(f"Output: {output_path}")
    print(f"Image size: {imgsz}")
    print(f"Quantization: {quantize}")
    print(f"Include NMS: {nms}")
    print()

    # ==========================================================================
    # LOAD PYTORCH MODEL
    # ==========================================================================

    print("Loading model...")
    model = YOLO(model_path)

    # ==========================================================================
    # EXPORT TO CORE ML
    # ==========================================================================
    # Ultralytics handles the conversion from PyTorch to Core ML format

    print("Exporting to Core ML...")

    # Build export arguments
    export_args = {
        'format': 'coreml',    # Target format
        'imgsz': imgsz,        # Input size (must match training)
        'nms': nms,            # Include NMS in model
    }

    # FP16 quantization is applied via the 'half' argument
    if quantize == 'fp16':
        export_args['half'] = True

    # Execute export
    # This creates a .mlpackage in the same directory as the input model
    exported_path = model.export(**export_args)
    print(f"Exported to: {exported_path}")

    # ==========================================================================
    # LOCATE EXPORTED FILE
    # ==========================================================================
    # Ultralytics may name the output differently, so we search for it

    exported_file = Path(exported_path)

    if not exported_file.exists():
        # Try common variations
        for suffix in ['.mlpackage', '.mlmodel']:
            test_path = Path(model_path).with_suffix(suffix)
            if test_path.exists():
                exported_file = test_path
                break

    if not exported_file.exists():
        print(f"Warning: Could not find exported file at {exported_file}")
        return None

    # ==========================================================================
    # APPLY INT8 QUANTIZATION (OPTIONAL)
    # ==========================================================================
    # INT8 quantization requires coremltools and additional processing

    if COREML_AVAILABLE and quantize == 'int8':
        print("\nApplying INT8 quantization...")
        try:
            # Load the exported Core ML model
            mlmodel = ct.models.MLModel(str(exported_file))

            # Apply weight quantization to 8 bits
            # This significantly reduces model size
            from coremltools.models.neural_network import quantization_utils
            mlmodel_quantized = quantization_utils.quantize_weights(mlmodel, nbits=8)

            # Save quantized model with new name
            quantized_path = output_path / f'SniperScope_Detector_INT8.mlpackage'
            mlmodel_quantized.save(str(quantized_path))
            print(f"INT8 model saved to: {quantized_path}")

            # Use quantized model for final output
            exported_file = quantized_path

        except Exception as e:
            print(f"Warning: INT8 quantization failed: {e}")

    # ==========================================================================
    # COPY TO OUTPUT WITH STANDARDIZED NAME
    # ==========================================================================

    # Determine final filename based on format and quantization
    if exported_file.suffix == '.mlpackage':
        final_name = f'SniperScope_Detector_{quantize.upper()}.mlpackage'
    else:
        final_name = f'SniperScope_Detector_{quantize.upper()}.mlmodel'

    final_path = output_path / final_name

    # Copy if source and destination differ
    if exported_file != final_path:
        import shutil

        # Remove existing file/directory if present
        if final_path.exists():
            if final_path.is_dir():
                shutil.rmtree(final_path)  # .mlpackage is a directory
            else:
                final_path.unlink()

        # Copy (directory for .mlpackage, file for .mlmodel)
        if exported_file.is_dir():
            shutil.copytree(exported_file, final_path)
        else:
            shutil.copy(exported_file, final_path)

    print(f"\nFinal model: {final_path}")

    # ==========================================================================
    # CALCULATE MODEL SIZE
    # ==========================================================================

    if final_path.is_dir():
        # .mlpackage is a directory - sum all file sizes
        size_bytes = sum(f.stat().st_size for f in final_path.rglob('*') if f.is_file())
    else:
        size_bytes = final_path.stat().st_size

    size_mb = size_bytes / (1024 * 1024)
    print(f"Model size: {size_mb:.2f} MB")

    # ==========================================================================
    # BENCHMARK (OPTIONAL)
    # ==========================================================================

    if benchmark and COREML_AVAILABLE:
        print("\n" + "-" * 40)
        print("Benchmarking...")
        benchmark_model(str(final_path), imgsz)

    return str(final_path)


# ==============================================================================
# BENCHMARKING FUNCTION
# ==============================================================================

def benchmark_model(model_path: str, imgsz: int = 1280, iterations: int = 50):
    """
    Benchmark Core ML model inference performance.

    This function measures inference latency on the CPU (Python environment
    doesn't have access to Neural Engine). Real iOS performance will be
    significantly faster when using ANE.

    Benchmarking Process:
        1. Load Core ML model
        2. Create dummy input tensor
        3. Run warmup iterations (not timed)
        4. Run timed iterations
        5. Calculate statistics (mean, std, min, max, FPS)

    Args:
        model_path: Path to .mlpackage or .mlmodel file
        imgsz: Input image size (for creating dummy input)
        iterations: Number of inference iterations to run

    Note:
        These benchmarks run on CPU only. Real iOS performance on
        Neural Engine will be 3-10x faster. Use this for relative
        comparisons between models, not absolute performance estimation.

    Typical Results (M1 MacBook Pro, CPU):
        FP32: ~150ms per inference
        FP16: ~80ms per inference
        INT8: ~50ms per inference

    Typical iOS Results (iPhone 14 Pro, Neural Engine):
        FP16: ~15ms per inference (60+ FPS)
    """
    # Check if coremltools is available
    if not COREML_AVAILABLE:
        print("coremltools not available for benchmarking")
        return

    # Load model
    try:
        mlmodel = ct.models.MLModel(model_path)
    except Exception as e:
        print(f"Failed to load model for benchmarking: {e}")
        return

    # ==========================================================================
    # GET INPUT SPECIFICATION
    # ==========================================================================
    # Core ML models define their expected input format

    spec = mlmodel.get_spec()
    input_desc = spec.description.input[0]
    input_name = input_desc.name

    print(f"Input: {input_name}")
    print(f"Running {iterations} iterations...")

    # ==========================================================================
    # CREATE DUMMY INPUT
    # ==========================================================================
    # Generate random image data matching model's expected input shape

    # YOLO models typically expect [batch, channels, height, width] or [height, width, channels]
    # Start with NCHW format
    dummy_input = np.random.rand(1, 3, imgsz, imgsz).astype(np.float32)

    # ==========================================================================
    # WARMUP ITERATIONS
    # ==========================================================================
    # Run a few iterations without timing to warm up caches and JIT compilation

    print("Warming up...")
    for _ in range(5):
        try:
            mlmodel.predict({input_name: dummy_input})
        except Exception:
            # Try different input format (HWC instead of NCHW)
            dummy_input = np.random.rand(imgsz, imgsz, 3).astype(np.float32)
            try:
                mlmodel.predict({input_name: dummy_input})
            except Exception as e:
                print(f"Benchmark failed: {e}")
                return

    # ==========================================================================
    # TIMED ITERATIONS
    # ==========================================================================

    times = []

    for i in range(iterations):
        # Time single inference
        start = time.time()
        mlmodel.predict({input_name: dummy_input})
        elapsed = time.time() - start
        times.append(elapsed)

        # Progress update
        if (i + 1) % 10 == 0:
            print(f"  {i + 1}/{iterations} completed")

    # ==========================================================================
    # CALCULATE STATISTICS
    # ==========================================================================

    # Convert to milliseconds
    times = np.array(times) * 1000

    print(f"\nBenchmark Results:")
    print(f"  Mean: {np.mean(times):.2f} ms")      # Average latency
    print(f"  Std:  {np.std(times):.2f} ms")       # Variability
    print(f"  Min:  {np.min(times):.2f} ms")       # Best case
    print(f"  Max:  {np.max(times):.2f} ms")       # Worst case
    print(f"  FPS:  {1000 / np.mean(times):.1f}")  # Frames per second


# ==============================================================================
# COMMAND LINE INTERFACE
# ==============================================================================

def main():
    """
    Parse command line arguments and execute export.

    This function provides a CLI interface for model export with options
    for customizing quantization, output location, and benchmarking.
    """
    parser = argparse.ArgumentParser(
        description='Export YOLO model to Core ML'
    )

    # ==========================================================================
    # REQUIRED ARGUMENTS
    # ==========================================================================

    parser.add_argument(
        '--model',
        type=str,
        required=True,
        help='Path to trained .pt model'
    )

    # ==========================================================================
    # OUTPUT CONFIGURATION
    # ==========================================================================

    parser.add_argument(
        '--output',
        type=str,
        default='models/exports',
        help='Output directory'
    )

    # ==========================================================================
    # MODEL CONFIGURATION
    # ==========================================================================

    parser.add_argument(
        '--imgsz',
        type=int,
        default=1280,
        help='Input image size'
    )

    parser.add_argument(
        '--quantize',
        type=str,
        choices=['fp32', 'fp16', 'int8'],
        default='fp16',
        help='Quantization mode'
    )

    parser.add_argument(
        '--no-nms',
        action='store_true',
        help='Do not include NMS in model'
    )

    # ==========================================================================
    # BENCHMARK CONFIGURATION
    # ==========================================================================

    parser.add_argument(
        '--no-benchmark',
        action='store_true',
        help='Skip benchmarking'
    )

    # Parse arguments
    args = parser.parse_args()

    # Execute export
    export_to_coreml(
        model_path=args.model,
        output_dir=args.output,
        imgsz=args.imgsz,
        quantize=args.quantize,
        nms=not args.no_nms,           # Note: flag inverts boolean
        benchmark=not args.no_benchmark,  # Note: flag inverts boolean
    )


# ==============================================================================
# SCRIPT ENTRY POINT
# ==============================================================================

if __name__ == '__main__':
    main()
