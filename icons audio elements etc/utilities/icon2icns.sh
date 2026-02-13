#!/bin/bash

# icon2icns.sh
# Converts Apple .icon packages to traditional .icns files
# Usage: ./icon2icns.sh <input.icon> [output.icns]

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
    echo "Usage: $0 <input.icon> [output.icns]"
    echo "Example: $0 MyIcon.icon"
    echo "Example: $0 MyIcon.icon CustomOutput.icns"
    exit 1
fi

INPUT="$1"
BASENAME=$(basename "$INPUT" .icon)
OUTPUT="${2:-${BASENAME}.icns}"

# Validate input
if [ ! -e "$INPUT" ]; then
    echo -e "${RED}Error: Input file '$INPUT' does not exist${NC}"
    exit 1
fi

# Check if input is actually a package/directory
if [ ! -d "$INPUT" ]; then
    echo -e "${RED}Error: '$INPUT' is not a package/directory${NC}"
    echo "Expected a .icon package, got a regular file"
    exit 1
fi

echo -e "${GREEN}Converting ${BASENAME}.icon to .icns...${NC}"

# Create temporary iconset directory
ICONSET="${BASENAME}.iconset"
TEMP_DIR=$(mktemp -d)
TEMP_ICONSET="${TEMP_DIR}/${ICONSET}"

mkdir -p "$TEMP_ICONSET"

echo "Searching for PNG files in .icon package..."

# Find all PNG files in the .icon package
PNG_FILES=()
while IFS= read -r -d '' file; do
    PNG_FILES+=("$file")
done < <(find "$INPUT" -name "*.png" -type f -print0)

if [ ${#PNG_FILES[@]} -eq 0 ]; then
    echo -e "${RED}Error: No PNG files found in .icon package${NC}"
    echo -e "${YELLOW}Contents of package:${NC}"
    ls -lR "$INPUT"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo -e "${BLUE}Found ${#PNG_FILES[@]} PNG file(s):${NC}"
for png in "${PNG_FILES[@]}"; do
    echo "  - $(basename "$png")"
done

# Find the largest PNG to use as source
LARGEST_PNG=""
LARGEST_SIZE=0

for png in "${PNG_FILES[@]}"; do
    echo -e "${BLUE}Checking: $(basename "$png")${NC}"
    
    # Try to get file size as fallback
    FILE_SIZE=$(stat -f%z "$png" 2>/dev/null || echo "0")
    
    # Try to get dimensions using sips
    if DIMS=$(sips -g pixelWidth "$png" 2>/dev/null); then
        WIDTH=$(echo "$DIMS" | grep "pixelWidth" | awk '{print $2}')
        
        if [ -n "$WIDTH" ] && [ "$WIDTH" -gt 0 ]; then
            echo "  Dimensions: ${WIDTH}×${WIDTH} (assuming square)"
            
            if [ "$WIDTH" -gt "$LARGEST_SIZE" ]; then
                LARGEST_SIZE=$WIDTH
                LARGEST_PNG="$png"
            fi
        else
            echo -e "${YELLOW}  Could not read dimensions, trying file size...${NC}"
            if [ "$FILE_SIZE" -gt "$LARGEST_SIZE" ]; then
                LARGEST_SIZE=$FILE_SIZE
                LARGEST_PNG="$png"
            fi
        fi
    else
        echo -e "${YELLOW}  sips failed, using file size (${FILE_SIZE} bytes)${NC}"
        if [ "$FILE_SIZE" -gt "$LARGEST_SIZE" ]; then
            LARGEST_SIZE=$FILE_SIZE
            LARGEST_PNG="$png"
        fi
    fi
done

if [ -z "$LARGEST_PNG" ]; then
    echo -e "${RED}Error: Could not determine largest PNG${NC}"
    echo -e "${YELLOW}Attempting to use first PNG as fallback...${NC}"
    LARGEST_PNG="${PNG_FILES[0]}"
fi

echo -e "${GREEN}Using source: $(basename "$LARGEST_PNG")${NC}"

# Verify the source PNG is readable
if ! sips -g pixelWidth "$LARGEST_PNG" &>/dev/null; then
    echo -e "${YELLOW}Warning: Source PNG may be corrupt or unreadable${NC}"
    echo "Attempting conversion anyway..."
fi

# Generate all required icon sizes
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
    
    if sips -z $size $size "$LARGEST_PNG" --out "$output_path" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Generated ${filename} (${size}×${size})"
        ((SUCCESS_COUNT++))
    else
        echo -e "  ${YELLOW}✗${NC} Failed to generate ${filename}"
    fi
done

if [ $SUCCESS_COUNT -eq 0 ]; then
    echo -e "${RED}Error: Failed to generate any icon sizes${NC}"
    echo "This usually means the source PNG is corrupt or in an unsupported format"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo -e "${GREEN}Successfully generated $SUCCESS_COUNT of ${#SIZE_SPECS[@]} sizes${NC}"

# Convert iconset to icns
echo "Converting to .icns..."
if iconutil -c icns "$TEMP_ICONSET" -o "$OUTPUT" 2>/dev/null; then
    echo -e "${GREEN}✓ Success: Created $OUTPUT${NC}"
    
    # Show file info
    SIZE=$(du -h "$OUTPUT" | cut -f1)
    echo "  File size: $SIZE"
    
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