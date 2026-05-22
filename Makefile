TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = misd

THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MISDHook

MISDHook_FILES = Tweak.x
MISDHook_CFLAGS = -fobjc-arc -I./headers
MISDHook_PRIVATE_FRAMEWORKS = PacketFilter
MISDHook_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
