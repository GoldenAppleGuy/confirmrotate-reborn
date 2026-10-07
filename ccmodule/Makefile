TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ConfirmRotateRebornModule
ConfirmRotateRebornModule_FILES = CRModule.m
ConfirmRotateRebornModule_CFLAGS = -fobjc-arc
ConfirmRotateRebornModule_FRAMEWORKS = UIKit
ConfirmRotateRebornModule_PRIVATE_FRAMEWORKS = ControlCenterUIKit
ConfirmRotateRebornModule_LDFLAGS += -F$(THEOS)/sdks/iPhoneOS16.5.sdk/System/Library/PrivateFrameworks
ConfirmRotateRebornModule_INSTALL_PATH = /Library/ControlCenter/Bundles

include $(THEOS_MAKE_PATH)/bundle.mk
