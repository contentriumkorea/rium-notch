// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#ifndef MEDIAREMOTEADAPTER_ADAPTER_GET_H
#define MEDIAREMOTEADAPTER_ADAPTER_GET_H

#import <Foundation/Foundation.h>

NSDictionary *internal_get(BOOL isTestMode, BOOL *timedOut);
NSNumber *fallbackElapsedNow(NSDictionary *data, NSTimeInterval now);
void normalizeElapsedNow(NSMutableDictionary *data, BOOL micros, NSTimeInterval now);
void limitArtwork(NSMutableDictionary *data);

#endif // MEDIAREMOTEADAPTER_ADAPTER_GET_H
