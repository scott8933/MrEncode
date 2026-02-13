#!/bin/bash

# Exit on error
set -e

echo "Starting debug logging cleanup..."

# Step 1: Create backup branch
git checkout -b cleanup-debug-logging
git add .
git commit -m "Checkpoint before debug logging cleanup"

# Step 2: Remove zDebug folder
git rm -r MrEncode/zDebug/
git commit -m "Remove zDebug folder"

# Step 3: Clean up EncodeEngine.swift
sed -i '' '/🧪 EncodeEngine 422 TEST BUILD ACTIVE/d' MrEncode/EncodeCore/EncodeEngine.swift
sed -i '' '/🧪 checkpoint/d' MrEncode/EncodeCore/EncodeEngine.swift
sed -i '' '/🧪 179()/d' MrEncode/EncodeCore/EncodeEngine.swift
sed -i '' '/🧪 191()/d' MrEncode/EncodeCore/EncodeEngine.swift
sed -i '' '/🧪 206)/d' MrEncode/EncodeCore/EncodeEngine.swift
sed -i '' '/❌ Metal42210Converter init failed/d' MrEncode/EncodeCore/EncodeEngine.swift
git add MrEncode/EncodeCore/EncodeEngine.swift
git commit -m "Remove test/checkpoint logging from EncodeEngine"

# Step 4: Clean up Metal42210Converter.swift
sed -i '' '/LOG(/d' MrEncode/EncodeCore/Metal42210Converter.swift
git add MrEncode/EncodeCore/Metal42210Converter.swift
git commit -m "Remove LOG diagnostics from Metal42210Converter"

# Step 5: Remove debug print blocks
sed -i '' '669,671d' MrEncode/Core/AppState.swift
sed -i '' '86,88d' MrEncode/Core/Services/MetadataExtractor.swift
git add MrEncode/Core/AppState.swift MrEncode/Core/Services/MetadataExtractor.swift
git commit -m "Remove debug print blocks"

# Step 6: Remove NSLog statements
sed -i '' '/NSLog.*bootstrapDeadlineLists/d' MrEncode/App/MrEncodeApp.swift
sed -i '' '/NSLog.*RunRequest mode detected/d' MrEncode/App/MrEncodeApp.swift
sed -i '' '/NSLog.*RunRequest preset persisted/d' MrEncode/App/MrEncodeApp.swift
sed -i '' '/NSLog.*Failed to decode/d' MrEncode/App/MrEncodeApp.swift
sed -i '' '/NSLog.*Ingest group/d' MrEncode/App/MrEncodeApp.swift
sed -i '' '/NSLog.*Batch done chime/d' MrEncode/Core/AppCore.swift
sed -i '' '/NSLog.*checkBatchDoneChime/d' MrEncode/Core/AppCore.swift
sed -i '' '/NSLog.*RunRequestLoader/d' MrEncode/Core/RunRequestLoader.swift
sed -i '' '/NSLog.*SoundManager/d' MrEncode/Core/Services/SoundManager.swift
git add MrEncode/App/MrEncodeApp.swift MrEncode/Core/AppCore.swift MrEncode/Core/RunRequestLoader.swift MrEncode/Core/Services/SoundManager.swift
git commit -m "Remove verbose NSLog statements"

# Step 7: Remove debug prints
sed -i '' '/print.*DropletExport/d' MrEncode/Core/AppState.swift
sed -i '' '/print.*Preset.*not found/d' MrEncode/Core/AppCore.swift
sed -i '' '/print.*Using Deadline/d' MrEncode/Core/AppCore.swift
sed -i '' '/print.*MetadataExtractor NCLC/d' MrEncode/Core/Services/MetadataExtractor.swift
sed -i '' '/print.*MODE: Local/d' MrEncode/Core/Services/EncodingService.swift
sed -i '' '/print.*Quality:/d' MrEncode/Core/Services/EncodingService.swift
sed -i '' '/print.*Overlays active/d' MrEncode/Core/Services/EncodingService.swift
sed -i '' '/print.*Global cancel/d' MrEncode/Core/Services/EncodingService.swift
sed -i '' '/print.*Stop during pause/d' MrEncode/Core/Services/EncodingService.swift
sed -i '' '/print.*Cancelling encode/d' MrEncode/Core/Services/EncodingService.swift
git add MrEncode/Core/AppState.swift MrEncode/Core/AppCore.swift MrEncode/Core/Services/MetadataExtractor.swift MrEncode/Core/Services/EncodingService.swift
git commit -m "Remove debug print statements"

echo ""
echo "✅ Automated cleanup complete!"
echo ""
echo "⚠️  MANUAL STEP: Edit MrEncode/Core/AppCommands.swift"
echo "    Remove the line: DebugDropletExporter.export()"
echo ""
echo "Then run: git add MrEncode/Core/AppCommands.swift"
echo "         git commit -m 'Remove DebugDropletExporter call'"
