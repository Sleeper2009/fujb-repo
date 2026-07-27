#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

@interface LMTransitionState : NSObject
@property (nonatomic, strong) CAShapeLayer *maskShape;
@property (nonatomic, strong) CALayer *contentLayer;
@property (nonatomic, assign) CGRect iconFrame;
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, assign) BOOL isOpening;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, assign) BOOL isCleanedUp;
@end

@implementation LMTransitionState
- (instancetype)init {
    if ((self = [super init])) {
        _timestamp = [NSDate date];
        _isCleanedUp = NO;
    }
    return self;
}
@end

@interface SBIconView : UIView
- (id)icon;
@end

@interface SBIconController : NSObject
- (void)handleHomeButtonTap;
- (void)_launchFromIconView:(id)iconView withActions:(id)actions;
- (void)iconManager:(id)manager launchIconForIconView:(id)iconView withActions:(id)actions;
@end

static NSString *const kLogPath = @"/var/mobile/Documents/LiquidMorphExtended.log";
static NSString *const kPrefDomain = @"com.furina.liquidmorph";

static CGFloat gBounceAmount = 26.0;
static CGFloat gPeakRadius = 90.0;
static CGFloat gEndRadius = 14.0;
static CGFloat gDuration = 0.38;
static BOOL gTweakEnabled = YES;
static BOOL gAdvancedLogging = YES;
static CGFloat gDampingRatio = 0.82;
static CGFloat gInitialVelocity = 0.5;
static BOOL gUseMetalOptimization = YES;
static NSUInteger gMaxKeyframeSteps = 24;

static LMTransitionState *gCurrentState = nil;
static UIWindow *gOverlayWindow = nil;

static void LMLog(NSString *format, ...) {
    @try {
        va_list args;
        va_start(args, format);
        NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:[NSDate date]], message];
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:kLogPath]) [fm createFileAtPath:kLogPath contents:nil attributes:nil];
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
        if (handle) {
            [handle seekToEndOfFile];
            [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [handle closeFile];
        }
    } @catch (NSException *e) {}
}

static NSDictionary *LMReadRawPlist(void) {
    @try {
        NSArray *candidatePaths = @[
            @"/var/mobile/Library/Preferences/com.furina.liquidmorph.plist",
            [NSString stringWithFormat:@"%@/Library/Preferences/com.furina.liquidmorph.plist", NSHomeDirectory()]
        ];
        for (NSString *path in candidatePaths) {
            NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
            if (dict) return dict;
        }
    } @catch (NSException *e) {}
    return nil;
}

static CGFloat LMPrefFloat(NSString *key, CGFloat fallback) {
    @try {
        NSDictionary *raw = LMReadRawPlist();
        if (raw && raw[key]) return [raw[key] doubleValue];
        
        CFStringRef keyRef = (__bridge CFStringRef)key;
        CFStringRef appRef = (__bridge CFStringRef)kPrefDomain;
        CFPropertyListRef val = CFPreferencesCopyAppValue(keyRef, appRef);
        if (!val) return fallback;
        
        CGFloat result = fallback;
        if (CFGetTypeID(val) == CFNumberGetTypeID()) {
            CFNumberGetValue((CFNumberRef)val, kCFNumberDoubleType, &result);
        }
        CFRelease(val);
        return result;
    } @catch (NSException *e) {
        return fallback;
    }
}

static BOOL LMPrefBool(NSString *key, BOOL fallback) {
    @try {
        NSDictionary *raw = LMReadRawPlist();
        if (raw && raw[key]) return [raw[key] boolValue];
        
        CFStringRef keyRef = (__bridge CFStringRef)key;
        CFStringRef appRef = (__bridge CFStringRef)kPrefDomain;
        CFPropertyListRef val = CFPreferencesCopyAppValue(keyRef, appRef);
        if (!val) return fallback;
        
        BOOL result = CFBooleanGetValue((CFBooleanRef)val);
        CFRelease(val);
        return result;
    } @catch (NSException *e) {
        return fallback;
    }
}

