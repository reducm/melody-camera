#!/bin/bash
# 只构建无个人签名的 Release；模型权重与用户配置不参与打包。
set -euo pipefail
cd "$(dirname "$0")/.."
sdk="${1:-}"
case "$sdk" in
  iphoneos) destination='generic/platform=iOS' ;;
  iphonesimulator) destination='generic/platform=iOS Simulator' ;;
  *) echo '用法：scripts/build-release.sh iphoneos|iphonesimulator' >&2; exit 2 ;;
esac
export GIT_LFS_SKIP_SMUDGE=1
derived="${MELODY_DERIVED_DATA:-$PWD/build/release-$sdk}"
packages="${MELODY_PACKAGES_DIR:-$PWD/.build/xcode-packages}"
output="${MELODY_RELEASE_OUTPUT:-$PWD/artifacts/release}"
mkdir -p "$output"
xcodebuild -resolvePackageDependencies -project MelodyCamera.xcodeproj -scheme MelodyCamera \
  -clonedSourcePackagesDirPath "$packages" -onlyUsePackageVersionsFromResolvedFile
python3 scripts/prepare-runtime.py --packages "$packages"
xcodebuild -project MelodyCamera.xcodeproj -scheme MelodyCamera \
  -configuration Release -sdk "$sdk" -destination "$destination" \
  -derivedDataPath "$derived" -clonedSourcePackagesDirPath "$packages" \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -jobs "${MELODY_BUILD_JOBS:-3}" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM= PRODUCT_BUNDLE_IDENTIFIER=com.melody.camera build
python3 scripts/package-release.py \
  --app "$derived/Build/Products/Release-$sdk/MelodyCamera.app" \
  --sdk "$sdk" --packages "$packages" --output "$output"
