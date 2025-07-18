//Jeffern影视平台 ©Jeffern 2025/7/15

#import "HLHomeViewController.h"
#import "NSView+ZCAddition.h"
#import <WebKit/WebKit.h>
#import "NSString+HLAddition.h"
#import "HLCollectionViewItem.h"
#import "AppDelegate.h"
#import <Foundation/Foundation.h>
#import <IOKit/pwr_mgt/IOPMLib.h>

#define HISTORY_PATH [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/JeffernMovie/history.json"]
#define SESSION_STATE_KEY @"HLHomeViewController_LastSessionURL"

#pragma mark ----



#define NSCollectionViewWidth   75
#define NSCollectionViewHeight  50
#define NSTextViewTips @"[{}]"

typedef enum : NSUInteger {
    EditType_VIP,
    EditType_Platform,
} EditType;

#define ChromeUserAgent @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/107.0.0.0 Safari/537.36"

@interface HLHomeViewController()<WKNavigationDelegate, WKUIDelegate, NSCollectionViewDataSource, NSCollectionViewDelegate, WKScriptMessageHandler>{
    BOOL isLoading;
    BOOL isChanged;
    WKWebViewConfiguration *secondConfiguration;
    IOPMAssertionID _assertionID;
}

@property (nonatomic, strong) WKWebView         *webView;
@property (nonatomic, strong) NSMutableArray    *modelsArray;
@property (nonatomic, strong) NSMutableArray    *buttonsArray;
@property (nonatomic, strong) NSString          *currentUrl;
@property (nonatomic, strong) NSCollectionView  *collectionView;
@property (nonatomic, strong) NSScrollView      *scrollView;
@property (nonatomic, strong) NSWindow          *secondWindow; // 第二弹窗
@property (nonatomic, strong) WKWebView         *secondWebView;// 第二个弹窗的webview
@property (nonatomic, strong) NSTextField *emptyTipsLabel;
@property (nonatomic, strong) NSTextField *loadingTipsLabel; // 新增：加载提示标签

@end;

@implementation HLHomeViewController

- (void)dealloc{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self disablePreventSleep];
}

- (void)viewDidLayout{
    [super viewDidLayout];
    self.webView.frame = self.view.bounds; // 让webview全屏
}

- (void)setIsFullScreen:(BOOL)isFullScreen{
    _isFullScreen = isFullScreen;
    
    [self.view setNeedsLayout:YES];
}

- (void)viewDidLoad {
    [super viewDidLoad];
   
    self.view.layer.backgroundColor = NSColor.lightGrayColor.CGColor;
    [self.view setNeedsDisplay:YES];
    
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.preferences.plugInsEnabled = YES;
    configuration.preferences.javaEnabled = YES;
    if (@available(macOS 10.12, *)) {
        configuration.userInterfaceDirectionPolicy = WKUserInterfaceDirectionPolicySystem;
    }
    if (@available(macOS 10.11, *)) {
        configuration.allowsAirPlayForMediaPlayback = YES;
    }
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = YES;
    configuration.applicationNameForUserAgent = ChromeUserAgent;
    
    // 新增：添加clearHistory的JS消息处理
    WKUserContentController *userContentController = [[WKUserContentController alloc] init];
    [userContentController addScriptMessageHandler:self name:@"clearHistory"];
    configuration.userContentController = userContentController;
    
    self.webView = [self createWebViewWithConfiguration:configuration];
    [self.view addSubview:self.webView];
    
    [self showEmptyTipsIfNeeded];

    // 监听菜单切换内置影视等通知
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleChangeUserCustomSiteURLNotification:) name:@"ChangeUserCustomSiteURLNotification" object:nil];

    // 智能预加载常用站点
    [self preloadFrequentlyUsedSites];
    // 启用防止休眠/锁屏
    [self enablePreventSleep];
    // 恢复上次会话
    [self restoreSessionState];
}

// 新增，确保弹窗在主窗口显示后弹出
- (void)viewDidAppear {
    [super viewDidAppear];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self promptForCustomSiteURLAndLoadIfNeeded];
        });
    });
}

