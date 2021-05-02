ARCHS = arm64 arm64e

TWEAK_NAME = zzzzzzzzzNotifyChroot
$(TWEAK_NAME)_FILES = Tweak.x
$(TWEAK_NAME)_CFLAGS = -fobjc-arc
$(TWEAK_NAME)_FRAMEWORKS = UIKit
$(TWEAK_NAME)_CODESIGN_FLAGS = -S../ent.plist

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk