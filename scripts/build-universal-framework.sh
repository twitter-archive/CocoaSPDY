#/bin/sh

# This script is used to produce a tarball for release. It will build and assemble in 
# /var/tmp, then move the final tarbal to your desktop. It takes one optional input
# parameter, the version, and must be run from the root CocoaSPDY directory. Examples:
#
# scripts/build-universal-framework.sh 1.1.0
# scripts/build-universal-framework.sh (will default to 0.0.0 version)
#
# kgoodier, 03/2015

set -e

if [ -n "$1" ]; then
  VERSION="$1"
else
  VERSION="0.0.0"
fi

CC=
PRODUCT="CocoaSPDY-${VERSION}"
UNIVERSAL_PATH="/var/tmp/${PRODUCT}"
UNIVERSAL_BUILD_DIR="/var/tmp/${PRODUCT}-build"
IOS_FRAMEWORK_PATH="${UNIVERSAL_BUILD_DIR}/Build/Products/Release-iphoneos/SPDY.framework"
OSX_FRAMEWORK_PATH="${UNIVERSAL_BUILD_DIR}/Build/Products/Release/SPDY.framework"

# Cleanup
rm -rf "${UNIVERSAL_PATH}"
rm -rf "${UNIVERSAL_BUILD_DIR}"

# Build the "SPDY" scheme (frameworks for both platforms)
xcodebuild -project "SPDY.xcodeproj" -configuration "Release" -scheme "SPDY" -derivedDataPath "${UNIVERSAL_BUILD_DIR}"

# Prepare output dir structure
mkdir -p "${UNIVERSAL_PATH}/iphoneos"
mkdir -p "${UNIVERSAL_PATH}/macosx"
cp -fR "${IOS_FRAMEWORK_PATH}" "${UNIVERSAL_PATH}/iphoneos/SPDY.framework"
cp -fR "${OSX_FRAMEWORK_PATH}" "${UNIVERSAL_PATH}/macosx/SPDY.framework"

# Create .tar.gz file
pushd "/var/tmp"
tar -cvzf "${PRODUCT}.tar.gz" "${PRODUCT}"
popd

# Cleanup
rm -rf "${UNIVERSAL_PATH}"
rm -rf "${UNIVERSAL_BUILD_DIR}"

# Move tarball to desktop
mv -f "${UNIVERSAL_PATH}.tar.gz" "${HOME}/Desktop/"
echo "Created ${HOME}/Desktop/${PRODUCT}.tar.gz"

