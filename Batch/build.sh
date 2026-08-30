#!/bin/zsh
set -euo pipefail

batch_dir="${0:A:h}"
repository_root="${batch_dir:h}"
output_path="${1:-$repository_root/.build/phantomstamp-batch}"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
ios_support="$sdk_path/System/iOSSupport"
host_arch="$(uname -m)"

case "$host_arch" in
  arm64|x86_64) ;;
  *)
    echo "Unsupported Mac architecture: $host_arch" >&2
    exit 2
    ;;
esac

mkdir -p "${output_path:h}"

sources=(
  "$batch_dir/BenchmarkWatermarkService.swift"
  "$batch_dir/PhantomStampBatchMain.swift"
  "$repository_root/PhantomStamp/Services/Watermark/WatermarkAlgorithmCore.swift"
  "$repository_root/PhantomStamp/Services/Watermark/Extensions/DataProcessing.swift"
  "$repository_root/PhantomStamp/Services/Watermark/Extensions/DSPTransforms.swift"
  "$repository_root/PhantomStamp/Services/Watermark/Extensions/ExtractionAndVoting.swift"
  "$repository_root/PhantomStamp/Services/Watermark/Extensions/FrequencyEmbedding.swift"
  "$repository_root/PhantomStamp/Services/Watermark/Extensions/GeometricCandidateDetection.swift"
  "$repository_root/PhantomStamp/Services/Watermark/Extensions/GridAlignment.swift"
  "$repository_root/PhantomStamp/Services/Watermark/Extensions/ImageProcessing.swift"
  "$repository_root/PhantomStamp/Services/Watermark/Extensions/Strips.swift"
  "$repository_root/PhantomStamp/Services/Watermark/Extensions/SyncTemplateEmbedding.swift"
  "$repository_root/PhantomStamp/Services/Watermark/Extensions/SyncTemplateExtraction.swift"
  "$repository_root/PhantomStamp/Models/WatermarkDSPModels.swift"
  "$repository_root/PhantomStamp/Utils/BlockEmbedAmplitude.swift"
  "$repository_root/PhantomStamp/Utils/Constants/AppConstants.swift"
  "$repository_root/PhantomStamp/Utils/Constants/Extensions/UserSettings.swift"
  "$repository_root/PhantomStamp/Utils/VarianceGainCurve.swift"
)

xcrun --sdk macosx swiftc \
  -O \
  -parse-as-library \
  -swift-version 5 \
  -target "$host_arch-apple-ios17.0-macabi" \
  -F "$ios_support/System/Library/Frameworks" \
  -L "$ios_support/usr/lib" \
  "${sources[@]}" \
  -o "$output_path"

echo "$output_path"
