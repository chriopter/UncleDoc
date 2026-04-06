#!/bin/sh

set -eu

PROJECT_PATH="UncleDoc.xcodeproj"
SCHEME_NAME="UncleDoc"

echo "Running Xcode Cloud post-clone setup for ${SCHEME_NAME}"
xcodebuild -version

if [ ! -f "${PROJECT_PATH}/xcshareddata/xcschemes/${SCHEME_NAME}.xcscheme" ]; then
    echo "error: Shared scheme ${SCHEME_NAME} is missing."
    exit 1
fi

xcodebuild \
    -resolvePackageDependencies \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME_NAME}"

echo "Post-clone setup finished"
