#import <AppKit/AppKit.h>
#import <ScreenSaver/ScreenSaver.h>

@protocol WorkplaceSaverDiagnostics
@property (readonly) NSInteger diagnosticTaskCount;
@property (readonly) NSInteger diagnosticPendingNoteCount;
@property (readonly) NSString *diagnosticEffectiveWeather;
@property (readonly) NSString *diagnosticStatePath;
@property (readonly) BOOL diagnosticIsOnline;
@property (readonly) BOOL diagnosticUsesCartoonCharacter;
@property (readonly) NSString *diagnosticBackground;
- (void)diagnosticPollState;
@end

@interface DiagnosticSaverWindow : NSWindow
@end
@implementation DiagnosticSaverWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
@end

static void advanceRunLoop(NSTimeInterval seconds) {
    // Merely spinning NSRunLoop does not dispatch AppKit window-server events.
    // In this standalone command-line host there is no NSApplication.run(), so
    // emulate its event pump to receive real occlusion changes and timer events.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    do {
        @autoreleasepool {
            NSDate *slice = [NSDate dateWithTimeIntervalSinceNow:MIN(0.01, MAX(0, deadline.timeIntervalSinceNow))];
            NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:slice
                                                inMode:NSDefaultRunLoopMode dequeue:YES];
            if (event != nil) [NSApp sendEvent:event];
            [NSApp updateWindows];
        }
    } while (deadline.timeIntervalSinceNow > 0);
}

static void printVisibility(NSWindow *window, ScreenSaverView *view, const char *phase) {
    fprintf(stderr, "VISIBILITY %s: visible=%s occlusion=0x%lx activeSpace=%s appActive=%s appHidden=%s key=%s miniaturized=%s viewHidden=%s attached=%s animating=%s\n",
            phase, window.isVisible ? "yes" : "no", (unsigned long)window.occlusionState,
            window.isOnActiveSpace ? "yes" : "no", NSApp.isActive ? "yes" : "no",
            NSApp.isHidden ? "yes" : "no", window.isKeyWindow ? "yes" : "no",
            window.isMiniaturized ? "yes" : "no", view.isHiddenOrHasHiddenAncestor ? "yes" : "no",
            view.window == window ? "yes" : "no", view.isAnimating ? "yes" : "no");
}

static BOOL waitForAnimation(ScreenSaverView *view, BOOL expected) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.0];
    do {
        advanceRunLoop(0.025);
        if (view.isAnimating == expected) return YES;
    } while (deadline.timeIntervalSinceNow > 0);
    return NO;
}

static BOOL waitForCount(id<WorkplaceSaverDiagnostics> view, NSInteger expected, BOOL explicitlyPoll) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:4.0];
    do {
        advanceRunLoop(0.025);
        if (explicitlyPoll) [view diagnosticPollState];
        if (view.diagnosticTaskCount == expected && view.diagnosticPendingNoteCount == expected + 1) return YES;
    } while (deadline.timeIntervalSinceNow > 0);
    return NO;
}

static BOOL writeFixtureWithAge(NSString *path, NSInteger count, NSTimeInterval age) {
    NSMutableArray *tasks = [NSMutableArray array];
    NSMutableArray *notes = [NSMutableArray array];
    for (NSInteger index = 0; index < count; index++) {
        [tasks addObject:@{ @"id": [NSString stringWithFormat:@"diagnostic-%ld", (long)index],
                           @"title": @"屏保跨进程验证", @"status": @"running", @"slot": @(index) }];
    }
    // Different note/task counts detect accidentally projecting notes as work.
    for (NSInteger index = 0; index < count + 1; index++) {
        [notes addObject:@{ @"id": [NSString stringWithFormat:@"pending-%ld", (long)index],
                           @"text": @"门外待办跨进程验证", @"slot": @(index),
                           @"createdAt": @([NSDate date].timeIntervalSinceReferenceDate - 18000) }];
    }
    NSDictionary *snapshot = @{ @"schemaVersion": @1, @"mode": @"automatic",
        @"preferredPosture": @"sitting", @"tasks": tasks, @"pendingNotes": notes,
        @"updatedAt": @([NSDate date].timeIntervalSinceReferenceDate - age),
        @"isOnline": @YES, @"demoRunning": @NO };
    NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:nil];
    return [data writeToFile:path options:NSDataWritingAtomic error:nil];
}

static BOOL writeFixture(NSString *path, NSInteger count) {
    return writeFixtureWithAge(path, count, 0);
}

