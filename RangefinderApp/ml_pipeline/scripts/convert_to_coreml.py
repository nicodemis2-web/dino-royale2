#!/usr/bin/env python3
"""
Convert YOLO model to CoreML format.

This script should be run with Python 3.10-3.12 for best compatibility with coremltools.
Python 3.14 has known issues with coremltools native libraries.

Usage:
    # Create a compatible environment
    python3.12 -m venv venv312
    source venv312/bin/activate
    pip install ultralytics coremltools

    # Run conversion
    python scripts/convert_to_coreml.py --model sniperscope/detector_v8/weights/best.pt
"""

import os
import sys
import argparse
import shutil
from pathlib import Path

def main():
    parser = argparse.ArgumentParser(description='Convert YOLO to CoreML')
    parser.add_argument('--model', type=str, required=True, help='Path to .pt model')
    parser.add_argument('--output', type=str, default='models/exports', help='Output directory')
    parser.add_argument('--imgsz', type=int, default=640, help='Image size')
    parser.add_argument('--half', action='store_true', help='FP16 quantization')
    parser.add_argument('--nms', action='store_true', default=True, help='Include NMS')
    args = parser.parse_args()

    # Change to ml_pipeline directory
    script_dir = Path(__file__).parent
    ml_pipeline_dir = script_dir.parent
    os.chdir(ml_pipeline_dir)

    # Create output directory
    output_path = Path(args.output)
    output_path.mkdir(parents=True, exist_ok=True)

    print(f"Loading model: {args.model}")

    from ultralytics import YOLO
    model = YOLO(args.model)

    print(f"Exporting to CoreML (imgsz={args.imgsz}, half={args.half}, nms={args.nms})...")

    try:
        exported_path = model.export(
            format='coreml',
            imgsz=args.imgsz,
            half=args.half,
            nms=args.nms
        )

        print(f"Export successful: {exported_path}")

        # Copy to output directory with standard name
        exported_file = Path(exported_path)
        if exported_file.exists():
            suffix = 'FP16' if args.half else 'FP32'
            final_name = f'SniperScope_Detector_{suffix}.mlpackage'
            final_path = output_path / final_name

            if final_path.exists():
                shutil.rmtree(final_path)
            shutil.copytree(exported_file, final_path)

            print(f"Saved to: {final_path}")

            # Get model size
            size_bytes = sum(f.stat().st_size for f in final_path.rglob('*') if f.is_file())
            print(f"Model size: {size_bytes / (1024*1024):.2f} MB")

    except Exception as e:
        print(f"CoreML export failed: {e}")
        print("\nTroubleshooting:")
        print("1. Make sure you're using Python 3.10-3.12")
        print("2. Try: pip install --upgrade coremltools")
        print("3. On macOS, ensure Xcode command line tools are installed")
        print("\nAlternative: Use the .torchscript model with ONNX->CoreML conversion")
        return 1

    return 0


if __name__ == '__main__':
    sys.exit(main())
