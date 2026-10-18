#import "launcher_bridge.h"
#import <dlfcn.h>
#import <objc/message.h>

typedef id (*BolaMsgSend0)(id, SEL);
typedef id (*BolaMsgSend1)(id, SEL, id);
typedef void (*BolaMsgSend2)(id, SEL, id);

static Class BolaWorkspaceClass(void) {
    static Class workspaceClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices",
               RTLD_NOW);
        workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        if (!workspaceClass) {
            dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",
                   RTLD_NOW);
            workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        }
    });
    return workspaceClass;
}

BOOL BolaOpenApplication(NSString *bundleID) {
    if (bundleID.length == 0) return NO;

    Class workspaceClass = BolaWorkspaceClass();
    if (!workspaceClass) return NO;

    SEL defaultSel = NSSelectorFromString(@"defaultWorkspace");
    if (![(id)workspaceClass respondsToSelector:defaultSel]) return NO;
    id workspace = ((BolaMsgSend0)objc_msgSend)((id)workspaceClass, defaultSel);
    if (!workspace) return NO;

    SEL openSel = NSSelectorFromString(@"openApplicationWithBundleID:");
    if (![workspace respondsToSelector:openSel]) return NO;
    ((BolaMsgSend2)objc_msgSend)(workspace, openSel, bundleID);
    return YES;
}

NSString *BolaInstalledAppVersion(NSString *bundleID) {
    if (bundleID.length == 0) return nil;
    BolaWorkspaceClass();

    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    SEL proxySel = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (!proxyClass || ![(id)proxyClass respondsToSelector:proxySel]) {
        return nil;
    }
    id proxy = ((BolaMsgSend1)objc_msgSend)((id)proxyClass, proxySel, bundleID);
    if (!proxy) return nil;

    SEL versionSel = NSSelectorFromString(@"shortVersionString");
    if (![proxy respondsToSelector:versionSel]) {
        versionSel = NSSelectorFromString(@"bundleVersion");
        if (![proxy respondsToSelector:versionSel]) return nil;
    }
    return ((BolaMsgSend0)objc_msgSend)(proxy, versionSel);
}
