#import <UIKit/UIKit.h>
#import <objc/runtime.h>

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
        LMLog(@"_handleTap fired | icon: %@", name);
    } @catch (NSException *e) {
        LMLog(@"Exception in _handleTap: %@", e.reason);
    }
    %orig;
}

%end

%hook SBIconController

- (void)iconManager:(id)manager launchIcon:(id)icon location:(CGPoint)location animated:(BOOL)animated completionHandler:(id)handler {
    @try {
        NSString *name = @"unknown";
        if (icon && [icon respondsToSelector:@selector(displayName)]) {
            name = [icon performSelector:@selector(displayName)] ?: @"unknown";
        }
        LMLog(@"launchIcon fired | icon: %@ | location: (%.1f, %.1f) | animated: %d",
              name, location.x, location.y, animated);
    } @catch (NSException *e) {
        LMLog(@"Exception in launchIcon hook: %@", e.reason);
    }
    %orig;
}

%end

%ctor {
    LMLog(@"=== LiquidMorph loaded | process: %@ | iOS %@ ===",
          [[NSProcessInfo processInfo] processName],
          [[UIDevice currentDevice] systemVersion]);
}