static void LMReloadSettings(void) {
    @try {
        CFPreferencesAppSynchronize((__bridge CFStringRef)kPrefDomain);
        gTweakEnabled = LMPrefBool(@"enabled", YES);
        gAdvancedLogging = LMPrefBool(@"advancedLogging", YES);
        gBounceAmount = LMPrefFloat(@"bounceAmount", 26.0);
        gPeakRadius = LMPrefFloat(@"peakRadius", 90.0);
        gEndRadius = LMPrefFloat(@"endRadius", 14.0);
        gDuration = LMPrefFloat(@"duration", 0.38);
        gDampingRatio = LMPrefFloat(@"dampingRatio", 0.82);
        gInitialVelocity = LMPrefFloat(@"initialVelocity", 0.5);
        gUseMetalOptimization = LMPrefBool(@"useMetalOptimization", YES);
    } @catch (NSException *e) {}
}

static void LMWriteDefault(NSString *key, id value) {
    @try {
        CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)kPrefDomain);
    } @catch (NSException *e) {}
}

static void LMSettingsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    LMReloadSettings();
}

static void LMResetCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    @try {
        LMWriteDefault(@"enabled", @YES);
        LMWriteDefault(@"advancedLogging", @YES);
        LMWriteDefault(@"bounceAmount", @26.0);
        LMWriteDefault(@"peakRadius", @90.0);
        LMWriteDefault(@"endRadius", @14.0);
        LMWriteDefault(@"duration", @0.38);
        LMWriteDefault(@"dampingRatio", @0.82);
        LMWriteDefault(@"initialVelocity", @0.5);
        LMWriteDefault(@"useMetalOptimization", @YES);
        CFPreferencesAppSynchronize((__bridge CFStringRef)kPrefDomain);
        LMReloadSettings();
    } @catch (NSException *e) {}
}

static void LMRespringCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    exit(0);
}

static CGPathRef LMRoundedQuadPath(CGPoint tl, CGPoint tr, CGPoint br, CGPoint bl,
                                    CGFloat rTL, CGFloat rTR, CGFloat rBR, CGFloat rBL) {
    CGMutablePathRef path = CGPathCreateMutable();
    @try {
        CGPoint points[4] = { tl, tr, br, bl };
        CGFloat radii[4] = { rTL, rTR, rBR, rBL };
        
        for (NSInteger i = 0; i < 4; i++) {
            CGPoint cur = points[i];
            CGPoint prev = points[(i - 1 + 4) % 4];
            CGPoint next = points[(i + 1) % 4];
            CGFloat r = radii[i];
            
            CGFloat distPrev = hypot(cur.x - prev.x, cur.y - prev.y);
            CGFloat distNext = hypot(cur.x - next.x, cur.y - next.y);
            CGFloat rClamped = MIN(r, MIN(distPrev, distNext) * 0.45);
            
            CGFloat toPrevX = (distPrev > 0) ? (prev.x - cur.x) / distPrev : 0;
            CGFloat toPrevY = (distPrev > 0) ? (prev.y - cur.y) / distPrev : 0;
            CGFloat toNextX = (distNext > 0) ? (next.x - cur.x) / distNext : 0;
            CGFloat toNextY = (distNext > 0) ? (next.y - cur.y) / distNext : 0;
            
            CGPoint p1 = CGPointMake(cur.x + toPrevX * rClamped, cur.y + toPrevY * rClamped);
            CGPoint p2 = CGPointMake(cur.x + toNextX * rClamped, cur.y + toNextY * rClamped);
            
            if (i == 0) {
                CGPathMoveToPoint(path, NULL, p1.x, p1.y);
            } else {
                CGPathAddLineToPoint(path, NULL, p1.x, p1.y);
            }
            CGPathAddQuadCurveToPoint(path, NULL, cur.x, cur.y, p2.x, p2.y);
        }
        CGPathCloseSubpath(path);
    } @catch (NSException *e) {
        if (gAdvancedLogging) LMLog(@"Error in LMRoundedQuadPath: %@", e);
    }
    return path;
}

static CGFloat LMEdgeProgress(CGFloat t, CGFloat closeness, CGFloat maxDelay) {
    CGFloat delay = closeness * maxDelay;
    CGFloat span = 1.0 - delay;
    if (span <= 0) span = 0.001;
    CGFloat edgeT = (t - delay) / span;
    if (edgeT < 0) edgeT = 0;
    if (edgeT > 1) edgeT = 1;
    return edgeT;
}

