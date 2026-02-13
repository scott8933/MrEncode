#!/bin/bash

# png2icns.sh
# Converts a PNG file to .icns format
# Saves both the .icns file AND the .iconset folder with all PNG sizes
# Usage: ./png2icns.sh <input.png> [output-basename]

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
    echo "Usage: $0 <input.png> [output-basename]"
    echo "Example: $0 MyIcon.png"
    echo "Example: $0 /path/to/MyIcon.png"
    echo "Example: $0 MyIcon.png CustomOutput"
    echo ""
    echo "Output files saved in the same directory as the input PNG:"
    echo "  - output.icns (for Info.plist reference)"
    echo "  - output.iconset/ (folder with all PNG sizes for Xcode)"
    exit 1
fi

INPUT="$1"

# Get absolute path of input file
if [[ "$INPUT" != /* ]]; then
    INPUT="$(pwd)/$INPUT"
fi

# Get directory and basename
INPUT_DIR=$(dirname "$INPUT")
INPUT_BASENAME=$(basename "$INPUT" .png)

# Determine output basename
if [ $# -ge 2 ]; then
    OUTPUT_BASENAME="$2"
else
    OUTPUT_BASENAME="$INPUT_BASENAME"
fi

OUTPUT_ICNS="${INPUT_DIR}/${OUTPUT_BASENAME}.icns"
OUTPUT_ICONSET="${INPUT_DIR}/${OUTPUT_BASENAME}.iconset"

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

echo -e "${GREEN}Converting ${INPUT_BASENAME}.png to .icns + .iconset...${NC}"
echo -e "${BLUE}Input:  $INPUT${NC}"
echo -e "${BLUE}Output: $OUTPUT_ICNS${NC}"
echo -e "${BLUE}        $OUTPUT_ICONSET/${NC}"

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

# Create/recreate the iconset directory
if [ -d "$OUTPUT_ICONSET" ]; then
    echo -e "${YELLOW}Removing existing iconset...${NC}"
    rm -rf "$OUTPUT_ICONSET"
fi

mkdir -p "$OUTPUT_ICONSET"

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
    output_path="${OUTPUT_ICONSET}/${filename}"
    
    if sips -z $size $size "$INPUT" --out "$output_path" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} ${filename} (${size}×${size})"
        ((SUCCESS_COUNT++))
    else
        echo -e "  ${YELLOW}✗${NC} Failed: ${filename}"
    fi
done

if [ $SUCCESS_COUNT -eq 0 ]; then
    echo -e "${RED}Error: Failed to generate any icon sizes${NC}"
    rm -rf "$OUTPUT_ICONSET"
    exit 1
fi

echo ""
echo -e "${GREEN}Successfully generated $SUCCESS_COUNT of ${#SIZE_SPECS[@]} sizes${NC}"

# Convert iconset to icns
echo ""
echo "Converting to .icns..."
if iconutil -c icns "$OUTPUT_ICONSET" -o "$OUTPUT_ICNS" 2>/dev/null; then
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ SUCCESS!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}Created:${NC}"
    
    # Show .icns file
    ICNS_SIZE=$(du -h "$OUTPUT_ICNS" | cut -f1)
    echo -e "  ${GREEN}✓${NC} $OUTPUT_ICNS (${ICNS_SIZE})"
    
    # Show iconset folder
    ICONSET_COUNT=$(ls -1 "$OUTPUT_ICONSET" | wc -l | tr -d ' ')
    echo -e "  ${GREEN}✓${NC} $OUTPUT_ICONSET/ (${ICONSET_COUNT} files)"
    
    # List iconset contents
    echo ""
    echo "Iconset contents:"
    ls -lh "$OUTPUT_ICONSET" | grep "\.png$" | awk '{printf "  %s (%s)\n", $9, $5}'
    
    echo ""
    echo -e "${BLUE}Usage in Xcode:${NC}"
    echo "  1. Drag ${OUTPUT_BASENAME}.iconset folder into Xcode project"
    echo "  2. Or drag individual PNGs from iconset into Asset Catalog"
    echo "  3. Reference in Info.plist as: ${OUTPUT_BASENAME}"
    echo ""
    echo -e "${BLUE}Quick actions:${NC}"
    echo "  Preview .icns:  open -a Preview '$OUTPUT_ICNS'"
    echo "  Show in Finder: open -R '$OUTPUT_ICNS'"
    
    exit 0
else
    echo -e "${RED}Error: iconutil conversion failed${NC}"
    echo "Iconset contents:"
    ls -lh "$OUTPUT_ICONSET"
    exit 1
fi