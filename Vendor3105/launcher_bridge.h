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

NS_ASSUME_NONNULL_END
