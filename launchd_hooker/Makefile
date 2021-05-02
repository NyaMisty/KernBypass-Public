TARGET := iphone:clang:14.3:7.0
INSTALL_TARGET_PROCESSES = runningboardd
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = launchd_hooker

launchd_hooker_FILES = Tweak.x
#launchd_hooker_FRAMEWORKS = libxpc
launchd_hooker_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