static CGFloat LMHumpRadius(CGFloat t) {
    CGFloat iconRadius = 10.0;
    CGFloat peakRadius = gPeakRadius;
    CGFloat endRadius = gEndRadius;
    if (t < 0.45) {
        return iconRadius + (peakRadius - iconRadius) * (t / 0.45);
    } else {
        CGFloat local = (t - 0.45) / 0.55;
        if (local > 1) local = 1;
        return peakRadius + (endRadius - peakRadius) * local;
    }
}

static UIImage *LMLoadAppSnapshot(NSString *bundleID) {
    if (bundleID.length == 0) return nil;
    @try {
        NSString *dir = [NSString stringWithFormat:@"/var/mobile/Library/Caches/Snapshots/%@", bundleID];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *files = [fm contentsOfDirectoryAtPath:dir error:nil];
        if (files.count == 0) return nil;
        for (NSString *f in files) {
            NSString *ext = f.pathExtension.lowercaseString;
            if ([ext isEqualToString:@"png"] || [ext isEqualToString:@"jpg"]) {
                UIImage *img = [UIImage imageWithContentsOfFile:[dir stringByAppendingPathComponent:f]];
                if (img) return img;
            }
        }
    } @catch (NSException *e) {
        if (gAdvancedLogging) LMLog(@"Error loading app snapshot for %@: %@", bundleID, e);
    }
    return nil;
}

static NSArray *LMBuildKeyframePaths(CGRect iconFrame, CGRect screen, BOOL opening) {
    NSMutableArray *paths = [NSMutableArray array];
    @try {
        CGFloat iconCenterXNorm = (iconFrame.origin.x + iconFrame.size.width / 2.0) / screen.size.width;
        CGFloat iconCenterYNorm = (iconFrame.origin.y + iconFrame.size.height / 2.0) / screen.size.height;

        CGFloat closeBottom = iconCenterYNorm;
        CGFloat closeTop = 1.0 - iconCenterYNorm;
        CGFloat closeRight = iconCenterXNorm;
        CGFloat closeLeft = 1.0 - iconCenterXNorm;

        NSUInteger steps = gMaxKeyframeSteps;
        CGFloat maxDelay = 0.3;
        CGFloat endRadius = gEndRadius;

        CGFloat bounceDirection = (iconCenterYNorm > 0.5) ? -1.0 : 1.0;
        CGFloat bounceAmount = gBounceAmount;

        CGFloat iconLeft = iconFrame.origin.x;
        CGFloat iconRight = iconFrame.origin.x + iconFrame.size.width;
        CGFloat iconTop = iconFrame.origin.y;
        CGFloat iconBottom = iconFrame.origin.y + iconFrame.size.height;
        CGFloat screenLeft = screen.origin.x;
        CGFloat screenRight = screen.origin.x + screen.size.width;
        CGFloat screenTop = screen.origin.y;
        CGFloat screenBottom = screen.origin.y + screen.size.height;

        for (NSUInteger i = 0; i <= steps; i++) {
            CGFloat tRaw = (CGFloat)i / (CGFloat)steps;
            CGFloat t = opening ? tRaw : (1.0 - tRaw);

            CGFloat topP = LMEdgeProgress(t, closeTop, maxDelay);
            CGFloat bottomP = LMEdgeProgress(t, closeBottom, maxDelay);
            CGFloat leftP = LMEdgeProgress(t, closeLeft, maxDelay);
            CGFloat rightP = LMEdgeProgress(t, closeRight, maxDelay);

            CGFloat dampedFactor = expf(-gDampingRatio * t) * cosf(t * (CGFloat)M_PI * 2.0);
            CGFloat bounceEnvelope = sinf(MIN(t, 1.0) * (CGFloat)M_PI) * bounceAmount * bounceDirection * (1.0 - 0.15 * t) + (dampedFactor * 2.0 + gInitialVelocity * 0.5);

            CGFloat topY = iconTop + (screenTop - iconTop) * topP + bounceEnvelope * (1.0 - topP);
            CGFloat bottomY = iconBottom + (screenBottom - iconBottom) * bottomP + bounceEnvelope * (1.0 - bottomP);

            CGFloat topLeftX = iconLeft + (screenLeft - iconLeft) * ((topP + leftP) * 0.5);
            CGFloat topRightX = iconRight + (screenRight - iconRight) * ((topP + rightP) * 0.5);
            CGFloat bottomLeftX = iconLeft + (screenLeft - iconLeft) * ((bottomP + leftP) * 0.5);
            CGFloat bottomRightX = iconRight + (screenRight - iconRight) * ((bottomP + rightP) * 0.5);

            CGPoint tl = CGPointMake(topLeftX, topY);
            CGPoint tr = CGPointMake(topRightX, topY);
            CGPoint br = CGPointMake(bottomRightX, bottomY);
            CGPoint bl = CGPointMake(bottomLeftX, bottomY);

            CGFloat humpBase = LMHumpRadius(t);

            CGFloat rTL = humpBase * (1.0 - MIN(topP, leftP)) + endRadius * MIN(topP, leftP);
            CGFloat rTR = humpBase * (1.0 - MIN(topP, rightP)) + endRadius * MIN(topP, rightP);
            CGFloat rBR = humpBase * (1.0 - MIN(bottomP, rightP)) + endRadius * MIN(bottomP, rightP);
            CGFloat rBL = humpBase * (1.0 - MIN(bottomP, leftP)) + endRadius * MIN(bottomP, leftP);

            CGPathRef p = LMRoundedQuadPath(tl, tr, br, bl, rTL, rTR, rBR, rBL);
            if (p) {
                [paths addObject:CFBridgingRelease(p)];
            }
        }
    } @catch (NSException *e) {
        if (gAdvancedLogging) LMLog(@"Error building keyframe paths extended: %@", e);
    }
    return paths;
}

