THEOS_MAKE_PATH = $(THEOS)/makefiles
include $(THEOS_MAKE_PATH)/common.mk

APPLICATION_NAME = DisplayPAD
DisplayPAD_FILES = Sources/main.m Sources/AppDelegate.m Sources/DisplayViewController.m Sources/TCPReceiver.m
DisplayPAD_FRAMEWORKS = UIKit AVFoundation CoreMedia VideoToolbox
DisplayPAD_PRIVATE_FRAMEWORKS =
DisplayPAD_CFLAGS = -fobjc-arc
DisplayPAD_ARCHS = arm64
IPHONE_DEPLOYMENT_TARGET = 9.0

include $(THEOS_MAKE_PATH)/application.mk
