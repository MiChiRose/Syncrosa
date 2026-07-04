#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"
#import "IGLogger.h"

static void IGWriteStartupLog(NSString *message) {
    if (![IGLogger desktopDiagnosticsEnabled]) return;

    @autoreleasepool {
        NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Desktop/Syncrosa-objc-startup.log"];
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], message];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!handle) {
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
            handle = [NSFileHandle fileHandleForWritingAtPath:path];
        }
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    }
}

static void IGUncaughtExceptionHandler(NSException *exception) {
    IGWriteStartupLog([NSString stringWithFormat:@"Uncaught exception: %@ - %@", exception.name, exception.reason]);
    IGWriteStartupLog([NSString stringWithFormat:@"Stack: %@", exception.callStackSymbols]);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSSetUncaughtExceptionHandler(&IGUncaughtExceptionHandler);
        IGWriteStartupLog(@"main entered");
        NSApplication *application = [NSApplication sharedApplication];
        IGWriteStartupLog(@"NSApplication created");
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [application setDelegate:delegate];
        IGWriteStartupLog(@"delegate installed, entering run loop");
        [application run];
        IGWriteStartupLog(@"application run loop exited");
    }
    return 0;
}