static void LMCancelCurrentIfAny(void) {
    @try {
        if (gCurrentState && !gCurrentState.isCleanedUp) {
            gCurrentState.isCleanedUp = YES;
            [gCurrentState.maskShape removeAllAnimations];
            [gCurrentState.contentLayer removeAllAnimations];
            [gCurrentState.maskShape removeFromSuperlayer];
            [gCurrentState.contentLayer removeFromSuperlayer];
            gCurrentState = nil;
        }
    } @catch (NSException *e) {
        if (gAdvancedLogging) LMLog(@"Error cancelling current transition: %@", e);
    }
}

static void LMEnsureWindow(void) {
    @try {
        if (gOverlayWindow) return;
        gOverlayWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        gOverlayWindow.windowLevel = UIWindowLevelStatusBar + 1000;
        gOverlayWindow.userInteractionEnabled = NO;
        gOverlayWindow.backgroundColor = [UIColor clearColor];
        if (gUseMetalOptimization && [gOverlayWindow respondsToSelector:@selector(layer)]) {
            gOverlayWindow.layer.shouldRasterize = NO;
            gOverlayWindow.layer.allowsGroupOpacity = YES;
        }
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    gOverlayWindow.windowScene = (UIWindowScene *)scene;
                    break;
                }
            }
        }
        gOverlayWindow.hidden = NO;
    } @catch (NSException *e) {
        if (gAdvancedLogging) LMLog(@"Error ensuring overlay window: %@", e);
    }
}

