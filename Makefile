TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = misd

THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VPNShare

VPNShare_FILES = Tweak.x
VPNShare_CFLAGS = -fobjc-arc -I./headers
VPNShare_PRIVATE_FRAMEWORKS = PacketFilter
VPNShare_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