- (void)handleChangeUserCustomSiteURLNotification:(NSNotification *)notification {
    NSString *url = notification.object;
    if (url && [url isKindOfClass:[NSString class]]) {
        [self loadUserCustomSiteURL:url];
        [self showEmptyTipsIfNeeded];
    } else {
        // object为nil时，弹出填写窗口
        [self changeUserCustomSiteURL:nil];
    }
}

- (WKWebView *)currentWebView {
    if (self.secondWindow.isVisible) {
        return self.secondWebView;
    } else {
        return self.webView;
    }
}

- (void)configurationDefaultData{
  
}

- (void)createButtonsForData{
    // 不添加任何按钮
    [self.modelsArray removeAllObjects];
    [self.collectionView reloadData];
    for (NSButton *button in self.buttonsArray) {
        [button removeFromSuperview];
    }
    [self.buttonsArray removeAllObjects];
    [self.view setNeedsLayout:YES];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSString *requestUrl = navigationAction.request.URL.absoluteString;
    NSString *currentUrl = webView.URL.absoluteString;
    // 只在历史记录页面跳转到http/https时显示“正在加载中”
    if ([currentUrl containsString:@"history_rendered.html"] &&
        ([requestUrl hasPrefix:@"http://"] || [requestUrl hasPrefix:@"https://"])) {
        if (!self.loadingTipsLabel) {
            NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 400, 40)];
            label.stringValue = @"正在加载中...";
            label.alignment = NSTextAlignmentCenter;
            label.font = [NSFont boldSystemFontOfSize:28];
            label.textColor = [NSColor whiteColor];
            label.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.7];
            label.editable = NO;
            label.bezeled = NO;
            label.drawsBackground = YES;
            label.selectable = NO;
            label.wantsLayer = YES;
            label.layer.cornerRadius = 16;
            label.layer.masksToBounds = YES;
            label.translatesAutoresizingMaskIntoConstraints = NO;
            [self.view addSubview:label];
            [NSLayoutConstraint activateConstraints:@[
                [label.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
                [label.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
                [label.widthAnchor constraintEqualToConstant:400],
                [label.heightAnchor constraintEqualToConstant:40]
            ]];
            self.loadingTipsLabel = label;
        }
        self.loadingTipsLabel.hidden = NO;
    }
    // 其它逻辑不变
    if (navigationAction.request.URL.absoluteString.length > 0) {
        
        // 拦截广告
        if ([requestUrl containsString:@"ynjczy.net"] ||
            [requestUrl containsString:@"ylbdtg.com"] ||
            [requestUrl containsString:@"662820.com"] ||
            [requestUrl containsString:@"api.vparse.org"] ||
            [requestUrl containsString:@"hyysvip.duapp.com"] ||
            [requestUrl containsString:@"f.qcwzx.net.cn"] ||
            [requestUrl containsString:@"adx.dlads.cn"] ||
            [requestUrl containsString:@"dlads.cn"] ||
            [requestUrl containsString:@"wuo.8h2x.com"]||
            [requestUrl containsString:@"strip.alicdn.com"]
            ) {
            decisionHandler(WKNavigationActionPolicyCancel);
            return;
        }

        if ([requestUrl hasSuffix:@".m3u8"]) {
           
        }
        else {
       
        }
        
        NSLog(@"request.URL.absoluteString = %@",requestUrl);
        
        if ([requestUrl hasPrefix:@"https://aweme.snssdk.co"] || [requestUrl hasPrefix:@"http://aweme.snssdk.co"]) {
            decisionHandler(WKNavigationActionPolicyCancel);
         
            return;
        }
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures{
    NSString *fromUrl = webView.URL.absoluteString;
    NSString *toUrl = navigationAction.request.URL.absoluteString;
    // 如果是从历史记录页面跳转，直接在主WebView打开，不新建窗口
    if ([fromUrl containsString:@"history_rendered.html"] &&
        ([toUrl hasPrefix:@"http://"] || [toUrl hasPrefix:@"https://"])) {
        [webView loadRequest:navigationAction.request];
        return nil;
    }
    if([navigationAction.request.URL.absoluteString isEqualToString:@"about:blank"]) {
        return nil;
    }
    
    secondConfiguration = configuration;
    [self.secondWindow close];
    
    NSUInteger windowStyleMask = NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskTitled;
    NSWindow *keyWindow = NSApplication.sharedApplication.keyWindow;
    NSWindow *secondWindow = [[NSWindow alloc] initWithContentRect:keyWindow.frame styleMask:windowStyleMask backing:NSBackingStoreBuffered defer:NO];
    
    WKWebView *secondWebView = [self createWebViewWithConfiguration:configuration];
    [secondWindow setContentView:secondWebView];
    [secondWindow makeKeyAndOrderFront:self];

    AppDelegate *delegate = (id)[NSApplication sharedApplication].delegate;
    [delegate.windonwArray addObject:secondWindow];
    
    [secondWebView loadRequest:navigationAction.request];
    self.secondWebView = secondWebView;
    self.secondWindow = secondWindow;
    
    NSLog(@"navigationAction.request =%@",navigationAction.request);
    
    return secondWebView;
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(null_unspecified WKNavigation *)navigation
{
    // 已通过WKUserScript全局注入隐藏滚动条，无需再手动注入
    if (self.loadingTipsLabel) {
        self.loadingTipsLabel.hidden = YES;
    }
    // 自动登录Emby（https://dongman.theluyuan.com/）
    NSString *currentURL = webView.URL.absoluteString;
    if ([currentURL hasPrefix:@"https://dongman.theluyuan.com"]) {
        NSString *js = @"var timer=setInterval(function(){\n"
        "var form = document.querySelector('form');\n"
        "var userInput = document.querySelector('input[label=\"用户名\"],input[placeholder*=\"用户名\"],input[type=\"text\"]');\n"
        "var passInput = document.querySelector('input[label=\"密码\"],input[placeholder*=\"密码\"],input[type=\"password\"]');\n"
        "if(userInput&&passInput){\n"
        "userInput.focus();\n"
        "userInput.value='guser';\n"
        "userInput.dispatchEvent(new Event('input', {bubbles:true}));\n"
        "userInput.dispatchEvent(new Event('change', {bubbles:true}));\n"
        "passInput.focus();\n"
        "passInput.value='guser';\n"
        "passInput.dispatchEvent(new Event('input', {bubbles:true}));\n"
        "passInput.dispatchEvent(new Event('change', {bubbles:true}));\n"
        "passInput.blur();\n"
        "}\n"
        "if(form&&userInput&&passInput){\n"
        "try{\n"
        "form.dispatchEvent(new Event('submit', {bubbles:true,cancelable:true}));\n"
        "form.requestSubmit ? form.requestSubmit() : form.submit();\n"
        "}catch(e){form.submit();}\n"
        "clearInterval(timer);\n"
        "}\n"
        "}, 300);";
        [webView evaluateJavaScript:js completionHandler:^(id _Nullable result, NSError * _Nullable error) {
            if (error) {
                NSLog(@"自动登录Emby注入JS出错: %@", error);
            }
        }];
    }
    // 获取网页标题并存入历史记录
    NSString *currentUrl = webView.URL.absoluteString;
    [webView evaluateJavaScript:@"document.title" completionHandler:^(id _Nullable title, NSError * _Nullable error) {
        if (currentUrl.length > 0 && [title isKindOfClass:[NSString class]] && ((NSString *)title).length > 0) {
            [self addHistoryWithName:title url:currentUrl];
        } else if (currentUrl.length > 0) {
            [self addHistoryWithName:currentUrl url:currentUrl];
        }
    }];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(null_unspecified WKNavigation *)navigation withError:(NSError *)error
{
    if (self.loadingTipsLabel) {
        self.loadingTipsLabel.hidden = YES;
    }
}


- (void)jeffernMovieCurrentApiDidChange:(NSNotification *)notification{
    [self.currentWebView evaluateJavaScript:@"document.location.href" completionHandler:^(NSString * _Nullable url, NSError * _Nullable error) {
        if (self.currentUrl == nil) {
            self.currentUrl = url;
        }
     
    }];
}


- (void)jeffernMovieDidCopyCurrentURL:(NSNotification *)notification{
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:self.currentWebView.URL.absoluteString forType:NSPasteboardTypeString];
}

- (void)jeffernMovieGoBackCurrentURL:(NSNotification *)notification{
    if ([self.currentWebView canGoBack]) {
        [self.currentWebView goBack];
    }
}

- (void)jeffernMovieGoForwardCurrentURL:(NSNotification *)notification{
    if ([self.currentWebView canGoForward]) {
        [self.currentWebView goForward];
    }
}

#pragma mark - Create

- (WKWebView *)createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration {
    WKUserContentController *userContentController = [[WKUserContentController alloc] init];
    // 注入隐藏滚动条的JS
    NSString *js = @"(function hideScrollbarsAllFrames(){\
        function injectStyle(doc){\
            if(!doc) return;\
            var style = doc.getElementById('hide-scrollbar-style');\
            if(!style){\
                style = doc.createElement('style');\
                style.id = 'hide-scrollbar-style';\
                style.innerHTML = '::-webkit-scrollbar{display:none !important;}';\
                doc.head.appendChild(style);\
            }\
        }\
        function injectAllFrames(win){\
            try{\
                injectStyle(win.document);\
            }catch(e){}\
            if(win.frames){\
                for(var i=0;i<win.frames.length;i++){\
                    try{\
                        injectAllFrames(win.frames[i]);\
                    }catch(e){}\
                }\
            }\
        }\
        injectAllFrames(window);\
        var observer = new MutationObserver(function(){\
            injectAllFrames(window);\
        });\
        observer.observe(document, {childList:true, subtree:true});\
    })();";
    WKUserScript *userScript = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:NO];
    [userContentController addUserScript:userScript];

    // 只保留最右下角“+”按钮的注入，尺寸恢复为原来大小
    NSString *globalBtnJS = @"(function(){\
        var allowDomains = ['yanetflix.com','omofun2.xyz','ddys.pro','duonaovod.com','hainatv.net','honghuli.com'];\
        var host = location.host;\
        var allow = false;\
        for(var i=0;i<allowDomains.length;i++){\
            if(host.indexOf(allowDomains[i])!==-1){ allow=true; break; }\
        }\
        if(!allow) return;\
        if(document.querySelector('.jeffern-global-fullscreen-btn')) return;\
        var btn = document.createElement('button');\
        btn.className = 'jeffern-global-fullscreen-btn';\
        btn.innerText = '+';\
        btn.style.position = 'fixed';\
        btn.style.right = '0px';\
        btn.style.bottom = '0px';\
        btn.style.zIndex = '2147483647';\
        btn.style.background = 'rgba(255,0,0,0.8)';\
        btn.style.color = 'white';\
        btn.style.border = 'none';\
        btn.style.padding = '520px 3px';\
        btn.style.borderRadius = '8px 0 0 0';\
        btn.style.cursor = 'pointer';\
        btn.style.fontSize = '20px';\
        btn.style.fontWeight = 'bold';\
        btn.style.boxShadow = '0 2px 8px rgba(0,0,0,0.2)';\
        btn.style.opacity = '0';\
        btn.style.pointerEvents = 'auto';\
        var hideTimer = null;\
        var autoHideTimer = null;\
        function showBtn(){\
            btn.style.opacity = '1';\
            if(hideTimer){ clearTimeout(hideTimer); hideTimer = null; }\
            if(autoHideTimer){ clearTimeout(autoHideTimer); autoHideTimer = null; }\
            autoHideTimer = setTimeout(function(){ btn.style.opacity = '0'; }, 1000);\
        }\
        function hideBtn(){\
            btn.style.opacity = '0';\
            if(autoHideTimer){ clearTimeout(autoHideTimer); autoHideTimer = null; }\
        }\
        btn.onmouseenter = function(){\
            showBtn();\
        };\
        btn.onmouseleave = function(){\
            if(autoHideTimer){ clearTimeout(autoHideTimer); autoHideTimer = null; }\
            autoHideTimer = setTimeout(function(){ btn.style.opacity = '0'; }, 1000);\
        };\
        document.addEventListener('mousemove', function(e){\
            var winWidth = window.innerWidth;\
            if(winWidth - e.clientX <= 20){\
                showBtn();\
            }\
        });\
        btn.onclick = function(){\
            var iframes = Array.from(document.querySelectorAll('iframe'));\
            if(iframes.length===0){ alert('未找到iframe播放器'); return; }\
            var maxIframe = iframes[0];\
            var maxArea = 0;\
            for(var i=0;i<iframes.length;i++){\
                var rect = iframes[i].getBoundingClientRect();\
                var area = rect.width*rect.height;\
                if(area>maxArea){ maxArea=area; maxIframe=iframes[i]; }\
            }\
            var target = maxIframe;\
            if(!target._isFullscreen){\
                target._originParent = target.parentElement;\
                target._originNext = target.nextSibling;\
                target._originStyle = {\
                    position: target.style.position,\
                    zIndex: target.style.zIndex,\
                    left: target.style.left,\
                    top: target.style.top,\
                    width: target.style.width,\
                    height: target.style.height,\
                    background: target.style.background\
                };\
                document.body.appendChild(target);\
                target.style.position = 'fixed';\
                target.style.zIndex = '2147483646';\
                target.style.left = '0';\
                target.style.top = '0';\
                target.style.width = '100vw';\
                target.style.height = '100vh';\
                target.style.background = 'black';\
                target._isFullscreen = true;\
                btn.innerText = '+';\
                window.scrollTo(0,0);\
            }else{\
                if(target._originParent){\
                    if(target._originNext && target._originNext.parentElement===target._originParent){\
                        target._originParent.insertBefore(target, target._originNext);\
                    }else{\
                        target._originParent.appendChild(target);\
                    }\
                }\
                if(target._originStyle){\
                    target.style.position = target._originStyle.position;\
                    target.style.zIndex = target._originStyle.zIndex;\
                    target.style.left = target._originStyle.left;\
                    target.style.top = target._originStyle.top;\
                    target.style.width = target._originStyle.width;\
                    target.style.height = target._originStyle.height;\
                    target.style.background = target._originStyle.background;\
                }\
                target._isFullscreen = false;\
                btn.innerText = '+';\
            }\
        };\
        document.body.appendChild(btn);\
        document.addEventListener('keydown', function(ev){\
            var iframes = Array.from(document.querySelectorAll('iframe'));\
            var maxIframe = iframes[0];\
            var maxArea = 0;\
            for(var i=0;i<iframes.length;i++){\
                var rect = iframes[i].getBoundingClientRect();\
                var area = rect.width*rect.height;\
                if(area>maxArea){ maxArea=area; maxIframe=iframes[i]; }\
            }\
            var target = maxIframe;\
            if(ev.key==='Escape' && target && target._isFullscreen){\
                btn.onclick();\
            }\
        });\
    })();";
    WKUserScript *globalBtnScript = [[WKUserScript alloc] initWithSource:globalBtnJS injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:NO];
    [userContentController addUserScript:globalBtnScript];
    // 注册clearHistory消息处理
    [userContentController addScriptMessageHandler:self name:@"clearHistory"];
    configuration.userContentController = userContentController;

    WKWebView *webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
    webView.UIDelegate = self;
    webView.allowsBackForwardNavigationGestures = YES;
    webView.navigationDelegate = self;
    [webView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    return webView;
}

- (void)creatgeCollectionView{
    CGRect frame = CGRectMake(0, CGRectGetHeight(self.view.bounds)-50, CGRectGetWidth(self.view.bounds), NSCollectionViewHeight);
    CGRect bound = CGRectZero;;

    NSCollectionView *collectionView = [[NSCollectionView alloc] initWithFrame:bound];
    NSCollectionViewFlowLayout *layout = [[NSCollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 0;
    layout.minimumInteritemSpacing = 0;
    layout.scrollDirection = NSCollectionViewScrollDirectionHorizontal;
    layout.itemSize = CGSizeMake(NSCollectionViewWidth, NSCollectionViewHeight);
    collectionView.collectionViewLayout = layout;
    collectionView.dataSource = self;
    collectionView.delegate = self;
    [collectionView registerClass:[HLCollectionViewItem class] forItemWithIdentifier:@"HLCollectionViewItemID"];
    
    NSClipView *clip = [[NSClipView alloc] initWithFrame:bound];
    clip.documentView = collectionView;
    
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:frame];
    scrollView.autohidesScrollers = YES; // 自动隐藏滚动条
    scrollView.hasVerticalScroller = NO; // 强制隐藏垂直滚动条
    scrollView.hasHorizontalScroller = NO; // 强制隐藏水平滚动条
    scrollView.contentView = clip;

    [self.view addSubview:scrollView];

    self.scrollView = scrollView;
    self.collectionView = collectionView;

    // 强制隐藏所有NSScroller子视图
    for (NSView *subview in scrollView.subviews) {
        if ([subview isKindOfClass:[NSScroller class]]) {
            subview.hidden = YES;
        }
    }
}

#pragma mark - Notification



- (void)jeffernMovieRequestSuccess:(NSNotification *)notification{
    

    
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"UserCustomSiteURL"]) {
    
    }
}

#pragma mark - history

- (NSMutableArray *)loadHistoryArray {
    NSData *data = [NSData dataWithContentsOfFile:HISTORY_PATH];
    if (!data) return [NSMutableArray array];
    NSArray *arr = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if ([arr isKindOfClass:[NSArray class]]) {
        return [arr mutableCopy];
    }
    return [NSMutableArray array];
}

- (void)saveHistoryArray:(NSArray *)array {
    NSData *data = [NSJSONSerialization dataWithJSONObject:array options:0 error:nil];
    NSString *dir = [HISTORY_PATH stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    [data writeToFile:HISTORY_PATH atomically:YES];
}

- (void)addHistoryWithName:(NSString *)name url:(NSString *)url {
    if (!url.length) return;
    if ([url containsString:@"history_rendered.html"]) return;
    if (name && [name isEqualToString:url]) return;

    // name为nil或空时不做正则判断
    if (!name || [[name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0) return;

    // 用正则判断标题是否为网址
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^https?://.+" options:NSRegularExpressionCaseInsensitive error:nil];
    NSUInteger matches = [regex numberOfMatchesInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)];
    if (matches > 0) return;

    NSMutableArray *history = [self loadHistoryArray];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *now = [formatter stringFromDate:[NSDate date]];

    NSDictionary *item = @{@"name": name ?: url, @"url": url, @"time": now};
    [history insertObject:item atIndex:0];
    while (history.count > 15) {
        [history removeLastObject];
    }
    [self saveHistoryArray:history];
}

- (void)clearHistory {
    [[NSFileManager defaultManager] removeItemAtPath:HISTORY_PATH error:nil];
}

#pragma mark - CollectionView
- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.modelsArray.count;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
    HLCollectionViewItem *item = [collectionView makeItemWithIdentifier:@"HLCollectionViewItemID" forIndexPath:indexPath];

    return item;
}



#pragma mark - Custom Site URL

- (void)promptForCustomSiteURLAndLoadIfNeeded {
    NSString *cachedUrl = [[NSUserDefaults standardUserDefaults] objectForKey:@"UserCustomSiteURL"];
    if (!cachedUrl || cachedUrl.length == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"⬇网址格式如下⬇";
        alert.informativeText = @"https://www.xxx.com";
        NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
        [alert setAccessoryView:input];
        [alert addButtonWithTitle:@"✨✨✨"];
        [alert addButtonWithTitle:@"使用内置影视"];
        [alert.window setInitialFirstResponder:input];
        __weak typeof(self) weakSelf = self;
        NSWindow *mainWindow = [NSApplication sharedApplication].mainWindow ?: self.view.window;
        if (mainWindow) {
            [alert beginSheetModalForWindow:mainWindow completionHandler:^(NSModalResponse returnCode) {
                if (returnCode == NSAlertFirstButtonReturn) {
                    NSString *url = [input.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (url.length > 0) {
                        [[NSUserDefaults standardUserDefaults] setObject:url forKey:@"UserCustomSiteURL"];
                        [[NSUserDefaults standardUserDefaults] synchronize];
                        [weakSelf loadUserCustomSiteURL:url];
                    } else {
                        [NSApp terminate:nil];
                    }
                } else if (returnCode == NSAlertSecondButtonReturn) {
                    // 弹窗选择内置影视站点
                    NSArray *siteNames = @[@"海纳TV",@"奈飞工厂", @"omofun动漫",@"红狐狸影视", @"低端影视", @"多瑙影视",@"CCTV",@"Emby"];
                    NSArray *siteURLs = @[
                        @"https://www.hainatv.net/",
                        @"https://yanetflix.com/",
                        @"https://www.omofun2.xyz/",
                        @"https://honghuli.com/",
                        @"https://ddys.pro/",
                        @"https://www.duonaovod.com/",
                        @"https://tv.cctv.com/live/",
                        @"https://dongman.theluyuan.com/",
                    ];
                    NSAlert *siteAlert = [[NSAlert alloc] init];
                    siteAlert.messageText = @"请选择内置影视站点";
                    for (NSString *name in siteNames) {
                        [siteAlert addButtonWithTitle:name];
                    }
                    NSWindow *mainWindow = [NSApplication sharedApplication].mainWindow ?: self.view.window;
                    [siteAlert beginSheetModalForWindow:mainWindow completionHandler:^(NSModalResponse siteCode) {
                        NSInteger idx = siteCode - NSAlertFirstButtonReturn;
                        if (idx >= 0 && idx < siteURLs.count) {
                            NSString *url = siteURLs[idx];
                            [weakSelf loadUserCustomSiteURL:url];
                        }
                        // 取消不做任何事
                    }];
                }
            }];
        } else {
            // 兜底：直接阻塞弹窗
            NSModalResponse returnCode = [alert runModal];
            if (returnCode == NSAlertFirstButtonReturn) {
                NSString *url = [input.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (url.length > 0) {
                    [[NSUserDefaults standardUserDefaults] setObject:url forKey:@"UserCustomSiteURL"];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                    [self loadUserCustomSiteURL:url];
                } else {
                    [NSApp terminate:nil];
                }
            } else if (returnCode == NSAlertSecondButtonReturn) {
                NSArray *siteNames = @[@"奈飞工厂", @"omofun动漫", @"低端影视", @"多瑙影视", @"星辰影视", @"CCTV", @"观影网"];
                NSArray *siteURLs = @[
                    @"https://yanetflix.com/",
                    @"https://www.omofun2.xyz",
                    @"https://ddys.pro/",
                    @"https://www.duonaovod.com/",
                    @"https://szgpmy.com/",
                    @"https://tv.cctv.com/live/",
                    @"https://www.gying.si"
                ];
                NSAlert *siteAlert = [[NSAlert alloc] init];
                siteAlert.messageText = @"请选择内置影视站点";
                for (NSString *name in siteNames) {
                    [siteAlert addButtonWithTitle:name];
                }
                NSModalResponse siteCode = [siteAlert runModal];
                NSInteger idx = siteCode - NSAlertFirstButtonReturn;
                if (idx >= 0 && idx < siteURLs.count) {
                    NSString *url = siteURLs[idx];
                    [self loadUserCustomSiteURL:url];
                }
                // 取消不做任何事
            }
        }
    } else {
        [self loadUserCustomSiteURL:cachedUrl];
    }
}

- (void)loadUserCustomSiteURL:(NSString *)urlString {
    if (!urlString || urlString.length == 0) return;
    // 显示“正在加载中”提示（更明显，垂直居中）
    if (!self.loadingTipsLabel) {
        NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 400, 40)];
        label.stringValue = @"正在加载中...";
        label.alignment = NSTextAlignmentCenter;
        label.font = [NSFont boldSystemFontOfSize:28];
        label.textColor = [NSColor whiteColor];
        label.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.7];
        label.editable = NO;
        label.bezeled = NO;
        label.drawsBackground = YES;
        label.selectable = NO;
        label.wantsLayer = YES;
        label.layer.cornerRadius = 16;
        label.layer.masksToBounds = YES;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [label.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
            [label.widthAnchor constraintEqualToConstant:400],
            [label.heightAnchor constraintEqualToConstant:40]
        ]];
        self.loadingTipsLabel = label;
    }
    self.loadingTipsLabel.hidden = NO;
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [self.webView loadRequest:request];
    // 新增：记录历史
    [self addHistoryWithName:nil url:urlString];
}

