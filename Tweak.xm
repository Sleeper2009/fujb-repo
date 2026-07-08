#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

static NSString *const kLogPath = @"/var/mobile/Documents/LiquidMorph.log";

static void LMLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:[NSDate date]], message];
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:kLogPath]) [fm createFileAtPath:kLogPath contents:nil attributes:nil];
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
        if (handle) {
            [handle seekToEndOfFile];
            [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [handle closeFile];
        }
    } @catch (NSException *e) { NSLog(@"[LiquidMorph] Log write failed: %@", e.reason); }
    NSLog(@"[LiquidMorph] %@", message);
}

static CGPathRef LMRoundedQuadPath(CGPoint tl, CGPoint tr, CGPoint br, CGPoint bl,
                                    CGFloat rTL, CGFloat rTR, CGFloat rBR, CGFloat rBL) {
    NSArray *points = @[[NSValue valueWithCGPoint:tl], [NSValue valueWithCGPoint:tr],
                         [NSValue valueWithCGPoint:br], [NSValue valueWithCGPoint:bl]];
    NSArray *radii = @[@(rTL), @(rTR), @(rBR), @(rBL)];
    CGMutablePathRef path = CGPathCreateMutable();
    NSInteger n = points.count;
    CGPoint (^getPoint)(NSInteger) = ^CGPoint(NSInteger idx) {
        return [points[(idx + n) % n] CGPointValue];
    };
    for (NSInteger i = 0; i < n; i++) {
        CGPoint cur = getPoint(i);
        CGPoint prev = getPoint(i - 1);
        CGPoint next = getPoint(i + 1);
        CGFloat r = [radii[i] floatValue];
        CGFloat distPrev = hypot(cur.x - prev.x, cur.y - prev.y);
        CGFloat distNext = hypot(cur.x - next.x, cur.y - next.y);
        CGFloat rClamped = MIN(r, MIN(distPrev, distNext) * 0.5);
        CGFloat toPrevX = (prev.x - cur.x) / (distPrev > 0 ? distPrev : 1);
        CGFloat toPrevY = (prev.y - cur.y) / (distPrev > 0 ? distPrev : 1);
        CGFloat toNextX = (next.x - cur.x) / (distNext > 0 ? distNext : 1);
        CGFloat toNextY = (next.y - cur.y) / (distNext > 0 ? distNext : 1);
        CGPoint p1 = CGPointMake(cur.x + toPrevX * rClamped, cur.y + toPrevY * rClamped);
        CGPoint p2 = CGPointMake(cur.x + toNextX * rClamped, cur.y + toNextY * rClamped);
        if (i == 0) { CGPathMoveToPoint(path, NULL, p1.x, p1.y); }
        else { CGPathAddLineToPoint(path, NULL, p1.x, p1.y); }
        CGPathAddQuadCurveToPoint(path, NULL, cur.x, cur.y, p2.x, p2.y);
    }
    CGPathCloseSubpath(path);
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

static UIImage *LMLoadAppSnapshot(NSString *bundleID) {
    if (bundleID.length == 0) return nil;
    NSString *dir = [NSString stringWithFormat:@"/var/mobile/Library/Caches/Snapshots/%@", bundleID];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;
    NSArray *files = [fm contentsOfDirectoryAtPath:dir error:&err];
    if (err || files.count == 0) return nil;
    for (NSString *f in files) {
        if ([f.pathExtension.lowercaseString isEqualToString:@"png"] ||
            [f.pathExtension.lowercaseString isEqualToString:@"jpg"]) {
            NSString *fullPath = [dir stringByAppendingPathComponent:f];
            UIImage *img = [UIImage imageWithContentsOfFile:fullPath];
            if (img) return img;
        }
    }
    return nil;
}

@interface LMTransitionState : NSObject
@property (nonatomic, strong) CAShapeLayer *maskShape;
@property (nonatomic, strong) CALayer *contentLayer;
@property (nonatomic, assign) CGRect iconFrame;
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, assign) BOOL isOpening;
@end
@implementation LMTransitionState
@end

static LMTransitionState *gCurrentState = nil;
static UIWindow *gOverlayWindow = nil;

