#!/bin/bash

# png2icns.sh
# Converts a PNG file to .icns format
# Saves output in the same directory as the input PNG
# Usage: ./png2icns.sh <input.png> [output.icns]

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -lt 1 ]; then
    echo -e "${RED}Error: No input file specified${NC}"
    echo "Usage: $0 <input.png> [output.icns]"
    echo "Example: $0 MyIcon.png"
    echo "Example: $0 /path/to/MyIcon.png"
    echo "Example: $0 MyIcon.png CustomOutput.icns"
    echo ""
    echo "Output is saved in the same directory as the input PNG"
    exit 1
fi

INPUT="$1"

# Get absolute path of input file
if [[ "$INPUT" != /* ]]; then
    INPUT="$(pwd)/$INPUT"
fi

# Get directory and basename
INPUT_DIR=$(dirname "$INPUT")
BASENAME=$(basename "$INPUT" .png)

# Determine output path
if [ $# -ge 2 ]; then
    # Custom output name provided
    OUTPUT_NAME="$2"
    # If it's just a filename (no path), put it in same dir as input
    if [[ "$OUTPUT_NAME" != */* ]]; then
        OUTPUT="${INPUT_DIR}/${OUTPUT_NAME}"
    else
        # Full path provided, use as-is
        OUTPUT="$OUTPUT_NAME"
    fi
else
    # Default: same directory as input, same basename
    OUTPUT="${INPUT_DIR}/${BASENAME}.icns"
fi

# Convert OUTPUT to absolute path if relative
if [[ "$OUTPUT" != /* ]]; then
    OUTPUT="$(cd "$(dirname "$OUTPUT")" && pwd)/$(basename "$OUTPUT")"
fi

# Validate input
if [ ! -f "$INPUT" ]; then
    echo -e "${RED}Error: Input file '$INPUT' does not exist${NC}"
    exit 1
fi

# Check if input is a PNG
if ! file "$INPUT" | grep -q "PNG image data"; then
    echo -e "${RED}Error: '$INPUT' is not a PNG file${NC}"
    exit 1
fi

echo -e "${GREEN}Converting ${BASENAME}.png to .icns...${NC}"
echo -e "${BLUE}Input:  $INPUT${NC}"
echo -e "${BLUE}Output: $OUTPUT${NC}"

# Get source image dimensions
echo ""
echo "Reading source image..."
if DIMS=$(sips -g pixelWidth -g pixelHeight "$INPUT" 2>/dev/null); then
    WIDTH=$(echo "$DIMS" | grep "pixelWidth" | awk '{print $2}')
    HEIGHT=$(echo "$DIMS" | grep "pixelHeight" | awk '{print $2}')
    
    if [ -z "$WIDTH" ] || [ -z "$HEIGHT" ]; then
        echo -e "${RED}Error: Could not read image dimensions${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Source dimensions: ${WIDTH}×${HEIGHT}${NC}"
    
    # Warn if not square
    if [ "$WIDTH" != "$HEIGHT" ]; then
        echo -e "${YELLOW}⚠ Warning: Image is not square. Output may be distorted.${NC}"
        echo "  Recommended: Use a square image for best results"
    fi
    
    # Warn if too small
    MIN_SIZE=$((WIDTH < HEIGHT ? WIDTH : HEIGHT))
    if [ "$MIN_SIZE" -lt 512 ]; then
        echo -e "${YELLOW}⚠ Warning: Image is ${MIN_SIZE}×${MIN_SIZE}. Larger sizes (512×512 or 1024×1024) recommended.${NC}"
    fi
else
    echo -e "${RED}Error: Could not read image with sips${NC}"
    exit 1
fi

# Create temporary iconset directory
ICONSET="${BASENAME}.iconset"
TEMP_DIR=$(mktemp -d)
TEMP_ICONSET="${TEMP_DIR}/${ICONSET}"

mkdir -p "$TEMP_ICONSET"

# Generate all required icon sizes
echo ""
echo "Generating icon sizes..."

declare -a SIZE_SPECS=(
    "icon_16x16.png:16"
    "icon_16x16@2x.png:32"
    "icon_32x32.png:32"
    "icon_32x32@2x.png:64"
    "icon_128x128.png:128"
    "icon_128x128@2x.png:256"
    "icon_256x256.png:256"
    "icon_256x256@2x.png:512"
    "icon_512x512.png:512"
    "icon_512x512@2x.png:1024"
)

SUCCESS_COUNT=0

for spec in "${SIZE_SPECS[@]}"; do
    filename="${spec%:*}"
    size="${spec#*:}"
    output_path="${TEMP_ICONSET}/${filename}"
    
    if sips -z $size $size "$INPUT" --out "$output_path" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} ${filename} (${size}×${size})"
        ((SUCCESS_COUNT++))
    else
        echo -e "  ${YELLOW}✗${NC} Failed: ${filename}"
    fi
done

if [ $SUCCESS_COUNT -eq 0 ]; then
    echo -e "${RED}Error: Failed to generate any icon sizes${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo ""
echo -e "${GREEN}Successfully generated $SUCCESS_COUNT of ${#SIZE_SPECS[@]} sizes${NC}"

# Convert iconset to icns
echo ""
echo "Converting to .icns..."
if iconutil -c icns "$TEMP_ICONSET" -o "$OUTPUT" 2>/dev/null; then
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ SUCCESS!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}Created: $OUTPUT${NC}"
    
    # Show file info
    SIZE=$(du -h "$OUTPUT" | cut -f1)
    echo -e "File size: $SIZE"
    
    # Show directory contents
    echo ""
    echo "Files in output directory:"
    ls -lh "$INPUT_DIR"/*.icns 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
    
    echo ""
    echo "Quick actions:"
    echo -e "  ${BLUE}Preview:${NC}  open -a Preview '$OUTPUT'"
    echo -e "  ${BLUE}Finder:${NC}   open -R '$OUTPUT'"
    
    # Clean up
    rm -rf "$TEMP_DIR"
    exit 0
else
    echo -e "${RED}Error: iconutil conversion failed${NC}"
    echo "Iconset contents:"
    ls -lh "$TEMP_ICONSET"
    rm -rf "$TEMP_DIR"
    exit 1
fi