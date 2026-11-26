#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

typedef void (*Hook)(Class, SEL, IMP, IMP *);
static Hook hook;
static NSUInteger scanEpoch, installedCount;
static NSHashTable<UIView *> *knownMenus;
static BOOL lifecycleInstalled;
static void installHooks(void);
static void (*presentOrig)(id,SEL,id), (*dismissOrig)(id,SEL);
static void report(NSString *status) {
    Class bridge = NSClassFromString(@"TSMMenuBridge");
    SEL sel = NSSelectorFromString(@"recordHookStatus:");
    if (bridge && [bridge respondsToSelector:sel]) ((void(*)(id,SEL,id))objc_msgSend)(bridge,sel,status);
}
static void (*collectionLayoutOrig)(id,SEL), (*pageLayoutOrig)(id,SEL), (*cellLayoutOrig)(id,SEL), (*pasteLayoutOrig)(id,SEL), (*slotLayoutOrig)(id,SEL);
static void (*collectionOffsetOrig)(id,SEL,CGPoint);
static void (*collectionBoundsOrig)(id,SEL,CGRect), (*menuBoundsOrig)(id,SEL,CGRect), (*menuFrameOrig)(id,SEL,CGRect), (*pageFrameOrig)(id,SEL,CGRect);
static void (*pageAlphaOrig)(id,SEL,CGFloat);
static void (*menuCenterOrig)(id,SEL,CGPoint);
static void (*menuTransformOrig)(id,SEL,CGAffineTransform);
static void (*menuTraitOrig)(id,SEL,UITraitCollection *);
static void (*layoutOrig)(id,SEL), (*windowOrig)(id,SEL), (*containerWindowOrig)(id,SEL);
static void (*hiddenOrig)(id,SEL,BOOL), (*containerHiddenOrig)(id,SEL,BOOL);
static void (*alphaOrig)(id,SEL,CGFloat), (*containerAlphaOrig)(id,SEL,CGFloat);
static char pending, notifying;
static void notify(UIView *view, BOOL remove) {
    if (objc_getAssociatedObject(view,&notifying)) return;
    objc_setAssociatedObject(view,&notifying,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    Class bridge = NSClassFromString(@"TSMMenuBridge");
    SEL sel = NSSelectorFromString(remove ? @"removeMenu:" : @"updateMenu:");
    if (bridge && [bridge respondsToSelector:sel]) ((void(*)(id,SEL,id))objc_msgSend)(bridge,sel,view);
    objc_setAssociatedObject(view,&notifying,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void schedule(UIView *view) {
    if (!NSThread.isMainThread) return;
    if (!knownMenus) knownMenus = [NSHashTable weakObjectsHashTable];
    [knownMenus addObject:view];
    if (!view.window || view.hidden) { notify(view,YES); return; }
    if (objc_getAssociatedObject(view,&pending)) return;
    objc_setAssociatedObject(view,&pending,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weak = view;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *v=weak; if (!v) return;
        objc_setAssociatedObject(v,&pending,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        notify(v,!v.window || v.hidden);
    });
}
static void findMenus(UIView *view, NSUInteger depth) {
    Class menu = NSClassFromString(@"_UIEditMenuListView");
    if (menu && [view isKindOfClass:menu]) { schedule(view); return; }
    if (depth == 0) return;
    for (UIView *child in view.subviews) findMenus(child,depth-1);
}
static void updateChildren(UIView *view) { findMenus(view,3); }
static void scanWindows(void) {
    UIApplication *app = UIApplication.sharedApplication;
    NSMutableOrderedSet<UIWindow *> *windows = [NSMutableOrderedSet orderedSetWithArray:app.windows];
    for (UIScene *scene in app.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
    Class textWindow = NSClassFromString(@"UITextEffectsWindow");
    // Effects windows and menu hosts can be reused/reparented after app switching.
    // Do not assume the container is a direct child of the window.
    for (UIView *menu in knownMenus.allObjects) {
        if (menu.window && textWindow && [menu.window isKindOfClass:textWindow]) {
            [windows addObject:menu.window];
            schedule(menu);
        }
    }
    for (UIWindow *w in windows) {
        if (textWindow && [w isKindOfClass:textWindow]) findMenus(w,12);
    }
}
static void queueScans(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ queueScans(); }); return; }
    NSUInteger epoch = ++scanEpoch;
    for (NSNumber *delay in @[@0, @50, @160, @350, @800, @1500]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay.longLongValue * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            if (epoch == scanEpoch && UIApplication.sharedApplication.applicationState == UIApplicationStateActive) scanWindows();
        });
    }
}
static void installLifecycle(void) {
    if (lifecycleInstalled) return;
    lifecycleInstalled = YES;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    // Foreground entry may still be inactive. didBecomeActive and scene activation
    // trigger a fresh, bounded sequence after UIKit reconstructs its menu windows.
    for (NSNotificationName name in @[UIApplicationWillEnterForegroundNotification,
                                      UIApplicationDidBecomeActiveNotification,
                                      UISceneDidActivateNotification]) {
        [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            installHooks();
            queueScans();
        }];
    }
}
static void presented(id self, SEL cmd, id config) {
    if (NSThread.isMainThread && [self respondsToSelector:@selector(view)] && [config respondsToSelector:@selector(sourcePoint)]) {
        UIView *source = [(UIEditMenuInteraction *)self view];
        Class bridge = NSClassFromString(@"TSMMenuBridge");
        SEL sel = NSSelectorFromString(@"recordPresentationForView:point:");
        if (source && bridge && [bridge respondsToSelector:sel]) {
            CGPoint point = [(UIEditMenuConfiguration *)config sourcePoint];
            ((void(*)(id,SEL,id,CGPoint))objc_msgSend)(bridge,sel,source,point);
        }
    }
    presentOrig(self,cmd,config); queueScans();
}
static void dismissed(id self, SEL cmd) { dismissOrig(self,cmd); queueScans(); }
static void layout(UIView *v,SEL s) {
    layoutOrig(v,s);
    // Apply before the completed native layout can be committed to the screen.
    if (NSThread.isMainThread && v.window && !v.hidden && v.alpha > 0.01) notify(v,NO);
    schedule(v);
}
static void windowChanged(UIView *v,SEL s) { windowOrig(v,s); schedule(v); }
static void hidden(UIView *v,SEL s,BOOL h) { hiddenOrig(v,s,h); schedule(v); }
static char immediate;
static void alpha(UIView *v,SEL s,CGFloat a) {
    alphaOrig(v,s,a);
    if (a > 0.01 && v.window && NSThread.isMainThread && !objc_getAssociatedObject(v,&immediate)) {
        objc_setAssociatedObject(v,&immediate,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        notify(v,NO);
        objc_setAssociatedObject(v,&immediate,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    schedule(v);
}
static void containerAlpha(UIView *v,SEL s,CGFloat a) { containerAlphaOrig(v,s,a); updateChildren(v); }
static void containerWindow(UIView *v,SEL s) { containerWindowOrig(v,s); updateChildren(v); }
static void containerHidden(UIView *v,SEL s,BOOL h) { containerHiddenOrig(v,s,h); updateChildren(v); }
static void scheduleAncestor(UIView *v) {
    Class c = NSClassFromString(@"_UIEditMenuListView");
    for (NSUInteger i=0; v && i<12; i++,v=v.superview) {
        if (c && [v isKindOfClass:c]) { schedule(v); return; }
    }
}
static void collectionLayout(UIView *v,SEL s) { collectionLayoutOrig(v,s); scheduleAncestor(v); }
static void centerAfterLayout(UIView *v) {
    if (!NSThread.isMainThread) return;
    Class menu = NSClassFromString(@"_UIEditMenuListView");
    for (UIView *p=v.superview; p; p=p.superview) {
        if (menu && [p isKindOfClass:menu]) {
            Class bridge = NSClassFromString(@"TSMMenuBridge");
            SEL sel = NSSelectorFromString(@"centerLayoutForView:menu:");
            if (bridge && [bridge respondsToSelector:sel]) ((void(*)(id,SEL,id,id))objc_msgSend)(bridge,sel,v,p);
            break;
        }
    }
}
static void pageLayout(UIView *v,SEL s) { pageLayoutOrig(v,s); centerAfterLayout(v); scheduleAncestor(v); }
static void pasteLayout(UIView *v,SEL s) { pasteLayoutOrig(v,s); centerAfterLayout(v); scheduleAncestor(v); }
static void slotLayout(UIView *v,SEL s) { slotLayoutOrig(v,s); centerAfterLayout(v); scheduleAncestor(v); }
static void cellLayout(UIView *v,SEL s) { cellLayoutOrig(v,s); centerAfterLayout(v); scheduleAncestor(v); }
static void collectionOffset(UIView *v,SEL s,CGPoint p) { collectionOffsetOrig(v,s,p); scheduleAncestor(v); }
static void collectionBounds(UIView *v,SEL s,CGRect r) { collectionBoundsOrig(v,s,r); scheduleAncestor(v); }
static void menuBounds(UIView *v,SEL s,CGRect r) { menuBoundsOrig(v,s,r); schedule(v); }
static void menuFrame(UIView *v,SEL s,CGRect r) { menuFrameOrig(v,s,r); schedule(v); }
static void menuCenter(UIView *v,SEL s,CGPoint p) {
    menuCenterOrig(v,s,p);
    if (!objc_getAssociatedObject(v,&notifying)) schedule(v);
}
static void menuTransform(UIView *v,SEL s,CGAffineTransform t) {
    menuTransformOrig(v,s,t);
    if (!objc_getAssociatedObject(v,&notifying)) schedule(v);
}
static void menuTrait(UIView *v,SEL s,UITraitCollection *previous) {
    menuTraitOrig(v,s,previous); schedule(v);
}
static void pageFrame(UIView *v,SEL s,CGRect r) { pageFrameOrig(v,s,r); scheduleAncestor(v); }
static void pageAlpha(UIView *v,SEL s,CGFloat a) { pageAlphaOrig(v,s,a); scheduleAncestor(v); }
static void install(Class c,SEL s,IMP f,IMP *orig) {
    if (!c || *orig) return;
    Method m=class_getInstanceMethod(c,s); if (!m) return;
    class_addMethod(c,s,method_getImplementation(m),method_getTypeEncoding(m));
    if (hook) hook(c,s,f,orig);
    else *orig = method_setImplementation(class_getInstanceMethod(c,s),f);
    if (*orig) installedCount++;
}
static void installHooks(void) {
    Class menu=NSClassFromString(@"_UIEditMenuListView"), container=NSClassFromString(@"_UIEditMenuContainerView");
    Class interaction=NSClassFromString(@"UIEditMenuInteraction");
    install(interaction,NSSelectorFromString(@"presentEditMenuWithConfiguration:"),(IMP)presented,(IMP*)&presentOrig);
    install(interaction,NSSelectorFromString(@"dismissMenu"),(IMP)dismissed,(IMP*)&dismissOrig);
    install(menu,@selector(layoutSubviews),(IMP)layout,(IMP*)&layoutOrig);
    install(menu,@selector(didMoveToWindow),(IMP)windowChanged,(IMP*)&windowOrig);
    install(menu,@selector(setHidden:),(IMP)hidden,(IMP*)&hiddenOrig);
    install(menu,@selector(setAlpha:),(IMP)alpha,(IMP*)&alphaOrig);
    install(container,@selector(setAlpha:),(IMP)containerAlpha,(IMP*)&containerAlphaOrig);
    install(container,@selector(didMoveToWindow),(IMP)containerWindow,(IMP*)&containerWindowOrig);
    install(container,@selector(setHidden:),(IMP)containerHidden,(IMP*)&containerHiddenOrig);
    Class collection=NSClassFromString(@"_UIEditMenuCollectionView"), page=NSClassFromString(@"_UIEditMenuPageButton"), cell=NSClassFromString(@"_UIEditMenuListViewCell");
    install(menu,@selector(setBounds:),(IMP)menuBounds,(IMP*)&menuBoundsOrig);
    install(menu,@selector(setFrame:),(IMP)menuFrame,(IMP*)&menuFrameOrig);
    install(menu,@selector(setCenter:),(IMP)menuCenter,(IMP*)&menuCenterOrig);
    install(menu,@selector(setTransform:),(IMP)menuTransform,(IMP*)&menuTransformOrig);
    install(menu,@selector(traitCollectionDidChange:),(IMP)menuTrait,(IMP*)&menuTraitOrig);
    install(collection,@selector(layoutSubviews),(IMP)collectionLayout,(IMP*)&collectionLayoutOrig);
    install(collection,@selector(setContentOffset:),(IMP)collectionOffset,(IMP*)&collectionOffsetOrig);
    install(collection,@selector(setBounds:),(IMP)collectionBounds,(IMP*)&collectionBoundsOrig);
    install(page,@selector(layoutSubviews),(IMP)pageLayout,(IMP*)&pageLayoutOrig);
    install(page,@selector(setFrame:),(IMP)pageFrame,(IMP*)&pageFrameOrig);
    install(page,@selector(setAlpha:),(IMP)pageAlpha,(IMP*)&pageAlphaOrig);
    install(cell,@selector(layoutSubviews),(IMP)cellLayout,(IMP*)&cellLayoutOrig);
    install(NSClassFromString(@"UIPasteControl"),@selector(layoutSubviews),(IMP)pasteLayout,(IMP*)&pasteLayoutOrig);
    install(NSClassFromString(@"_UISlotView"),@selector(layoutSubviews),(IMP)slotLayout,(IMP*)&slotLayoutOrig);
    report([NSString stringWithFormat:@"0.2.6 %@ hooks=%lu presentation=%@",hook?@"substrate":@"objc-runtime",(unsigned long)installedCount,presentOrig?@"yes":@"no"]);
}
#ifndef NG_TESTING
__attribute__((constructor)) static void start(void) {
    hook=(Hook)dlsym(RTLD_DEFAULT,"MSHookMessageEx");
    if (!hook) for (NSString *p in @[@"/usr/lib/libsubstrate.dylib",@"/var/jb/usr/lib/libsubstrate.dylib"]) {
        void *h=dlopen(p.UTF8String,RTLD_NOW|RTLD_LOCAL); if (h) hook=(Hook)dlsym(h,"MSHookMessageEx"); if (hook) break;
    }
    if (NSThread.isMainThread) { installHooks(); installLifecycle(); }
    dispatch_async(dispatch_get_main_queue(), ^{ installHooks(); installLifecycle(); queueScans(); });
}
#endif
