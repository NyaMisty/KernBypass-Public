ARCHS = arm64 arm64e
#TARGET := iphone:clang:14.3:7.0

include $(THEOS)/makefiles/common.mk

USE_LIBKRW = 1

SUBPROJECT_NAME = kernelhelper
LIBRARY_NAME = kernelhelper
LIB_DIR := lib

kernelhelper_FILES = kernel.m
kernelhelper_CFLAGS = -fobjc-arc
kernelhelper_FRAMEWORKS = IOKit
#kernelhelper_INSTALL_PATH = /usr/local/lib
#kernelhelper_LINKAGE_TYPE = static
#kernelhelper_LDFLAGS = -lcompression
kernelhelper_LIBRARIES = compression

ifdef USE_DIMENTIO
	kernelhelper_FILES += libdimentio.c
	kernelhelper_CFLAGS += -DUSE_DIMENTIO
endif
ifdef USE_LIBKRW
	#kernelhelper_FRAMEWORKS += kernelhelper/libkrw
	kernelhelper_LIBRARIES += krw
	#kernelhelper_LDFLAGS += -L.
	kernelhelper_FILES += libdimentio.c
	kernelhelper_CFLAGS += -DUSE_LIBKRW
endif
ifdef USE_JELBREK_LIB
	#kernelhelper_FILES += libdimentio.c
	kernelhelper_CFLAGS += -DUSE_JELBREK_LIB
endif


ifdef USE_JELBREK_LIB
	#preparerootfs_LDFLAGS = $(LIB_DIR)/jelbrekLib.dylib
	#changerootfs_LDFLAGS = $(LIB_DIR)/jelbrekLib.dylib
	kernelhelper_LDFLAGS += $(LIB_DIR)/jelbrekLib.dylib
endif


include $(THEOS_MAKE_PATH)/subproject.mk
#include $(THEOS_MAKE_PATH)/library.mk

ifdef USE_JELBREK_LIB
internal-stage::
	$(THEOS)/toolchain/linux/iphone/bin/ldid -S./ent.plist $(THEOS_STAGING_DIR)/usr/lib/jelbrekLib.dylib
	cp $(LIB_DIR)/jelbrekLib.dylib $(THEOS_STAGING_DIR)/usr/lib
endif