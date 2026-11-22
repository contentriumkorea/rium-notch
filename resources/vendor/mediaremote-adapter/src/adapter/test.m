// Copyright (c) 2025 Alexander5015
// This file is licensed under the BSD 3-Clause License.

#import <Foundation/Foundation.h>
#include <signal.h>

#import "MediaRemoteAdapter.h"
#import "adapter/get.h"
#import "test/NowPlayingTest.h"
#import "utility/helpers.h"

static NSTask *nowPlayingClientHelperTask = nil;
static NSFileHandle *helperInput = nil;
static NSFileHandle *helperOutput = nil;

void cleanup_helper() {
    if (nowPlayingClientHelperTask && helperInput && helperOutput) {
        @try {
            [helperInput writeData:[@"cleanup\n"
                                       dataUsingEncoding:NSUTF8StringEncoding]];
            [helperInput closeFile];
        } @catch (NSException *exception) {
        }

        // Graceful shutdown with timeout
        NSTimeInterval timeout = 2.0;
        NSDate *cleanupDeadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
        while (nowPlayingClientHelperTask.isRunning &&
               [cleanupDeadline timeIntervalSinceNow] > 0) {
            [NSThread sleepForTimeInterval:0.1];
        }

        if (nowPlayingClientHelperTask.isRunning) {
            @try {
                [nowPlayingClientHelperTask terminate];
            } @catch (NSException *exception) {
            }

            NSDate *terminationDeadline =
                [NSDate dateWithTimeIntervalSinceNow:1.0];
            while (nowPlayingClientHelperTask.isRunning &&
                   [terminationDeadline timeIntervalSinceNow] > 0) {
                [NSThread sleepForTimeInterval:0.1];
            }
        }

        if (nowPlayingClientHelperTask.isRunning) {
            // Force kill as last resort
            kill(nowPlayingClientHelperTask.processIdentifier, SIGKILL);
        }

        @try {
            if (helperOutput.readabilityHandler) {
                helperOutput.readabilityHandler = nil;
            }
            [helperOutput closeFile];
        } @catch (__unused NSException *exception) {
        }

        @
        try {
            [nowPlayingClientHelperTask waitUntilExit];
        } @catch (__unused NSException *exception) {
        }
    } else if (nowPlayingClientHelperTask) {
        @try {
            [nowPlayingClientHelperTask terminate];
            [nowPlayingClientHelperTask waitUntilExit];
        } @catch (__unused NSException *exception) {
        }
    }
    nowPlayingClientHelperTask = nil;
    helperInput = nil;
    helperOutput = nil;
}

void cleanup_and_exit() {
    cleanup_helper();
    exit(1);
}

void handleSignal(int signal) {
    if (signal == SIGINT || signal == SIGTERM)
        cleanup_and_exit();
}

