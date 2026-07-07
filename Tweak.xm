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
        if (![fm fileExistsAtPath:kLogPath]) {
            [fm createFileAtPath:kLogPath contents:nil attributes:nil];
        }
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
        if (handle) {
            [handle seekToEndOfFile];
            [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [handle closeFile];
        }
    } @catch (NSException *e) {
        NSLog(@"[LiquidMorph] Log write failed: %@", e.reason);
    }
    NSLog(@"[LiquidMorph] %@", message);
}

static UIBezierPath *LMRoundedPath(CGRect rect, CGFloat radius) {
    if (radius < 0) radius = 0;
    return [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];
}

static void LMPlayMorphOverlay(CGRect iconFrame) {
    UIWindow *window = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { window = w; break; }
    }
    if (!window) window = [UIApplication sharedApplication].windows.firstObject;
    if (!window) { LMLog(@"Morph: khong tim thay window"); return; }

    CGRect screenBounds = window.bounds;

    CAShapeLayer *shape = [CAShapeLayer layer];
    shape.fillColor = [UIColor colorWithWhite:1.0 alpha:0.85].CGColor;
    shape.frame = screenBounds;
    shape.zPosition = 9999;
    [window.layer addSublayer:shape];

    NSInteger steps = 10;
    NSMutableArray *paths = [NSMutableArray array];

    CGFloat startRadius = 22.0;
    CGFloat endRadius = 0.0;

    for (NSInteger i = 0; i <= steps; i++) {
        CGFloat t = (CGFloat)i / (CGFloat)steps;

        CGFloat sizeT = t;
        CGFloat overshoot = 0.0;
        if (t > 0.6 && t < 1.0) {
            CGFloat local = (t - 0.6) / 0.4;
            overshoot = sinf(local * M_PI) * 0.04;
        }

        CGFloat x = iconFrame.origin.x + (screenBounds.origin.x - iconFrame.origin.x) * sizeT;
        CGFloat y = iconFrame.origin.y + (screenBounds.origin.y - iconFrame.origin.y) * sizeT;
        CGFloat w = iconFrame.size.width + (screenBounds.size.width - iconFrame.size.width) * (sizeT + overshoot);
        CGFloat h = iconFrame.size.height + (screenBounds.size.height - iconFrame.size.height) * (sizeT + overshoot);

        CGRect frame = CGRectMake(x, y, w, h);

        CGFloat radiusT = powf(t, 2.2);
        CGFloat radius = startRadius + (endRadius - startRadius) * radiusT;

        [paths addObject:(__bridge id)LMRoundedPath(frame, radius).CGPath];
    }

    CAKeyframeAnimation *anim = [CAKeyframeAnimation animationWithKeyPath:@"path"];
    anim.values = paths;
    anim.duration = 0.55;
    anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    anim.fillMode = kCAFillModeForwards;
    anim.removedOnCompletion = NO;

    shape.path = (__bridge CGPathRef)paths.lastObject;
    [shape addAnimation:anim forKey:@"morph"];

    LMLog(@"Morph overlay played | from: %@ to: %@", NSStringFromCGRect(iconFrame), NSStringFromCGRect(screenBounds));

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
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
    LMLog(@"=== LiquidMorph loaded | process: %@ | iOS %@ ===",
          [[NSProcessInfo processInfo] processName],
          [[UIDevice currentDevice] systemVersion]);
}
