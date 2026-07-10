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

// Bien co: chi bat dau ghi log animation SAU KHI ban cham icon, va tu dong
// tat sau 2 giay - de tranh log qua nhieu thu khong lien quan (dong ho,
// keyboard, hieu ung khac cua he thong).
static BOOL gCaptureEnabled = NO;

static void LMDescribeAnimation(CALayer *layer, NSString *key, CAAnimation *anim) {
    @try {
        NSString *layerClass = NSStringFromClass([layer class]);
        NSString *layerDesc = [layer description];
        NSString *animClass = NSStringFromClass([anim class]);
        NSString *keyPath = @"?";
        NSString *valuesDesc = @"";

        if ([anim isKindOfClass:[CABasicAnimation class]]) {
            CABasicAnimation *b = (CABasicAnimation *)anim;
            keyPath = b.keyPath ?: @"?";
            valuesDesc = [NSString stringWithFormat:@"from:%@ to:%@", b.fromValue, b.toValue];
        } else if ([anim isKindOfClass:[CAKeyframeAnimation class]]) {
            CAKeyframeAnimation *k = (CAKeyframeAnimation *)anim;
            keyPath = k.keyPath ?: @"?";
            valuesDesc = [NSString stringWithFormat:@"valuesCount:%lu", (unsigned long)k.values.count];
        } else if ([anim isKindOfClass:[CATransition class]]) {
            keyPath = @"(CATransition)";
        } else if ([anim isKindOfClass:[CAAnimationGroup class]]) {
            CAAnimationGroup *g = (CAAnimationGroup *)anim;
            keyPath = [NSString stringWithFormat:@"(group, %lu sub-anims)", (unsigned long)g.animations.count];
        }

        LMLog(@"[anim-dump] layer:%@ | key:%@ | animClass:%@ | keyPath:%@ | duration:%.3f | %@ | layerBounds:%@ layerPos:%@",
              layerClass, key, animClass, keyPath, anim.duration, valuesDesc,
              NSStringFromCGRect(layer.bounds), NSStringFromCGPoint(layer.position));
    } @catch (NSException *e) {
        LMLog(@"[anim-dump] Exception describing animation: %@", e.reason);
    }
}

%hook CALayer

- (void)addAnimation:(CAAnimation *)anim forKey:(NSString *)key {
    if (gCaptureEnabled) {
        LMDescribeAnimation(self, key, anim);
    }
    %orig;
}

%end

@interface SBIconView : UIView
- (id)icon;
@end

%hook SBIconView

- (void)_handleTap {
    @try {
        id icon = [self valueForKey:@"icon"];
        NSString *className = NSStringFromClass([icon class]);

        BOOL isFolderLike = [className.lowercaseString containsString:@"folder"] ||
                             [className.lowercaseString containsString:@"library"] ||
                             [className.lowercaseString containsString:@"cluster"];
        if (isFolderLike) {
            %orig;
            return;
        }

        LMLog(@"=== _handleTap - BAT DAU GHI ANIMATION trong 2 giay ===");
        gCaptureEnabled = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            gCaptureEnabled = NO;
            LMLog(@"=== KET THUC ghi animation ===");
        });
    } @catch (NSException *e) {
        LMLog(@"Exception in _handleTap: %@", e.reason);
    }
    %orig;
}

%end

%ctor {
    LMLog(@"=== LiquidMorph ANIM-DUMP loaded | process: %@ | iOS %@ ===",
          [[NSProcessInfo processInfo] processName],
          [[UIDevice currentDevice] systemVersion]);
}
