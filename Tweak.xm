#import <UIKit/UIKit.h>

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
@end

@interface SBIconController : NSObject
- (BOOL)iconShouldAllowTap:(SBIconView *)iconView;
@end

%hook SBIconController

- (BOOL)iconShouldAllowTap:(SBIconView *)iconView {
    @try {
        LMLog(@"iconShouldAllowTap fired | iconView class: %@", NSStringFromClass([iconView class]));
    } @catch (NSException *e) {
        LMLog(@"Exception in iconShouldAllowTap: %@", e.reason);
    }
    return %orig;
}

%end

%ctor {
    LMLog(@"=== LiquidMorph loaded into process: %@ | iOS %@ ===",
          [[NSProcessInfo processInfo] processName],
          [[UIDevice currentDevice] systemVersion]);
}
