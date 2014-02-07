//
//  SPDYSettingsStore.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "This file requires ARC support."
#endif

#import "SPDYSettingsStore.h"
#import "SPDYOrigin.h"

// Convenience wrapper for SPDYSettings array
@interface SPDYSettingsObj : NSObject
@property (nonatomic, readonly) SPDYSettings *settings;
@end

@implementation SPDYSettingsObj
{
    SPDYSettings _settings[SPDY_SETTINGS_LENGTH];
}

- (id)init
{
    self = [super init];
    if (self) {
        SPDY_SETTINGS_ITERATOR(i) {
            _settings[i].set = NO;
        }
    }
    return self;
}

- (SPDYSettings *)settings
{
    return _settings;
}

@end

@interface SPDYSettingsStore ()
+ (NSMutableDictionary *)_sharedStore;
@end

@implementation SPDYSettingsStore

+ (SPDYSettings *)settingsForOrigin:(SPDYOrigin *)origin
{
    NSMutableDictionary *sharedStore = [SPDYSettingsStore _sharedStore];
    SPDYSettingsObj *storedSettingsObj = sharedStore[origin];

    if (!storedSettingsObj) {
        return NULL;
    }

    return storedSettingsObj.settings;
}

+ (void)persistSettings:(SPDYSettings *)settings forOrigin:(SPDYOrigin *)origin
{
    NSMutableDictionary *sharedStore = [SPDYSettingsStore _sharedStore];
    SPDYSettingsObj *storedSettingsObj = sharedStore[origin];

    if (!storedSettingsObj) {
        storedSettingsObj = [[SPDYSettingsObj alloc] init];
        sharedStore[origin] = storedSettingsObj;
    }

    SPDYSettings *storedSettings = storedSettingsObj.settings;

    SPDY_SETTINGS_ITERATOR(i) {
        if (settings[i].set && settings[i].flags == SPDY_SETTINGS_FLAG_PERSIST_VALUE) {
            storedSettings[i].set = YES;
            storedSettings[i].flags = SPDY_SETTINGS_FLAG_PERSISTED;
            storedSettings[i].value = settings[i].value;
        }
    }
}


+ (void)clearSettingsForOrigin:(SPDYOrigin *)origin
{
    NSMutableDictionary *sharedStore = [SPDYSettingsStore _sharedStore];
    SPDYSettingsObj *storedSettingsObj = sharedStore[origin];

    if (!storedSettingsObj) {
        return;
    }

    SPDYSettings *storedSettings = storedSettingsObj.settings;

    SPDY_SETTINGS_ITERATOR(i) {
        storedSettings[i].set = NO;
    }
}

#pragma mark private methods

+ (NSMutableDictionary *)_sharedStore
{
    static dispatch_once_t pred;
    static NSMutableDictionary *sharedStore;
    dispatch_once(&pred, ^{
        sharedStore = [[NSMutableDictionary alloc] init];
    });
    return sharedStore;
}

@end