static NSData *renderPNG(ScreenSaverView *view) {
    NSBitmapImageRep *image = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:image];
    return [image representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

static BOOL saveSettledFrame(ScreenSaverView *view, NSString *basePath, NSString *phase) {
    // Prime the native transition, then render its settled result without starting a timer.
    renderPNG(view);
    advanceRunLoop(0.7);
    NSString *path = [[basePath stringByDeletingPathExtension]
        stringByAppendingFormat:@"-%@.png", phase];
    NSData *png = renderPNG(view);
    if (png == nil || ![png writeToFile:path options:NSDataWritingAtomic error:nil]) return NO;
    printf("FRAME: %s\n", path.UTF8String);
    return YES;
}

static BOOL verifyIndependentSceneContexts(Class principal, NSString *statePath) {
    NSScreen *screen = NSScreen.screens.firstObject;
    if (screen == nil) return NO;
    NSMutableDictionary *desktop = [NSMutableDictionary dictionary];
    NSMutableDictionary *saver = [NSMutableDictionary dictionary];
    for (NSScreen *display in NSScreen.screens) {
        CGDirectDisplayID number = [display.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(number);
        if (uuid == NULL) return NO;
        NSString *identity = [@"display:" stringByAppendingString:CFBridgingRelease(CFUUIDCreateString(NULL, uuid))];
        CFRelease(uuid);
        desktop[identity] = @"room";
        saver[identity] = @"outdoors";
    }
    NSWindow *window = [[NSWindow alloc] initWithContentRect:screen.frame
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    ScreenSaverView *view = [[principal alloc] initWithFrame:NSMakeRect(0, 0, screen.frame.size.width, screen.frame.size.height) isPreview:NO];
    window.contentView = view;
    id<WorkplaceSaverDiagnostics> diagnostic = (id<WorkplaceSaverDiagnostics>)view;
    NSWindow *previewFlagWindow = [[NSWindow alloc] initWithContentRect:screen.frame
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    previewFlagWindow.releasedWhenClosed = NO;
    ScreenSaverView *fullPreviewFlagView = [[principal alloc] initWithFrame:view.bounds isPreview:YES];
    previewFlagWindow.contentView = fullPreviewFlagView;
    ScreenSaverView *thumbnail = [[principal alloc] initWithFrame:NSMakeRect(0, 0, 320, 180) isPreview:YES];
    BOOL passed = YES;
    for (NSUInteger stage = 0; stage < 2; stage++) {
        if (!writeFixture(statePath, 1)) { passed = NO; break; }
        NSMutableDictionary *snapshot = [[NSJSONSerialization JSONObjectWithData:
            [NSData dataWithContentsOfFile:statePath] options:0 error:nil] mutableCopy];
        snapshot[@"world"] = @{ @"weather": @"rain", @"weatherMode": @"manual", @"timeMode": @"night",
            @"displayScenes": stage == 0 ? desktop : saver,
            @"screenSaverDisplayScenes": stage == 0 ? saver : desktop };
        NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:nil];
        if (![data writeToFile:statePath options:NSDataWritingAtomic error:nil]) { passed = NO; break; }
        [diagnostic diagnosticPollState];
        [(id<WorkplaceSaverDiagnostics>)fullPreviewFlagView diagnosticPollState];
        [(id<WorkplaceSaverDiagnostics>)thumbnail diagnosticPollState];
        NSString *expected = stage == 0 ? @"outdoors" : @"room";
        if (![diagnostic.diagnosticBackground isEqualToString:expected]
            || ![[(id<WorkplaceSaverDiagnostics>)fullPreviewFlagView diagnosticBackground] isEqualToString:expected]
            || ![[(id<WorkplaceSaverDiagnostics>)thumbnail diagnosticBackground] isEqualToString:@"room"]
            || view.isAnimating || fullPreviewFlagView.isAnimating || thumbnail.isAnimating
            || window.isVisible || previewFlagWindow.isVisible) {
            passed = NO; break;
        }
    }
    [view stopAnimation];
    [fullPreviewFlagView stopAnimation];
    [thumbnail stopAnimation];
    [window close];
    [previewFlagWindow close];
    if (passed) printf("PASS: actual saver and full-screen preview-flag instance follow the independent saver map; small preview stays room; no window or timer started\n");
    else fprintf(stderr, "FAIL: saver used desktop scene choices or started a visible diagnostic window\n");
    return passed;
}

/// A separate host verifies the actual compiled plug-in without changing system settings.
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "Usage: SaverHost /absolute/VirtualWorkplace.saver /absolute/output.png [--window] [--state-roundtrip | --headless-roundtrip]\n");
            return 2;
        }
        NSApplication *application = [NSApplication sharedApplication];
        NSString *bundlePath = [NSString stringWithUTF8String:argv[1]];
        NSString *outputPath = [NSString stringWithUTF8String:argv[2]];
        NSError *error = nil;
        BOOL showWindow = NO;
        BOOL verifyState = NO;
        BOOL headlessRoundtrip = NO;
        for (int index = 3; index < argc; index++) {
            if (strcmp(argv[index], "--window") == 0) showWindow = YES;
            if (strcmp(argv[index], "--state-roundtrip") == 0) verifyState = YES;
            if (strcmp(argv[index], "--headless-roundtrip") == 0) headlessRoundtrip = YES;
        }
        showWindow = !headlessRoundtrip && (showWindow || verifyState);
        verifyState |= headlessRoundtrip;
        [application setActivationPolicy:showWindow ? NSApplicationActivationPolicyRegular : NSApplicationActivationPolicyAccessory];
        [application finishLaunching];
        advanceRunLoop(0.05);
        NSString *fixtureDirectory = nil;
        if (verifyState) {
            fixtureDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [@"VirtualWorkplaceSaverCheck-" stringByAppendingString:NSUUID.UUID.UUIDString]];
            if (![[NSFileManager defaultManager] createDirectoryAtPath:fixtureDirectory
                    withIntermediateDirectories:YES attributes:nil error:&error]) return 1;
            NSString *statePath = [fixtureDirectory stringByAppendingPathComponent:@"state.json"];
            if (!writeFixture(statePath, 1)) return 1;
            setenv("WORKPLACE_STATE_PATH", statePath.fileSystemRepresentation, 1);
        }
        NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
        error = nil;
        if (bundle == nil || ![bundle loadAndReturnError:&error]) {
            fprintf(stderr, "Cannot load saver bundle: %s\n", [[error description] UTF8String]);
            return 1;
        }
        Class principal = bundle.principalClass;
        if (principal == Nil || ![principal isSubclassOfClass:ScreenSaverView.class]) {
            fprintf(stderr, "Bundle principal class is not a ScreenSaverView subclass\n");
            return 1;
        }
        NSRect frame = NSMakeRect(0, 0, 1440, 900);
        ScreenSaverView *view = [[principal alloc] initWithFrame:frame isPreview:YES];
        if (view == nil) {
            fprintf(stderr, "Cannot initialize screen saver principal class\n");
            return 1;
        }
        if (![view respondsToSelector:@selector(diagnosticUsesCartoonCharacter)]
                || ![(id<WorkplaceSaverDiagnostics>)view diagnosticUsesCartoonCharacter]) {
            fprintf(stderr, "FAIL: actual saver bundle did not load the cartoon character asset\n");
            return 1;
        }
        printf("PASS: actual saver bundle loaded the cartoon character asset\n");
        NSWindow *window = [[DiagnosticSaverWindow alloc] initWithContentRect:frame
                                                    styleMask:NSWindowStyleMaskBorderless
                                                      backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed = NO;
        window.title = @"虚拟工位 · 独立屏保生命周期测试";
        window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
        window.contentView = view;
        [window center];
        if (showWindow) {
            [application activateIgnoringOtherApps:YES];
            [window makeKeyAndOrderFront:nil];
            [window orderFrontRegardless];
            advanceRunLoop(0.3);
            printVisibility(window, view, "ordered-front");
        }
        [view startAnimation];
        advanceRunLoop(0.5);
        BOOL animatedWhileVisible = view.isAnimating;
        NSUInteger lifecycleChecks = 0;
        if (showWindow) {
            for (NSUInteger cycle = 0; cycle < 10; cycle++) {
                [view startAnimation];
                if (!waitForAnimation(view, YES)) {
                    printVisibility(window, view, "start-failed");
                    fprintf(stderr, "FAIL: visible animation did not start (cycle %lu)\n", cycle);
                    return 1;
                }
                lifecycleChecks++;
                [view stopAnimation];
                if (!waitForAnimation(view, NO)) {
                    fprintf(stderr, "FAIL: animation did not stop (cycle %lu)\n", cycle);
                    return 1;
                }
                lifecycleChecks++;
            }
            [view startAnimation];
            printVisibility(window, view, "before-hide");
            [window orderOut:nil];
            if (!waitForAnimation(view, NO)) {
                fprintf(stderr, "FAIL: hidden window kept animating\n"); return 1;
            }
            lifecycleChecks++;
            printVisibility(window, view, "after-hide");
            [window orderFrontRegardless];
            [application activateIgnoringOtherApps:YES];
            [window makeKeyAndOrderFront:nil];
            // A screen saver host issues a new start request when presenting the
            // saver again. orderOut/orderFront can retain the same cached
            // occlusion flags, so that pair is not itself a guaranteed signal.
            [view startAnimation];
            if (!waitForAnimation(view, YES)) {
                printVisibility(window, view, "show-resume-failed");
                fprintf(stderr, "FAIL: animation did not resume after showing window\n"); return 1;
            }
            lifecycleChecks++;
            [NSWorkspace.sharedWorkspace.notificationCenter postNotificationName:NSWorkspaceScreensDidSleepNotification object:nil];
            if (!waitForAnimation(view, NO)) {
                fprintf(stderr, "FAIL: simulated screen sleep kept animating\n"); return 1;
            }
            lifecycleChecks++;
            [NSWorkspace.sharedWorkspace.notificationCenter postNotificationName:NSWorkspaceScreensDidWakeNotification object:nil];
            if (!waitForAnimation(view, YES)) {
                fprintf(stderr, "FAIL: animation did not resume after simulated wake\n"); return 1;
            }
            lifecycleChecks++;
        }
        if (verifyState) {
            if (![view respondsToSelector:@selector(diagnosticTaskCount)]
                    || ![view respondsToSelector:@selector(diagnosticPendingNoteCount)]
                    || ![view respondsToSelector:@selector(diagnosticEffectiveWeather)]
                    || (headlessRoundtrip && ![view respondsToSelector:@selector(diagnosticPollState)])) {
                fprintf(stderr, "FAIL: rebuild saver to include read-only diagnostic probes\n"); return 1;
            }
            id<WorkplaceSaverDiagnostics> diagnostic = (id<WorkplaceSaverDiagnostics>)view;
            NSString *statePath = [fixtureDirectory stringByAppendingPathComponent:@"state.json"];
            NSString *threePath = [fixtureDirectory stringByAppendingPathComponent:@"three.json"];
            NSString *zeroPath = [fixtureDirectory stringByAppendingPathComponent:@"zero.json"];
            if (![diagnostic.diagnosticStatePath isEqualToString:statePath]
                    || !waitForCount(diagnostic, 1, headlessRoundtrip)
                    || !writeFixture(threePath, 3) || !writeFixture(zeroPath, 0)) {
                fprintf(stderr, "FAIL: initial isolated snapshot not readable\n"); return 1;
            }
            if (headlessRoundtrip && !saveSettledFrame(view, outputPath, @"tasks-1")) return 1;
            NSTask *writer = [[NSTask alloc] init];
            writer.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
            writer.arguments = @[@"-c", @"sleep 1.3; cp \"$2\" \"$1.pending\" && mv \"$1.pending\" \"$1\"; sleep 1.3; cp \"$3\" \"$1.pending\" && mv \"$1.pending\" \"$1\"",
                                 @"saver-fixture-writer", statePath, threePath, zeroPath];
            if (![writer launchAndReturnError:&error]) {
                fprintf(stderr, "FAIL: cannot launch isolated fixture writer\n"); return 1;
            }
            BOOL sawThree = waitForCount(diagnostic, 3, headlessRoundtrip);
            if (headlessRoundtrip && sawThree && !saveSettledFrame(view, outputPath, @"tasks-3")) return 1;
            BOOL sawZero = sawThree && waitForCount(diagnostic, 0, headlessRoundtrip);
            if (headlessRoundtrip && sawZero && !saveSettledFrame(view, outputPath, @"tasks-0")) return 1;
            [writer waitUntilExit];
            if (!sawThree || !sawZero || writer.terminationStatus != 0) {
                fprintf(stderr, "FAIL: cross-process snapshot changes were not observed\n"); return 1;
            }
            printf("PASS: separate writer updated isolated snapshot; saver observed tasks 1 -> 3 -> 0 and independent pending notes 2 -> 4 -> 1\n");
            if (headlessRoundtrip) {
                NSUInteger weatherSlot = (NSUInteger)([NSDate date].timeIntervalSince1970 / 2700);
                NSString *randomWeather = diagnostic.diagnosticEffectiveWeather;
                if (![@[@"clear", @"cloudy", @"rain", @"snow", @"thunderstorm"] containsObject:randomWeather]) {
                    fprintf(stderr, "FAIL: saver did not resolve a supported random weather state\n"); return 1;
                }
                NSMutableDictionary *cleared = [[NSJSONSerialization JSONObjectWithData:
                    [NSData dataWithContentsOfFile:statePath] options:NSJSONReadingMutableContainers error:nil] mutableCopy];
                cleared[@"pendingNotes"] = @[];
                NSData *clearedData = [NSJSONSerialization dataWithJSONObject:cleared options:0 error:nil];
                if (![clearedData writeToFile:statePath options:NSDataWritingAtomic error:nil]) return 1;
                [diagnostic diagnosticPollState];
                BOOL sameSlot = weatherSlot == (NSUInteger)([NSDate date].timeIntervalSince1970 / 2700);
                if (diagnostic.diagnosticPendingNoteCount != 0
                    || (sameSlot && ![diagnostic.diagnosticEffectiveWeather isEqualToString:randomWeather])) {
                    fprintf(stderr, "FAIL: clearing pending notes changed random weather in actual saver\n"); return 1;
                }
                cleared[@"world"] = @{ @"weather": @"thunderstorm", @"weatherMode": @"manual", @"timeMode": @"day" };
                clearedData = [NSJSONSerialization dataWithJSONObject:cleared options:0 error:nil];
                if (![clearedData writeToFile:statePath options:NSDataWritingAtomic error:nil]) return 1;
                [diagnostic diagnosticPollState];
                if (![diagnostic.diagnosticEffectiveWeather isEqualToString:@"thunderstorm"]) {
                    fprintf(stderr, "FAIL: saver did not preserve the manual weather choice\n"); return 1;
                }
                printf("PASS: saver resolved random weather independently of overdue notes and respected manual weather\n");
                if (!writeFixture(statePath, 3)) return 1;
                [diagnostic diagnosticPollState];
                if (diagnostic.diagnosticTaskCount != 3 || diagnostic.diagnosticPendingNoteCount != 4) return 1;
                NSData *corrupt = [@"{invalid JSON" dataUsingEncoding:NSUTF8StringEncoding];
                if (![corrupt writeToFile:statePath options:NSDataWritingAtomic error:nil]) return 1;
                [diagnostic diagnosticPollState];
                if (diagnostic.diagnosticTaskCount != 3 || diagnostic.diagnosticPendingNoteCount != 4) {
                    fprintf(stderr, "FAIL: corrupt state did not preserve last valid snapshot\n"); return 1;
                }
                if (!saveSettledFrame(view, outputPath, @"corrupt-preserved-3")) return 1;
                if (!writeFixtureWithAge(statePath, 2, 30)) return 1;
                [diagnostic diagnosticPollState];
                if (diagnostic.diagnosticTaskCount != 2 || diagnostic.diagnosticPendingNoteCount != 3 || diagnostic.diagnosticIsOnline) {
                    fprintf(stderr, "FAIL: stale snapshot did not resolve to offline\n"); return 1;
                }
                if (!saveSettledFrame(view, outputPath, @"offline-2")) return 1;
                if (view.isAnimating) {
                    fprintf(stderr, "FAIL: headless state polling unexpectedly started animation\n"); return 1;
                }
                printf("PASS: corrupt state preserved last valid 3 tasks; stale heartbeat resolved offline; no animation timer started\n");
                if (!verifyIndependentSceneContexts(principal, statePath)) return 1;
                printf("NOT TESTED: visible lifecycle, system sandbox, lock screen, and multiple displays\n");
            }
            [[NSFileManager defaultManager] removeItemAtPath:fixtureDirectory error:nil];
        }
        NSData *png = renderPNG(view);
        if (png == nil || ![png writeToFile:outputPath options:NSDataWritingAtomic error:&error]) {
            fprintf(stderr, "Cannot write saver rendering: %s\n", [[error description] UTF8String]);
            return 1;
        }
        [view stopAnimation];
        advanceRunLoop(0.05);
        if (view.isAnimating) {
            fprintf(stderr, "Saver timer is still running after stopAnimation\n");
            return 1;
        }
        if (showWindow) {
            [view startAnimation];
            if (!waitForAnimation(view, YES)) return 1;
            [window close];
            if (!waitForAnimation(view, NO)) {
                fprintf(stderr, "FAIL: closing window kept animating\n"); return 1;
            }
            lifecycleChecks++;
            printf("PASS: %lu lifecycle checks (10 start/stop cycles, hidden stop + host show/start, screen sleep/wake, close)\n", lifecycleChecks);
        }
        [window orderOut:nil];
        [window close];
        printf("PASS: bundle loaded; principal=%s; PNG=%lu bytes; stopped timer=yes; visible animation=%s\n",
               NSStringFromClass(principal).UTF8String, (unsigned long)png.length,
               showWindow ? (animatedWhileVisible ? "yes" : "no (window may be occluded)") : "not requested");
        printf("%s\n", outputPath.UTF8String);
        return 0;
    }
}