- (void)changeUserCustomSiteURL:(id)sender {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UserCustomSiteURL"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self promptForCustomSiteURLAndLoadIfNeeded];
    [self showEmptyTipsIfNeeded];
}

- (void)showEmptyTipsIfNeeded {
    // 已去除全局浮动提示，不再显示 label。
}

- (void)showLocalHistoryHTML {
    NSString *htmlPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"history_rendered.html"];
    NSURL *url = [NSURL fileURLWithPath:htmlPath];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [self.webView loadRequest:request];
}

#pragma mark - WKScriptMessageHandler
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:@"clearHistory"]) {
        [self clearHistory];
        // 重新生成HTML并刷新
        AppDelegate *delegate = (AppDelegate *)[NSApplication sharedApplication].delegate;
        [delegate generateHistoryHTML];
        [self showLocalHistoryHTML];
    }
}

#pragma mark - 智能预加载常用站点
- (void)preloadFrequentlyUsedSites {
    NSMutableArray *history = [self loadHistoryArray];
    if (history.count == 0) return;
    // 统计域名出现频率
    NSMutableDictionary *hostCount = [NSMutableDictionary dictionary];
    for (NSDictionary *item in history) {
        NSString *urlStr = item[@"url"];
        NSURL *url = [NSURL URLWithString:urlStr];
        if (!url.host) continue;
        NSString *host = url.host;
        NSNumber *count = hostCount[host];
        hostCount[host] = @(count ? count.integerValue + 1 : 1);
    }
    // 按频率排序，取前3
    NSArray *sortedHosts = [hostCount keysSortedByValueUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        return [obj2 compare:obj1];
    }];
    NSInteger preloadCount = MIN(3, sortedHosts.count);
    for (NSInteger i = 0; i < preloadCount; i++) {
        NSString *host = sortedHosts[i];
        // 找到历史中第一个该host的完整url
        NSString *preloadUrl = nil;
        for (NSDictionary *item in history) {
            NSString *urlStr = item[@"url"];
            NSURL *url = [NSURL URLWithString:urlStr];
            if ([url.host isEqualToString:host]) {
                preloadUrl = urlStr;
                break;
            }
        }
        if (preloadUrl) {
            NSURL *url = [NSURL URLWithString:preloadUrl];
            NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
            NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request];
            [task resume];
        }
    }
}

#pragma mark - 防止休眠/锁屏
- (void)enablePreventSleep {
    if (self.isPreventingSleep) return;
    IOReturn success = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep,
                                                   kIOPMAssertionLevelOn,
                                                   CFSTR("JeffernMovie防止休眠/锁屏"),
                                                   &_assertionID);
    if (success == kIOReturnSuccess) {
        self.isPreventingSleep = YES;
    }
}

- (void)disablePreventSleep {
    if (!self.isPreventingSleep) return;
    IOPMAssertionRelease(_assertionID);
    self.isPreventingSleep = NO;
}

#pragma mark - 会话恢复
- (void)saveSessionState {
    NSString *currentUrl = self.currentWebView.URL.absoluteString;
    if (currentUrl.length > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:currentUrl forKey:SESSION_STATE_KEY];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (void)restoreSessionState {
    NSString *lastUrl = [[NSUserDefaults standardUserDefaults] objectForKey:SESSION_STATE_KEY];
    if (lastUrl.length > 0) {
        NSURL *url = [NSURL URLWithString:lastUrl];
        if (url) {
            NSURLRequest *request = [NSURLRequest requestWithURL:url];
            [self.webView loadRequest:request];
        }
    }
}


@end
