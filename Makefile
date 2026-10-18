# Theos build cho BolaClone (Ubuntu/WSL, không cần Xcode)
#
#   export THEOS=$HOME/theos
#   make package            -> .deb (cài qua Sileo/Filza trên máy jailbreak)
#   make                    -> .theos/_/Applications/BolaClone.app
#   make ipa                -> BolaClone.ipa (kéo thả eSign/TrollStore)
#
# Yêu cầu: Swift toolchain ở $HOME/swift (xem tools/build_linux.sh).

THEOS ?= $(HOME)/theos
TARGET := iphone:clang:16.5:16.0
ARCHS := arm64

# Trên Linux/WSL dùng Swift toolchain tải tay ở ~/swift; trên macOS để trống
# để Theos lấy swiftc từ Xcode.
ifeq ($(shell uname),Linux)
SWIFTBINPATH := $(HOME)/swift/usr/bin
endif

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := BolaClone

BolaClone_FILES := $(shell find Sources -name '*.swift' | sort)
BolaClone_FRAMEWORKS := UIKit SwiftUI Combine AVFoundation Foundation
BolaClone_SWIFT_VERSION := 5

# Trên Linux, SDK Theos chỉ có .swiftinterface (không có binary overlay module),
# nên cross-compile SwiftUI bị chặn ở Dispatch overlay. Trên macOS (Xcode toolchain)
# resource-dir mặc định của Theos đã đúng.
ifeq ($(shell uname),Linux)
SWIFT_IOS_RES ?= $(HOME)/swift-ios-res
BolaClone_SWIFTFLAGS := -resource-dir $(SWIFT_IOS_RES)
BolaClone_LDFLAGS := -L$(SWIFT_IOS_RES)/iphoneos -L$(SYSROOT)/usr/lib/swift
endif

include $(THEOS_MAKE_PATH)/application.mk

.PHONY: ipa
ipa: all
	@rm -rf .theos/ipa Payload BolaClone.ipa
	@mkdir -p .theos/ipa/Payload
	@cp -R ".theos/_/Applications/BolaClone.app" .theos/ipa/Payload/
	@cd .theos/ipa && zip -qry ../../BolaClone.ipa Payload
	@echo "-> $$(pwd)/BolaClone.ipa"
