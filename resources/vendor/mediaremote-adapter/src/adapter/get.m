// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#include <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <dispatch/dispatch.h>
#include <math.h>

#import "MediaRemoteAdapter.h"
#import "adapter/env.h"
#import "adapter/get.h"
#import "adapter/globals.h"
#import "adapter/keys.h"
#import "adapter/now_playing.h"
#import "utility/helpers.h"

#define GET_TIMEOUT_MILLIS 2000
#define JSON_NULL @"null"

// The adapter's --now estimate otherwise freezes at the anchor when rate is absent.
static NSNumber *fallbackElapsedNowInUnits(NSDictionary *data, BOOL micros, NSTimeInterval now) {
    id playing = data[kMRAPlaying], rate = data[kMRAPlaybackRate];
    id timestamp = data[micros ? kMRATimestampEpochMicros : kMRATimestamp];
    id elapsed = data[micros ? kMRAElapsedTimeMicros : kMRAElapsedTime];
    id duration = data[micros ? kMRADurationMicros : kMRADuration];
    if (![playing isKindOfClass:[NSNumber class]] || ![playing boolValue] || rate != nil ||
        !(micros ? [timestamp isKindOfClass:[NSNumber class]] : [timestamp isKindOfClass:[NSDate class]]) ||
        ![elapsed isKindOfClass:[NSNumber class]] ||
        (duration && ![duration isKindOfClass:[NSNumber class]])) return nil;
    double factor = micros ? 1000000.0 : 1.0;
    double base = [elapsed doubleValue], length = [duration doubleValue];
    double age = now - (micros ? [timestamp doubleValue] / factor : [(NSDate *)timestamp timeIntervalSince1970]);
    if (!isfinite(base) || !isfinite(length) || !isfinite(age) || base < 0 || length < 0 ||
        (length > 0 && base > length) || age < 0) return nil;
    double result = base + age * factor;
    if (!isfinite(result)) return nil;
    if (length > 0) result = fmin(length, result);
    return @(micros ? floor(result) : result);
}
NSNumber *fallbackElapsedNow(NSDictionary *data, NSTimeInterval now) { return fallbackElapsedNowInUnits(data, NO, now); }

void normalizeElapsedNow(NSMutableDictionary *data, BOOL micros, NSTimeInterval now) {
    NSString *source = micros ? kMRAElapsedTimeMicros : kMRAElapsedTime;
    NSString *target = micros ? kMRAElapsedTimeNowMicros : kMRAElapsedTimeNow;
    // The earlier adapter estimate may use an invalid or future time anchor.
    [data removeObjectForKey:target];
    id playing = data[kMRAPlaying];
    if ([playing isKindOfClass:[NSNumber class]] && ![playing boolValue]) {
        // A player may retain its old rate after pausing.
        id elapsed = data[source];
        if ([elapsed isKindOfClass:[NSNumber class]]) data[target] = elapsed;
    } else if ([playing isKindOfClass:[NSNumber class]] && [playing boolValue]) {
        id rate = data[kMRAPlaybackRate];
        if (!rate) {
            NSNumber *fallback = fallbackElapsedNowInUnits(data, micros, now);
            if (fallback) data[target] = fallback;
            return;
        }
        id timestamp = data[micros ? kMRATimestampEpochMicros : kMRATimestamp];
        id elapsed = data[micros ? kMRAElapsedTimeMicros : kMRAElapsedTime];
        id duration = data[micros ? kMRADurationMicros : kMRADuration];
        if (![rate isKindOfClass:[NSNumber class]] || ![elapsed isKindOfClass:[NSNumber class]] ||
            (duration && ![duration isKindOfClass:[NSNumber class]]) ||
            !(micros ? [timestamp isKindOfClass:[NSNumber class]] : [timestamp isKindOfClass:[NSDate class]])) return;
        double factor = micros ? 1000000.0 : 1.0;
        double anchor = micros ? [timestamp doubleValue] / factor : [timestamp timeIntervalSince1970];
        double base = [elapsed doubleValue], length = [duration doubleValue], speed = [rate doubleValue];
        double age = now - anchor;
        if (!isfinite(base) || !isfinite(length) || !isfinite(speed) || !isfinite(age) ||
            base < 0 || length < 0 || (length > 0 && base > length) || speed < -16 || speed > 16 || age < 0) return;
        double projected = base + age * factor * speed;
        if (!isfinite(projected)) return;
        double bounded = fmax(0, length > 0 ? fmin(length, projected) : projected);
        data[micros ? kMRAElapsedTimeNowMicros : kMRAElapsedTimeNow] = @(micros ? floor(bounded) : bounded);
    }
}

void limitArtwork(NSMutableDictionary *data) {
    id artwork = data[kMRAArtworkData];
    NSUInteger size = [artwork isKindOfClass:[NSData class]] ? [artwork length] :
        ([artwork isKindOfClass:[NSString class]] ? [artwork lengthOfBytesUsingEncoding:NSUTF8StringEncoding] : 0);
    if (size <= 1000000) return;
    // Keep the image small enough for base64 and the bounded metadata reply.
    NSData *input = nil;
    if (size <= 20000000) {
        input = [artwork isKindOfClass:[NSData class]] ? artwork :
            [[NSData alloc] initWithBase64EncodedString:artwork options:0];
    }
    CGImageSourceRef source = input ? CGImageSourceCreateWithData((__bridge CFDataRef)input, NULL) : NULL;
    CGImageRef image = source ? CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)@{
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize: @448
    }) : NULL;
    if (source) CFRelease(source);
    NSMutableData *output = [NSMutableData data];
    CGImageDestinationRef destination = image ? CGImageDestinationCreateWithData((__bridge CFMutableDataRef)output, CFSTR("public.png"), 1, NULL) : NULL;
    if (destination) {
        CGImageDestinationAddImage(destination, image, NULL);
        if (!CGImageDestinationFinalize(destination)) [output setLength:0];
        CFRelease(destination);
    }
    if (image) CGImageRelease(image);
    if (output.length > 0 && output.length <= 1000000) {
        data[kMRAArtworkData] = output;
        data[kMRAArtworkMimeType] = @"image/png";
    } else {
        [data removeObjectForKey:kMRAArtworkData];
        [data removeObjectForKey:kMRAArtworkMimeType];
    }
}

