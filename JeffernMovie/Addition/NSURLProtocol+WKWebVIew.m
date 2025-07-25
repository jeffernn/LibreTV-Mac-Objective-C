//Jeffern影视平台 ©Jeffern 2025/7/15

#import "NSURLProtocol+WKWebVIew.h"
#import "HybridNSURLProtocol.h"
#import <WebKit/WebKit.h>
//FOUNDATION_STATIC_INLINE 属于属于runtime范畴，你的.m文件需要频繁调用一个函数,可以用static inline来声明。从SDWebImage从get到的。
FOUNDATION_STATIC_INLINE Class ContextControllerClass() {
    static Class cls;
    if (!cls) {
        cls = [[[WKWebView new] valueForKey:@"browsingContextController"] class];
    }
    return cls;
}

FOUNDATION_STATIC_INLINE SEL UnregisterSchemeSelector() {
    return NSSelectorFromString(@"unregisterSchemeForCustomProtocol:");
}

@implementation NSURLProtocol (WebKitSupport)

static NSString *testScheme = nil;
+ (void)wk_registerScheme:(NSString *)scheme {
    testScheme = scheme;
    [NSURLProtocol registerClass:[HybridNSURLProtocol class]];//这里还是注册了自定义的urlProtocol
#if WK_API_ENABLED
    [WKBrowsingContextController registerSchemeForCustomProtocol:testScheme]; //而且为自定义的protocol这里绑定了scheme
#endif
//    }
}

+ (void)wk_unregisterScheme:(NSString *)scheme {
    Class cls = ContextControllerClass();
    SEL sel = UnregisterSchemeSelector();
    if ([(id)cls respondsToSelector:sel]) {
     // 放弃编辑器警告
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [(id)cls performSelector:sel withObject:scheme];
#pragma clang diagnostic pop
    }
}

@end
