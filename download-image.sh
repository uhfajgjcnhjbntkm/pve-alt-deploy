#!/bin/bash

# Script to download and prepare Alt Workstation image

set -e

IMAGE_URL="https://mega.nz/file/H1YXCCJQ#1gK8XMUOVYkfWKj2Rbloocyve7cq1d2_ahXIao7IiK8"
OUTPUT_DIR="/var/cache/pve-alt-deploy"
IMAGE_NAME="alt-workstation.qcow2"

mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

echo "Downloading Alt Workstation image..."
wget -O "$IMAGE_NAME" "$IMAGE_URL"

echo "Generating checksum..."
sha256sum "$IMAGE_NAME" > "${IMAGE_NAME}.sha256"

echo "Image downloaded successfully:"
ls -lh "$IMAGE_NAME"
cat "${IMAGE_NAME}.sha256"
