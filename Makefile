ARCHS = arm64 arm64e
DEBUG = 0
FINALPACKAGE = 1

TARGET := iphone:clang:14.3:12.1.2
export TARGET
MIN_IOS_SDK_VERSION = 7.0

#THEOS_DEVICE_IP = localhost -p 2222

TOOL_NAME = preparerootfs changerootfs rawmount setmntflag mksparsedmg

preparerootfs_FILES = preparerootfs.m vnode_utils.c
#preparerootfs_FILES += libdimentio.c
#preparerootfs_CFLAGS = -objc-arc -D USE_DEV_FAKEVAR
preparerootfs_CFLAGS = -objc-arc -D USE_TMPFS_FAKEVAR -DUSE_HARDLINK
#preparerootfs_CFLAGS = -objc-arc -D USE_TMPFS_FAKEVAR
preparerootfs_FRAMEWORKS = IOKit
preparerootfs_CODESIGN_FLAGS = -Sent.plist
preparerootfs_SUBPROJECTS = kernelhelper
preparerootfs_LDFLAGS = -Lkernelhelper

setmntflag_FILES = setmntflag.m vnode_utils.c
setmntflag_CFLAGS = -objc-arc
setmntflag_FRAMEWORKS = IOKit
setmntflag_CODESIGN_FLAGS = -Sent.plist
setmntflag_SUBPROJECTS = kernelhelper
setmntflag_LDFLAGS = -Lkernelhelper

rawmount_FILES = rawmount.m vnode_utils.c
rawmount_CFLAGS = -objc-arc
rawmount_FRAMEWORKS = IOKit
rawmount_CODESIGN_FLAGS = -Sent.plist
rawmount_SUBPROJECTS = kernelhelper
rawmount_LDFLAGS = -Lkernelhelper

mksparsedmg_FILES = mksparsedmg.m
mksparsedmg_CFLAGS = -objc-arc
mksparsedmg_CODESIGN_FLAGS = -Sent.plist

changerootfs_FILES = changerootfs.m vnode_utils.c
#changerootfs_FILES += libdimentio.c
changerootfs_CFLAGS = -objc-arc -D USE_TMPFS_FAKEVAR
changerootfs_FRAMEWORKS = IOKit
changerootfs_CODESIGN_FLAGS = -Sent.plist
changerootfs_SUBPROJECTS = kernelhelper
changerootfs_LDFLAGS = -Lkernelhelper

SUBPROJECTS += zzzzzzzzznotifychroot
SUBPROJECTS += kernbypassprefs
SUBPROJECTS += kernbypassd
SUBPROJECTS += prerm
SUBPROJECTS += KernBypassdCC
SUBPROJECTS += launchd_hooker

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tool.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

#ifdef USE_JELBREK_LIB
#before-package::
#	$(THEOS)/toolchain/linux/iphone/bin/ldid -S./ent.plist $(THEOS_STAGING_DIR)/usr/lib/jelbrekLib.dylib
#	cp $(LIB_DIR)/jelbrekLib.dylib $(THEOS_STAGING_DIR)/usr/lib
#endif

before-package::
	mkdir -p $(THEOS_STAGING_DIR)/usr/lib/
	cp ./layout/DEBIAN/* $(THEOS_STAGING_DIR)/DEBIAN
	chmod -R 755 $(THEOS_STAGING_DIR)
	chmod 6755 $(THEOS_STAGING_DIR)/usr/bin/kernbypassd
	chmod 666 $(THEOS_STAGING_DIR)/DEBIAN/control

after-package::
	#make clean

after-install::
	#install.exec "sbreload"