static NSArray *LMBuildKeyframePaths(CGRect iconFrame, CGRect screen, BOOL opening) {
    CGFloat iconCenterXNorm = (iconFrame.origin.x + iconFrame.size.width / 2.0) / screen.size.width;
    CGFloat iconCenterYNorm = (iconFrame.origin.y + iconFrame.size.height / 2.0) / screen.size.height;

    CGFloat closeBottom = iconCenterYNorm;
    CGFloat closeTop = 1.0 - iconCenterYNorm;
    CGFloat closeRight = iconCenterXNorm;
    CGFloat closeLeft = 1.0 - iconCenterXNorm;

    NSInteger steps = 24;
    NSMutableArray *paths = [NSMutableArray array];
    CGFloat startRadius = 120.0;
    CGFloat endRadius = 20.0;
    CGFloat maxDelay = 0.4;

    CGFloat bounceDirection = (iconCenterYNorm > 0.5) ? -1.0 : 1.0;
    CGFloat bounceAmount = 42.0;

    CGFloat iconLeft = iconFrame.origin.x;
    CGFloat iconRight = iconFrame.origin.x + iconFrame.size.width;
    CGFloat iconTop = iconFrame.origin.y;
    CGFloat iconBottom = iconFrame.origin.y + iconFrame.size.height;
    CGFloat screenLeft = screen.origin.x;
    CGFloat screenRight = screen.origin.x + screen.size.width;
    CGFloat screenTop = screen.origin.y;
    CGFloat screenBottom = screen.origin.y + screen.size.height;

    for (NSInteger i = 0; i <= steps; i++) {
        CGFloat tRaw = (CGFloat)i / (CGFloat)steps;
        CGFloat t = opening ? tRaw : (1.0 - tRaw);

        CGFloat topP = LMEdgeProgress(t, closeTop, maxDelay);
        CGFloat bottomP = LMEdgeProgress(t, closeBottom, maxDelay);
        CGFloat leftP = LMEdgeProgress(t, closeLeft, maxDelay);
        CGFloat rightP = LMEdgeProgress(t, closeRight, maxDelay);

        CGFloat bounceEnvelope = sinf(MIN(t, 1.0) * M_PI) * bounceAmount * bounceDirection;

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

        CGFloat rTL = startRadius * (1.0 - MIN(topP, leftP)) + endRadius * MIN(topP, leftP);
        CGFloat rTR = startRadius * (1.0 - MIN(topP, rightP)) + endRadius * MIN(topP, rightP);
        CGFloat rBR = startRadius * (1.0 - MIN(bottomP, rightP)) + endRadius * MIN(bottomP, rightP);
        CGFloat rBL = startRadius * (1.0 - MIN(bottomP, leftP)) + endRadius * MIN(bottomP, leftP);

        CGPathRef p = LMRoundedQuadPath(tl, tr, br, bl, rTL, rTR, rBR, rBL);
        [paths addObject:(__bridge_transfer id)p];
    }
    return paths;
}

static void LMCancelCurrentIfAny(void) {
    if (gCurrentState) {
        [gCurrentState.maskShape removeAllAnimations];
        [gCurrentState.contentLayer removeAllAnimations];
        [gCurrentState.maskShape removeFromSuperlayer];
        [gCurrentState.contentLayer removeFromSuperlayer];
        gCurrentState = nil;
    }
}

static void LMEnsureWindow(void) {
    if (gOverlayWindow) return;
    gOverlayWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    gOverlayWindow.windowLevel = UIWindowLevelStatusBar + 1000;
    gOverlayWindow.userInteractionEnabled = NO;
    gOverlayWindow.backgroundColor = [UIColor clearColor];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                gOverlayWindow.windowScene = (UIWindowScene *)scene;
                break;
            }
        }
    }
    gOverlayWindow.hidden = NO;
}

