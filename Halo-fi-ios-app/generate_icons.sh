#!/bin/bash

# Generate placeholder app icons for Halo Fi iOS app
# This script creates basic colored squares as placeholder icons

echo "Generating placeholder app icons for Halo Fi..."

# Create icons directory if it doesn't exist
ICON_DIR="Halo-fi-IOS/Halo-fi-IOS/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ICON_DIR"

# Function to generate a colored square icon
generate_icon() {
    local size=$1
    local filename=$2
    local color=$3
    
    # Use ImageMagick if available, otherwise create a simple colored square
    if command -v convert &> /dev/null; then
        convert -size ${size}x${size} xc:$color "$ICON_DIR/$filename"
        echo "✓ Generated $filename (${size}x${size})"
    else
        # Fallback: create a simple text file with instructions
        echo "Icon: ${size}x${size} - $color background" > "$ICON_DIR/$filename.txt"
        echo "Please replace this with an actual ${size}x${size} PNG icon" >> "$ICON_DIR/$filename.txt"
        echo "✓ Created placeholder for $filename (${size}x${size})"
    fi
}

# Generate all required icon sizes
echo "Creating iPhone icons..."
generate_icon "40x40" "Icon-40.png" "#6366f1"      # 20pt @2x
generate_icon "60x60" "Icon-60.png" "#6366f1"      # 20pt @3x
generate_icon "58x58" "Icon-58.png" "#8b5cf6"      # 29pt @2x
generate_icon "87x87" "Icon-87.png" "#8b5cf6"      # 29pt @3x
generate_icon "80x80" "Icon-80.png" "#a855f7"      # 40pt @2x
generate_icon "120x120" "Icon-120.png" "#a855f7"   # 40pt @3x
generate_icon "120x120" "Icon-120.png" "#c084fc"   # 60pt @2x (reuse)
generate_icon "180x180" "Icon-180.png" "#c084fc"   # 60pt @3x

echo "Creating iPad icons..."
generate_icon "20x20" "Icon-20.png" "#6366f1"      # 20pt @1x
generate_icon "40x40" "Icon-40.png" "#6366f1"      # 20pt @2x (reuse)
generate_icon "29x29" "Icon-29.png" "#8b5cf6"      # 29pt @1x
generate_icon "58x58" "Icon-58.png" "#8b5cf6"      # 29pt @2x (reuse)
generate_icon "40x40" "Icon-40.png" "#a855f7"      # 40pt @1x (reuse)
generate_icon "80x80" "Icon-80.png" "#a855f7"      # 40pt @2x (reuse)
generate_icon "76x76" "Icon-76.png" "#c084fc"      # 76pt @1x
generate_icon "152x152" "Icon-152.png" "#c084fc"   # 76pt @2x
generate_icon "167x167" "Icon-167.png" "#ddd6fe"   # 83.5pt @2x

echo "Creating App Store icon..."
generate_icon "1024x1024" "Icon-1024.png" "#6366f1" # App Store

echo ""
echo "🎉 Icon generation complete!"
echo ""
echo "Next steps:"
echo "1. Replace placeholder icons with your actual Halo Fi app icon"
echo "2. Make sure all icons are PNG format"
echo "3. Try uploading to TestFlight again"
echo ""
echo "Note: If you don't have ImageMagick installed, you'll need to create"
echo "actual PNG icons manually or install ImageMagick with:"
echo "  brew install imagemagick"
