#!/bin/bash
# Download datasets for SniperScope training

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(dirname "$SCRIPT_DIR")"
DATASETS_DIR="$PIPELINE_DIR/datasets"

echo "=============================================="
echo "SniperScope Dataset Downloader"
echo "=============================================="
echo ""
echo "Datasets directory: $DATASETS_DIR"
echo ""

# Create directories
mkdir -p "$DATASETS_DIR/visdrone_raw"
mkdir -p "$DATASETS_DIR/depth"

# Function to download with progress
download_file() {
    local url=$1
    local output=$2

    if [ -f "$output" ]; then
        echo "File already exists: $output"
        return 0
    fi

    echo "Downloading: $url"
    curl -L -# -o "$output" "$url"
    echo "Downloaded: $output"
}

# VisDrone Dataset
echo ""
echo "=== VisDrone Dataset ==="
echo ""

VISDRONE_TRAIN_URL="https://github.com/VisDrone/VisDrone-Dataset/releases/download/v1.0/VisDrone2019-DET-train.zip"
VISDRONE_VAL_URL="https://github.com/VisDrone/VisDrone-Dataset/releases/download/v1.0/VisDrone2019-DET-val.zip"

cd "$DATASETS_DIR/visdrone_raw"

# Download training set
if [ ! -d "VisDrone2019-DET-train" ]; then
    download_file "$VISDRONE_TRAIN_URL" "VisDrone2019-DET-train.zip"
    echo "Extracting training set..."
    unzip -q "VisDrone2019-DET-train.zip"
    rm "VisDrone2019-DET-train.zip"
else
    echo "VisDrone training set already extracted"
fi

# Download validation set
if [ ! -d "VisDrone2019-DET-val" ]; then
    download_file "$VISDRONE_VAL_URL" "VisDrone2019-DET-val.zip"
    echo "Extracting validation set..."
    unzip -q "VisDrone2019-DET-val.zip"
    rm "VisDrone2019-DET-val.zip"
else
    echo "VisDrone validation set already extracted"
fi

# Vehicle Dimensions Database
echo ""
echo "=== Vehicle Dimensions Database ==="
echo ""

cd "$DATASETS_DIR"
if [ ! -d "us-car-models-data" ]; then
    echo "Cloning US car models data..."
    git clone https://github.com/abhionlyone/us-car-models-data.git
else
    echo "US car models data already exists"
fi

# Summary
echo ""
echo "=============================================="
echo "Download Complete!"
echo "=============================================="
echo ""
echo "Downloaded datasets:"
echo "  - VisDrone2019-DET-train"
echo "  - VisDrone2019-DET-val"
echo "  - US Car Models Data"
echo ""
echo "Next steps:"
echo "  1. Run: python scripts/prepare_visdrone.py"
echo "  2. Collect custom field images"
echo "  3. Run: python scripts/train.py"
echo ""