static void LMPlayTransition(CGRect iconFrame, NSString *bundleID, BOOL opening) {
    @try {
        LMCancelCurrentIfAny();
        LMEnsureWindow();

        CGRect screen = gOverlayWindow.bounds;
        UIImage *snapshot = LMLoadAppSnapshot(bundleID);

        CALayer *contentLayer = [CALayer layer];
        contentLayer.frame = screen;
        contentLayer.contentsGravity = kCAGravityResizeAspectFill;
        if (gUseMetalOptimization) {
            contentLayer.drawsAsynchronously = YES;
        }
        if (snapshot) {
            contentLayer.contents = (__bridge id)snapshot.CGImage;
        } else {
            contentLayer.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0].CGColor;
        }

        CAShapeLayer *maskShape = [CAShapeLayer layer];
        maskShape.frame = screen;
        if (gUseMetalOptimization) {
            maskShape.drawsAsynchronously = YES;
        }
        contentLayer.mask = maskShape;
        [gOverlayWindow.layer addSublayer:contentLayer];

        CATransform3D initialTransform = CATransform3DIdentity;
        CGFloat scaleX = (screen.size.width > 0) ? (iconFrame.size.width / screen.size.width) : 0.1;
        CGFloat scaleY = (screen.size.height > 0) ? (iconFrame.size.height / screen.size.height) : 0.1;
        CGPoint iconCenter = CGPointMake(CGRectGetMidX(iconFrame), CGRectGetMidY(iconFrame));
        CGPoint screenCenter = CGPointMake(CGRectGetMidX(screen), CGRectGetMidY(screen));
        
        initialTransform = CATransform3DTranslate(initialTransform, iconCenter.x - screenCenter.x, iconCenter.y - screenCenter.y, 0);
        initialTransform = CATransform3DScale(initialTransform, scaleX, scaleY, 1.0);

        [CATransaction begin];
        [CATransaction setAnimationDuration:gDuration];
        [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
        if (opening) {
            contentLayer.transform = CATransform3DIdentity;
        } else {
            contentLayer.transform = initialTransform;
        }
        [CATransaction commit];

        NSArray *paths = LMBuildKeyframePaths(iconFrame, screen, opening);
        if (paths.count > 0) {
            CAKeyframeAnimation *anim = [CAKeyframeAnimation animationWithKeyPath:@"path"];
            anim.values = paths;
            anim.duration = gDuration;
            anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            anim.fillMode = kCAFillModeForwards;
            anim.removedOnCompletion = NO;

            maskShape.path = (__bridge CGPathRef)paths.lastObject;
            [maskShape addAnimation:anim forKey:@"morphExtended"];
        }

        LMTransitionState *state = [LMTransitionState new];
        state.maskShape = maskShape;
        state.contentLayer = contentLayer;
        state.iconFrame = iconFrame;
        state.bundleID = bundleID;
        state.isOpening = opening;
        gCurrentState = state;

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((gDuration + 0.15) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try {
                if (gCurrentState == state && !state.isCleanedUp) {
                    state.isCleanedUp = YES;
                    [maskShape removeFromSuperlayer];
                    [contentLayer removeFromSuperlayer];
                    if (gCurrentState == state) {
                        gCurrentState = nil;
                    }
                }
            } @catch (NSException *subEx) {
                if (gAdvancedLogging) LMLog(@"Error in cleanup block extended: %@", subEx);
            }
        });
    } @catch (NSException *e) {
        if (gAdvancedLogging) LMLog(@"Error in LMPlayTransition extended: %@", e);
    }
}

// --- LOGOS HOOKS ---

%hook SBIconView

- (void)_handleTap {
    if (!gTweakEnabled) {
        %orig;
        return;
    }
    @try {
        id icon = [self valueForKey:@"icon"];
        NSString *bundleID = @"";
        if (icon) {
            if ([icon respondsToSelector:@selector(nodeIdentifier)]) {
                bundleID = ((id (*)(id, SEL))objc_msgSend)(icon, @selector(nodeIdentifier)) ?: @"";
            } else if ([icon respondsToSelector:@selector(bundleIdentifier)]) {
                bundleID = ((id (*)(id, SEL))objc_msgSend)(icon, @selector(bundleIdentifier)) ?: @"";
            }
        }
        CGRect frameInWindow = [self.window convertRect:self.bounds fromView:self];
        LMPlayTransition(frameInWindow, bundleID, YES);
    } @catch (NSException *e) {
        if (gAdvancedLogging) LMLog(@"Error in SBIconView _handleTap hook: %@", e);
    }
    %orig;
}

%end

%hook SBUIController

- (void)animateApplicationLaunch:(id)arg1 withActions:(id)arg2 {
    @try {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        %orig;
        [CATransaction commit];
    } @catch (NSException *e) {
        if (gAdvancedLogging) LMLog(@"Error in SBUIController animateApplicationLaunch: %@", e);
        %orig;
    }
}

%end

%hook SBIconController

- (void)handleHomeButtonTap {
    @try {
        if (gTweakEnabled && gCurrentState && gCurrentState.isOpening) {
            LMPlayTransition(gCurrentState.iconFrame, gCurrentState.bundleID, NO);
        }
    } @catch (NSException *e) {
        if (gAdvancedLogging) LMLog(@"Error in handleHomeButtonTap: %@", e);
    }
    %orig;
}

%end

%ctor {
    @autoreleasepool {
        LMReloadSettings();
        
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            (CFNotificationCallback)LMSettingsChangedCallback,
            CFSTR("com.furina.liquidmorph/settingschanged"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            (CFNotificationCallback)LMResetCallback,
            CFSTR("com.furina.liquidmorph/reset"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            (CFNotificationCallback)LMRespringCallback,
            CFSTR("com.furina.liquidmorph/respring"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
    }
}