static void LMPlayTransition(CGRect iconFrame, NSString *bundleID, BOOL opening) {
    LMCancelCurrentIfAny();
    LMEnsureWindow();

    CGRect screen = gOverlayWindow.bounds;
    UIImage *snapshot = LMLoadAppSnapshot(bundleID);

    CALayer *contentLayer = [CALayer layer];
    contentLayer.frame = screen;
    contentLayer.contentsGravity = kCAGravityResizeAspectFill;
    if (snapshot) {
        contentLayer.contents = (__bridge id)snapshot.CGImage;
    } else {
        contentLayer.backgroundColor = [UIColor colorWithWhite:0.98 alpha:1.0].CGColor;
    }

    CAShapeLayer *maskShape = [CAShapeLayer layer];
    maskShape.frame = screen;
    contentLayer.mask = maskShape;
    [gOverlayWindow.layer addSublayer:contentLayer];

    NSArray *paths = LMBuildKeyframePaths(iconFrame, screen, opening);

    CAKeyframeAnimation *anim = [CAKeyframeAnimation animationWithKeyPath:@"path"];
    anim.values = paths;
    anim.duration = 0.45;
    anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    anim.fillMode = kCAFillModeForwards;
    anim.removedOnCompletion = NO;

    maskShape.path = (__bridge CGPathRef)paths.lastObject;
    [maskShape addAnimation:anim forKey:@"morph"];

    LMTransitionState *state = [LMTransitionState new];
    state.maskShape = maskShape;
    state.contentLayer = contentLayer;
    state.iconFrame = iconFrame;
    state.bundleID = bundleID;
    state.isOpening = opening;
    gCurrentState = state;

    LMLog(@"Transition %@ played | bundleID: %@ | snapshot: %@",
          opening ? @"OPEN" : @"CLOSE", bundleID ?: @"?", snapshot ? @"yes" : @"no");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((anim.duration + 0.1) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gCurrentState == state) {
            [maskShape removeFromSuperlayer];
            [contentLayer removeFromSuperlayer];
            gCurrentState = nil;
        }
    });
}

@interface SBIconView : UIView
- (id)icon;
@end

%hook SBIconView

- (void)_handleTap {
    @try {
        id icon = [self valueForKey:@"icon"];
        NSString *bundleID = @"";
        if (icon && [icon respondsToSelector:@selector(bundleIdentifier)]) {
            bundleID = [icon performSelector:@selector(bundleIdentifier)] ?: @"";
        }
        CGRect frameInWindow = [self.window convertRect:self.bounds fromView:self];
        LMLog(@"_handleTap fired | bundleID: %@ | frame: %@", bundleID, NSStringFromCGRect(frameInWindow));
        LMPlayTransition(frameInWindow, bundleID, YES);
    } @catch (NSException *e) {
        LMLog(@"Exception in _handleTap: %@", e.reason);
    }
    %orig;
}

%end

// Do them 4 candidate khac de tim dung cho tat animation goc
@interface SBIconController : NSObject
- (void)handleHomeButtonTap;
- (void)_launchFromIconView:(id)iconView withActions:(id)actions;
- (id)launchActionsForIconView:(id)iconView;
- (void)iconManager:(id)manager launchIconForIconView:(id)iconView withActions:(id)actions;
- (void)iconManager:(id)manager willPrepareIconViewForLaunch:(id)iconView;
@end

%hook SBIconController

- (void)handleHomeButtonTap {
    @try {
        if (gCurrentState && gCurrentState.isOpening) {
            CGRect iconFrame = gCurrentState.iconFrame;
            NSString *bundleID = gCurrentState.bundleID;
            LMLog(@"handleHomeButtonTap fired -> play CLOSE | frame: %@", NSStringFromCGRect(iconFrame));
            LMPlayTransition(iconFrame, bundleID, NO);
        } else {
            LMLog(@"handleHomeButtonTap fired but no active open-state - bo qua");
        }
    } @catch (NSException *e) {
        LMLog(@"Exception in handleHomeButtonTap: %@", e.reason);
    }
    %orig;
}

- (void)_launchFromIconView:(id)iconView withActions:(id)actions {
    LMLog(@"[dump-launch] _launchFromIconView:withActions: fired");
    %orig;
}

- (id)launchActionsForIconView:(id)iconView {
    LMLog(@"[dump-launch] launchActionsForIconView: fired");
    return %orig;
}

- (void)iconManager:(id)manager launchIconForIconView:(id)iconView withActions:(id)actions {
    LMLog(@"[dump-launch] iconManager:launchIconForIconView:withActions: fired");
    %orig;
}

- (void)iconManager:(id)manager willPrepareIconViewForLaunch:(id)iconView {
    LMLog(@"[dump-launch] iconManager:willPrepareIconViewForLaunch: fired");
    %orig;
}

%end

%ctor {
    LMLog(@"=== LiquidMorph REAL v4 (dump-launch) loaded | process: %@ | iOS %@ ===",
          [[NSProcessInfo processInfo] processName],
          [[UIDevice currentDevice] systemVersion]);
}