NSDictionary *internal_get(BOOL isTestMode, BOOL *timedOut) {
    if (timedOut) *timedOut = NO;
    NSString *micros_option = getEnvOption(@"micros");
    __block const bool convert_micros = micros_option != nil;

    NSString *human_readable_option = getEnvOption(@"human-readable");
    __block const bool human_readable = human_readable_option != nil;

    NSString *now_option = getEnvOption(@"now");
    __block const bool calculate_now = now_option != nil;

    NSString *no_artwork_option = getEnvOption(@"no-artwork");
    const bool no_artwork = no_artwork_option != nil;

    NSString *allow_missing_title_option = getEnvOption(@"allow-missing-title");
    const bool allow_missing_title = allow_missing_title_option != nil;

    __block NSMutableDictionary *liveData = [NSMutableDictionary dictionary];
    __block BOOL isFromTestClient = NO;

    dispatch_group_t group = dispatch_group_create();

    // PID and Bundle Identifier
    dispatch_group_enter(group);
    g_mediaRemote.getNowPlayingApplicationPID(
        g_serialdispatchQueue, ^(int pid) {
          if (pid != 0) {
              liveData[kMRAProcessIdentifier] = @(pid);
              bool ok = appForPID(pid, ^(NSRunningApplication *process) {
                if (process.bundleIdentifier != nil) {
                    liveData[kMRABundleIdentifier] = process.bundleIdentifier;
                }
                dispatch_group_leave(group);
              });
              if (!ok) {
                  dispatch_group_leave(group);
              }
          } else {
              dispatch_group_leave(group);
          }
        });

    // Now Playing Client
    dispatch_group_enter(group);
    g_mediaRemote.getNowPlayingClient(g_serialdispatchQueue, ^(id client) {
      NSString *parentAppBundleID = nil;
      if (client && [client respondsToSelector:@selector
                            (parentApplicationBundleIdentifier)]) {
          parentAppBundleID = [client
              performSelector:@selector(parentApplicationBundleIdentifier)];
      }
      if (parentAppBundleID) {
          liveData[kMRAParentApplicationBundleIdentifier] = parentAppBundleID;
      }
      dispatch_group_leave(group);
    });

    // Is Playing
    dispatch_group_enter(group);
    g_mediaRemote.getNowPlayingApplicationIsPlaying(
        g_serialdispatchQueue, ^(bool isPlaying) {
          liveData[kMRAPlaying] = @(isPlaying);
          dispatch_group_leave(group);
        });

    dispatch_group_enter(group);
    g_mediaRemote.getNowPlayingInfo(g_serialdispatchQueue, ^(
                                        NSDictionary *information) {
      NSString *serviceIdentifier =
          information[kMRMediaRemoteNowPlayingInfoServiceIdentifier];
      if (!isTestMode &&
          [serviceIdentifier
              isEqualToString:@"com.vandenbe.MediaRemoteAdapter.TestClient"]) {
          isFromTestClient = YES;
          dispatch_group_leave(group);
          return;
      }
      NSDictionary *converted = convertNowPlayingInformation(
          information, convert_micros, calculate_now, no_artwork);
      [liveData addEntriesFromDictionary:converted];
      dispatch_group_leave(group);
    });

    // Wait for all async callbacks or timeout
    dispatch_time_t timeout =
        dispatch_time(DISPATCH_TIME_NOW, GET_TIMEOUT_MILLIS * NSEC_PER_MSEC);
    long result = dispatch_group_wait(group, timeout);

    if (result != 0) {
        if (timedOut) *timedOut = YES;
        printErrf(
            @"Reading now playing information timed out after %d milliseconds",
            GET_TIMEOUT_MILLIS);
        return nil;
    }

    if (isFromTestClient) {
        return nil;
    }

    limitArtwork(liveData);
    if (calculate_now) {
        NSTimeInterval observedUptime = [NSProcessInfo processInfo].systemUptime;
        normalizeElapsedNow(liveData, convert_micros, [NSDate date].timeIntervalSince1970);
        if (liveData[convert_micros ? kMRAElapsedTimeNowMicros : kMRAElapsedTimeNow]) {
            liveData[@"positionObservedUptime"] = @(observedUptime);
        }
    }

    if (human_readable) {
        makePayloadHumanReadable(liveData);
    }

    if (!allMandatoryPayloadKeysSet(liveData, allow_missing_title)) {
        return nil;
    }

    return liveData;
}

void adapter_get() {
    BOOL timedOut = NO;
    NSDictionary *liveData = internal_get(NO, &timedOut);
    if (timedOut) fail(@"Reading now playing information timed out");

    NSString *human_readable_option = getEnvOption(@"human-readable");
    const bool human_readable = human_readable_option != nil;

    NSString *resultStr = nil;
    if (!liveData) {
        resultStr = JSON_NULL;
    } else {
        resultStr = serializeJsonDictionarySafe(liveData, human_readable);
        if (!resultStr) {
            fail(@"Failed to serialize now playing information");
        }
    }

    printOut(resultStr);
}

extern void adapter_get_env() { adapter_get(); }
