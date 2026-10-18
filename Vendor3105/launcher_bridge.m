#import "launcher_bridge.h"
#import <dlfcn.h>
#import <objc/message.h>

typedef id (*BolaMsgSend0)(id, SEL);
typedef void (*BolaMsgSend2)(id, SEL, id);

BOOL BolaOpenApplication(NSString *bundleID) {
    if (bundleID.length == 0) return NO;

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
