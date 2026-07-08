#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

static NSString *const kLogPath = @"/var/mobile/Documents/LiquidMorph.log";
static UIWindow *gOverlayWindow = nil;

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

        if (i == 0) {
            CGPathMoveToPoint(path, NULL, p1.x, p1.y);
        } else {
            CGPathAddLineToPoint(path, NULL, p1.x, p1.y);
        }
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

static void LMPlayMorphOverlay(CGRect iconFrame) {
    if (!gOverlayWindow) {
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

    CGRect screen = gOverlayWindow.bounds;
    CGFloat iconCenterXNorm = (iconFrame.origin.x + iconFrame.size.width / 2.0) / screen.size.width;
    CGFloat iconCenterYNorm = (iconFrame.origin.y + iconFrame.size.height / 2.0) / screen.size.height;

    // closeness: 1 = sat canh do, 0 = sat canh doi dien
    CGFloat closeBottom = iconCenterYNorm;
    CGFloat closeTop = 1.0 - iconCenterYNorm;
    CGFloat closeRight = iconCenterXNorm;
    CGFloat closeLeft = 1.0 - iconCenterXNorm;

    CAShapeLayer *shape = [CAShapeLayer layer];
    shape.fillColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.3 alpha:0.9].CGColor;
    shape.strokeColor = [UIColor whiteColor].CGColor;
    shape.lineWidth = 2.0;
    shape.frame = screen;
    [gOverlayWindow.layer addSublayer:shape];

    NSInteger steps = 20;
    NSMutableArray *paths = [NSMutableArray array];
    CGFloat startRadius = 80.0;
    CGFloat maxDelay = 0.45;

    CGFloat iconLeft = iconFrame.origin.x;
    CGFloat iconRight = iconFrame.origin.x + iconFrame.size.width;
    CGFloat iconTop = iconFrame.origin.y;
    CGFloat iconBottom = iconFrame.origin.y + iconFrame.size.height;

    CGFloat screenLeft = screen.origin.x;
    CGFloat screenRight = screen.origin.x + screen.size.width;
    CGFloat screenTop = screen.origin.y;
    CGFloat screenBottom = screen.origin.y + screen.size.height;

    for (NSInteger i = 0; i <= steps; i++) {
        CGFloat t = (CGFloat)i / (CGFloat)steps;

        // Tien do rieng cho tung canh (tren/duoi/trai/phai)
        CGFloat topP = LMEdgeProgress(t, closeTop, maxDelay);
        CGFloat bottomP = LMEdgeProgress(t, closeBottom, maxDelay);
        CGFloat leftP = LMEdgeProgress(t, closeLeft, maxDelay);
        CGFloat rightP = LMEdgeProgress(t, closeRight, maxDelay);

        // Y cua canh tren/duoi phu thuoc DUNG tien do cua canh do
        CGFloat topY = iconTop + (screenTop - iconTop) * topP;
        CGFloat bottomY = iconBottom + (screenBottom - iconBottom) * bottomP;

        // QUAN TRONG: X cua moi goc phu thuoc CA tien do canh ngang (tren/duoi)
        // LAN tien do canh doc (trai/phai) - day la thu tao ra hinh thang that,
        // khac voi ban truoc dung chung 1 leftX/rightX cho ca 2 canh.
        CGFloat topLeftX = iconLeft + (screenLeft - iconLeft) * ((topP + leftP) * 0.5);
        CGFloat topRightX = iconRight + (screenRight - iconRight) * ((topP + rightP) * 0.5);
        CGFloat bottomLeftX = iconLeft + (screenLeft - iconLeft) * ((bottomP + leftP) * 0.5);
        CGFloat bottomRightX = iconRight + (screenRight - iconRight) * ((bottomP + rightP) * 0.5);

        CGPoint tl = CGPointMake(topLeftX, topY);
        CGPoint tr = CGPointMake(topRightX, topY);
        CGPoint br = CGPointMake(bottomRightX, bottomY);
        CGPoint bl = CGPointMake(bottomLeftX, bottomY);

        CGFloat rTL = startRadius * (1.0 - MIN(topP, leftP));
        CGFloat rTR = startRadius * (1.0 - MIN(topP, rightP));
        CGFloat rBR = startRadius * (1.0 - MIN(bottomP, rightP));
        CGFloat rBL = startRadius * (1.0 - MIN(bottomP, leftP));

        CGPathRef p = LMRoundedQuadPath(tl, tr, br, bl, rTL, rTR, rBR, rBL);
        [paths addObject:(__bridge_transfer id)p];
    }

    CAKeyframeAnimation *anim = [CAKeyframeAnimation animationWithKeyPath:@"path"];
    anim.values = paths;
    anim.duration = 2.0;
    anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    anim.fillMode = kCAFillModeForwards;
    anim.removedOnCompletion = NO;

    shape.path = (__bridge CGPathRef)paths.lastObject;
    [shape addAnimation:anim forKey:@"morph"];

    LMLog(@"Morph v3 played | iconCenterNorm: (%.2f, %.2f)", iconCenterXNorm, iconCenterYNorm);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [shape removeFromSuperlayer];
    });
}

@interface SBIconView : UIView
- (id)icon;
@end
@interface SBIcon : NSObject
- (NSString *)displayName;
@end

%hook SBIconView
- (void)_handleTap {
    @try {
        id icon = [self valueForKey:@"icon"];
        NSString *name = @"unknown";
        if (icon && [icon respondsToSelector:@selector(displayName)]) {
            name = [icon performSelector:@selector(displayName)] ?: @"unknown";
        }
        CGRect frameInWindow = [self.window convertRect:self.bounds fromView:self];
        LMLog(@"_handleTap fired | icon: %@ | frame: %@", name, NSStringFromCGRect(frameInWindow));
        LMPlayMorphOverlay(frameInWindow);
    } @catch (NSException *e) {
        LMLog(@"Exception in _handleTap: %@", e.reason);
    }
    %orig;
}
%end

%ctor {
    LMLog(@"=== LiquidMorph v3 loaded | process: %@ | iOS %@ ===",
          [[NSProcessInfo processInfo] processName],
          [[UIDevice currentDevice] systemVersion]);
}
