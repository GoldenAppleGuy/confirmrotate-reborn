#!/bin/bash
# Builds ConfirmRotate Reborn for both package schemes into packages/:
#   rootless (iphoneos-arm64, /var/jb) and rootful (iphoneos-arm, /).
# Uses $THEOS (default /opt/theos). Compiler overrides (TARGET_CC etc.) are passed through.
set -e
cd "$(dirname "$0")"
export THEOS="${THEOS:-/opt/theos}"
rm -rf packages
make clean >/dev/null
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
make clean >/dev/null
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=
ls -1 packages
