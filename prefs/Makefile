TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ConfirmRotateRebornPrefs
ConfirmRotateRebornPrefs_FILES = CRRootListController.m
ConfirmRotateRebornPrefs_CFLAGS = -fobjc-arc
ConfirmRotateRebornPrefs_FRAMEWORKS = UIKit
ConfirmRotateRebornPrefs_PRIVATE_FRAMEWORKS = Preferences
ConfirmRotateRebornPrefs_LDFLAGS += -F$(THEOS)/sdks/iPhoneOS16.5.sdk/System/Library/PrivateFrameworks
ConfirmRotateRebornPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
