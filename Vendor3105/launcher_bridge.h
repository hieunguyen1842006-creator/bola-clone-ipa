//
//  launcher_bridge.h
//
//  Mở app khác bằng LSApplicationWorkspace (MobileCoreServices private framework),
//  cùng cách IPA gốc làm: class LSApplicationWorkspace → defaultWorkspace →
//  openApplicationWithBundleID:. Fallback URL scheme nằm phía Swift.
//

#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

BOOL BolaOpenApplication(NSString *bundleID);

/// Tắt app (LSApplicationWorkspace terminate…). NO nếu máy không cho phép.
BOOL BolaTerminateApplication(NSString *bundleID);

/// Phiên bản app đã cài (LSApplicationProxy.shortVersionString); nil nếu không đọc được.
NSString * _Nullable BolaInstalledAppVersion(NSString *bundleID);

NS_ASSUME_NONNULL_END