extern void adapter_test(void) {
    @autoreleasepool {
        NSDictionary *fallback = @{@"playing": @YES, @"elapsedTime": @10, @"duration": @100,
                                   @"timestamp": [NSDate dateWithTimeIntervalSince1970:100]};
        NSCAssert([fallbackElapsedNow(fallback, 105) doubleValue] == 15, @"missing-rate estimate failed");
        NSMutableDictionary *invalid = [fallback mutableCopy];
        invalid[@"playbackRate"] = @2;
        NSCAssert(fallbackElapsedNow(invalid, 105) == nil, @"explicit rate must not be replaced");
        [invalid removeObjectForKey:@"playbackRate"]; invalid[@"playing"] = @NO;
        NSCAssert(fallbackElapsedNow(invalid, 105) == nil, @"paused time must not be advanced");
        NSCAssert(fallbackElapsedNow(fallback, 99) == nil && [fallbackElapsedNow(fallback, 191) doubleValue] == 100,
                  @"future anchor or track end handled incorrectly");
        NSMutableDictionary *paused = [@{@"playing": @NO, @"elapsedTime": @10, @"elapsedTimeNow": @25,
                                          @"playbackRate": @1} mutableCopy];
        normalizeElapsedNow(paused, NO, 105);
        NSCAssert([paused[@"elapsedTimeNow"] doubleValue] == 10, @"paused position advanced with stale rate");
        NSMutableDictionary *pausedMicros = [@{@"playing": @NO, @"elapsedTimeMicros": @10000000,
                                                @"elapsedTimeNowMicros": @25000000} mutableCopy];
        normalizeElapsedNow(pausedMicros, YES, 105);
        NSCAssert([pausedMicros[@"elapsedTimeNowMicros"] longLongValue] == 10000000, @"paused microsecond position advanced");
        NSMutableDictionary *running = [fallback mutableCopy];
        normalizeElapsedNow(running, NO, 105);
        NSCAssert([running[@"elapsedTimeNow"] doubleValue] == 15, @"playing fallback was not retained");
        running[@"playbackRate"] = @2; running[@"elapsedTimeNow"] = @12;
        normalizeElapsedNow(running, NO, 105);
        NSCAssert([running[@"elapsedTimeNow"] doubleValue] == 20, @"elapsed time was not refreshed with explicit playback rate");
        normalizeElapsedNow(running, NO, 200);
        NSCAssert([running[@"elapsedTimeNow"] doubleValue] == 100, @"projected playback time exceeded duration");
        running[@"playbackRate"] = @0; normalizeElapsedNow(running, NO, 110);
        NSCAssert([running[@"elapsedTimeNow"] doubleValue] == 10, @"zero playback rate advanced");
        running[@"playbackRate"] = @(-1); running[@"elapsedTimeNow"] = @11;
        normalizeElapsedNow(running, NO, 110);
        NSCAssert([running[@"elapsedTimeNow"] doubleValue] == 0, @"reverse playback did not stop at zero");
        running[@"playbackRate"] = @(-17); normalizeElapsedNow(running, NO, 110);
        NSCAssert(running[@"elapsedTimeNow"] == nil && [running[@"elapsedTime"] doubleValue] == 10, @"invalid playback rate retained an estimate");
        running[@"playbackRate"] = @2; running[@"elapsedTimeNow"] = @11; normalizeElapsedNow(running, NO, 99);
        NSCAssert(running[@"elapsedTimeNow"] == nil, @"future playback anchor retained an estimate");
        running[@"playbackRate"] = @17; running[@"elapsedTimeNow"] = @11; normalizeElapsedNow(running, NO, 105);
        NSCAssert(running[@"elapsedTimeNow"] == nil, @"unsupported playback rate retained an estimate");
        [running removeObjectForKey:@"playbackRate"]; running[@"elapsedTimeNow"] = @11; normalizeElapsedNow(running, NO, 99);
        NSCAssert(running[@"elapsedTimeNow"] == nil, @"future fallback anchor retained an estimate");
        NSMutableDictionary *stream = [fallback mutableCopy];
        [stream removeObjectForKey:@"duration"];
        normalizeElapsedNow(stream, NO, 105);
        NSCAssert([stream[@"elapsedTimeNow"] doubleValue] == 15, @"missing-duration fallback did not advance");
        stream[@"playbackRate"] = @2; normalizeElapsedNow(stream, NO, 105);
        NSCAssert([stream[@"elapsedTimeNow"] doubleValue] == 20, @"missing-duration explicit rate did not advance");
        stream[@"duration"] = @0; stream[@"playbackRate"] = @(-1); normalizeElapsedNow(stream, NO, 120);
        NSCAssert([stream[@"elapsedTimeNow"] doubleValue] == 0, @"unbounded reverse time fell below zero");
        stream[@"duration"] = @(-1); normalizeElapsedNow(stream, NO, 105);
        NSCAssert(stream[@"elapsedTimeNow"] == nil, @"invalid duration retained an estimate");
        NSMutableDictionary *streamMicros = [@{@"playing": @YES, @"playbackRate": @2,
             @"elapsedTimeMicros": @10000000, @"timestampEpochMicros": @100000000} mutableCopy];
        normalizeElapsedNow(streamMicros, YES, 105);
        NSCAssert([streamMicros[@"elapsedTimeNowMicros"] longLongValue] == 20000000, @"missing-duration microseconds failed");
        NSMutableDictionary *runningMicros = [@{@"playing": @YES, @"playbackRate": @2,
             @"elapsedTimeMicros": @10000000, @"durationMicros": @100000000,
             @"timestampEpochMicros": @100000000, @"elapsedTimeNowMicros": @11000000} mutableCopy];
        normalizeElapsedNow(runningMicros, YES, 105);
        NSCAssert([runningMicros[@"elapsedTimeNowMicros"] longLongValue] == 20000000, @"microsecond playback position was not refreshed");
        [runningMicros removeObjectForKey:@"playbackRate"]; normalizeElapsedNow(runningMicros, YES, 105);
        NSCAssert([runningMicros[@"elapsedTimeNowMicros"] longLongValue] == 15000000, @"microsecond missing-rate fallback failed");
        normalizeElapsedNow(runningMicros, YES, 99);
        NSCAssert(runningMicros[@"elapsedTimeNowMicros"] == nil, @"future microsecond anchor retained an estimate");
        NSMutableDictionary *artwork = [@{@"title": @"Track", @"elapsedTime": @12,
                                           @"artworkData": [NSMutableData dataWithLength:1000000],
                                           @"artworkMimeType": @"image/jpeg"} mutableCopy];
        limitArtwork(artwork);
        NSCAssert(artwork[@"artworkData"] != nil, @"bounded artwork was discarded");
        NSData *tinyPNG = [[NSData alloc] initWithBase64EncodedString:@"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2ioAAAAASUVORK5CYII=" options:0];
        NSMutableData *largePNG = [tinyPNG mutableCopy];
        [largePNG setLength:1000001];
        artwork[@"artworkData"] = largePNG;
        limitArtwork(artwork);
        NSCAssert([artwork[@"artworkData"] length] > 0 && [artwork[@"artworkData"] length] <= 1000000 &&
                  [artwork[@"artworkMimeType"] isEqual:@"image/png"], @"large artwork was not resized");
        artwork[@"artworkData"] = [largePNG base64EncodedStringWithOptions:0];
        limitArtwork(artwork);
        NSCAssert([artwork[@"artworkData"] isKindOfClass:[NSData class]] &&
                  [artwork[@"artworkData"] length] > 0 && [artwork[@"artworkData"] length] <= 1000000,
                  @"large encoded artwork was not resized");
        artwork[@"artworkData"] = [NSMutableData dataWithLength:1000001];
        limitArtwork(artwork);
        NSCAssert(artwork[@"artworkData"] == nil && artwork[@"artworkMimeType"] == nil &&
                  [artwork[@"elapsedTime"] intValue] == 12 && [artwork[@"title"] isEqual:@"Track"],
                  @"oversized artwork must not discard playback metadata");
        signal(SIGINT, handleSignal);
        signal(SIGTERM, handleSignal);
        signal(SIGPIPE, SIG_IGN);

        // If adapterOutput is not null, we know the adapter is working
        // correctly
        NSDictionary *result = internal_get(YES, NULL);
        if (result != nil) {
            cleanup_helper();
            exit(0);
        }

        // Instantiate helper to ensure MediaRemote has data
        // We only do this if adapterOutput is null to minimize the impact on
        // other apps using the adapter
        NSString *helperPath =
            NSProcessInfo.processInfo
                .environment[@"MEDIAREMOTEADAPTER_TEST_CLIENT_PATH"];
        if (helperPath.length == 0) {
            printErrf(@"Test client path is missing");
            cleanup_helper();
            exit(1);
        }

        // Set up pipes for communication with the helper process
        NSPipe *inputPipe = [NSPipe pipe];
        NSPipe *outputPipe = [NSPipe pipe];

        nowPlayingClientHelperTask = [[NSTask alloc] init];
        nowPlayingClientHelperTask.launchPath = helperPath;
        nowPlayingClientHelperTask.standardInput = inputPipe;
        nowPlayingClientHelperTask.standardOutput = outputPipe;

        @try {
            [nowPlayingClientHelperTask launch];
        } @catch (NSException *exception) {
            printErrf(
                @"Exeption while trying to launch test client task: %@: %@",
                exception.name, exception.reason);
            cleanup_helper();
            exit(2);
        }

        helperInput = inputPipe.fileHandleForWriting;
        helperOutput = outputPipe.fileHandleForReading;

        dispatch_semaphore_t setupSem = dispatch_semaphore_create(0);
        NSMutableString *lineBuffer = [[NSMutableString alloc] init];
        helperOutput.readabilityHandler = ^(NSFileHandle *fh) {
          @autoreleasepool {
              NSData *chunk = [fh availableData];
              if (chunk.length == 0) {
                  fh.readabilityHandler = nil;
                  return;
              }

              // Validate UTF-8 encoding with graceful degradation
              NSString *chunkStr =
                  [[NSString alloc] initWithData:chunk
                                        encoding:NSUTF8StringEncoding];
              if (!chunkStr) {
                  return;
              }

              [lineBuffer appendString:chunkStr];

              NSUInteger bufferLength = [lineBuffer length];
              NSUInteger searchStart = 0;

              while (searchStart < bufferLength) {
                  NSRange remainingRange =
                      NSMakeRange(searchStart, bufferLength - searchStart);
                  NSRange nlRange = [lineBuffer rangeOfString:@"\n"
                                                      options:0
                                                        range:remainingRange];

                  if (nlRange.location == NSNotFound) {
                      break;
                  }

                  NSUInteger lineLength = nlRange.location - searchStart;
                  NSString *line = [lineBuffer
                      substringWithRange:NSMakeRange(searchStart, lineLength)];

                  if ([line isEqualToString:@"setup_done"]) {
                      fh.readabilityHandler = nil;
                      dispatch_semaphore_signal(setupSem);
                      return;
                  }

                  searchStart = nlRange.location + nlRange.length;
              }
              if (searchStart > 0) {
                  [lineBuffer
                      deleteCharactersInRange:NSMakeRange(0, searchStart)];
              }
          }
        };
        // Wait for setup_done or timeout
        NSTimeInterval setupTimeout = 3.0;
        dispatch_time_t timeout = dispatch_time(
            DISPATCH_TIME_NOW, (int64_t)(setupTimeout * NSEC_PER_SEC));
        long result_wait = dispatch_semaphore_wait(setupSem, timeout);

        if (helperOutput.readabilityHandler) {
            helperOutput.readabilityHandler = nil;
        }

        if (result_wait != 0) {
            printErrf(@"The test client did not signal setup_done within %.1fs",
                      setupTimeout);
            cleanup_helper();
            exit(3);
        }

        // Small delay to ensure new data is available, for some reason the
        // first call to adapter_get slows down MediaRemote?
        [NSThread sleepForTimeInterval:0.01];

        result = internal_get(YES, NULL);
        if (result != nil) {
            cleanup_helper();
            exit(0);
        }

        cleanup_helper();
        exit(4);
    }
}
