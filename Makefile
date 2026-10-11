THEOS ?= /opt/theos
TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME ?= rootless
INSTALL_TARGET_PROCESSES = SpringBoard
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

# Package architecture follows the scheme: rootless (iphoneos-arm64), roothide (iphoneos-arm64e,
# needs roothide's Theos) or rootful (iphoneos-arm). Build rootful with: make package THEOS_PACKAGE_SCHEME=
ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
THEOS_PACKAGE_ARCH = iphoneos-arm64
else ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
THEOS_PACKAGE_ARCH = iphoneos-arm64e
else
THEOS_PACKAGE_ARCH = iphoneos-arm
endif

TWEAK_NAME = ConfirmRotateReborn
ConfirmRotateReborn_FILES = Tweak.x
ConfirmRotateReborn_CFLAGS = -fobjc-arc -DCR_VERSION=\"$(shell grep '^Version:' control | cut -d' ' -f2)\"
ConfirmRotateReborn_FRAMEWORKS = UIKit QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs ccmodule
include $(THEOS_MAKE_PATH)/aggregate.mk
