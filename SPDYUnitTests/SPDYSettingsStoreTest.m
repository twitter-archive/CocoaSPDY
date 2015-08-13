//
//  SPDYSettingsStoreTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier.
//

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>
#import "SPDYSettingsStore.h"
#import "SPDYOrigin.h"
#import "SPDYDefinitions.h"

@interface SPDYSettingsStoreTest : XCTestCase
@end

@implementation SPDYSettingsStoreTest

- (void)testSettings:(SPDYSettings *)settings
{
    SPDY_SETTINGS_ITERATOR(i) {
        settings[i].set = NO;
    }

    settings[SPDY_SETTINGS_DOWNLOAD_BANDWIDTH].set = YES;
    settings[SPDY_SETTINGS_DOWNLOAD_BANDWIDTH].value = 1;
    settings[SPDY_SETTINGS_DOWNLOAD_BANDWIDTH].flags = SPDY_SETTINGS_FLAG_PERSIST_VALUE;

    settings[SPDY_SETTINGS_CLIENT_CERTIFICATE_VECTOR_SIZE].set = YES;
    settings[SPDY_SETTINGS_CLIENT_CERTIFICATE_VECTOR_SIZE].value = 2;
    settings[SPDY_SETTINGS_CLIENT_CERTIFICATE_VECTOR_SIZE].flags = SPDY_SETTINGS_FLAG_PERSIST_VALUE;

    settings[SPDY_SETTINGS_MAX_CONCURRENT_STREAMS].set = YES;
    settings[SPDY_SETTINGS_MAX_CONCURRENT_STREAMS].value = 3;
    settings[SPDY_SETTINGS_MAX_CONCURRENT_STREAMS].flags = 0;  // not persisted
}

#pragma mark Tests

- (void)testSettingsForWrongOrigin
{
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://api.twitter.com" error:nil];
    SPDYOrigin *origin2 = [[SPDYOrigin alloc] initWithString:@"http://api.twitter.com" error:nil];

    SPDYSettings settings[SPDY_SETTINGS_LENGTH];
    [self testSettings:settings];

    [SPDYSettingsStore persistSettings:settings forOrigin:origin];

    SPDYSettings *persistedSettings;
    persistedSettings = [SPDYSettingsStore settingsForOrigin:origin2];  // invalid origin
    XCTAssertTrue(persistedSettings == NULL);
}

- (void)testSettingsForOrigin
{
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://api.twitter.com" error:nil];

    SPDYSettings settings[SPDY_SETTINGS_LENGTH];
    [self testSettings:settings];

    [SPDYSettingsStore persistSettings:settings forOrigin:origin];

    SPDYSettings *persistedSettings;
    persistedSettings = [SPDYSettingsStore settingsForOrigin:origin];
    XCTAssertTrue(persistedSettings != NULL);

    XCTAssertTrue(persistedSettings[SPDY_SETTINGS_DOWNLOAD_BANDWIDTH].set);
    XCTAssertTrue(persistedSettings[SPDY_SETTINGS_CLIENT_CERTIFICATE_VECTOR_SIZE].set);
    XCTAssertFalse(persistedSettings[SPDY_SETTINGS_MAX_CONCURRENT_STREAMS].set);
    XCTAssertFalse(persistedSettings[SPDY_SETTINGS_ROUND_TRIP_TIME].set);

    XCTAssertEqual(persistedSettings[SPDY_SETTINGS_DOWNLOAD_BANDWIDTH].value, 1);
    XCTAssertEqual(persistedSettings[SPDY_SETTINGS_CLIENT_CERTIFICATE_VECTOR_SIZE].value, 2);
}

- (void)testClearSettings
{
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://api.twitter.com" error:nil];

    SPDYSettings settings[SPDY_SETTINGS_LENGTH];
    [self testSettings:settings];

    [SPDYSettingsStore persistSettings:settings forOrigin:origin];
    [SPDYSettingsStore clearSettingsForOrigin:origin];

    SPDYSettings *persistedSettings;
    persistedSettings = [SPDYSettingsStore settingsForOrigin:origin];
    XCTAssertTrue(persistedSettings != NULL);

    XCTAssertFalse(persistedSettings[SPDY_SETTINGS_DOWNLOAD_BANDWIDTH].set);
    XCTAssertFalse(persistedSettings[SPDY_SETTINGS_CLIENT_CERTIFICATE_VECTOR_SIZE].set);
    XCTAssertFalse(persistedSettings[SPDY_SETTINGS_MAX_CONCURRENT_STREAMS].set);
    XCTAssertFalse(persistedSettings[SPDY_SETTINGS_ROUND_TRIP_TIME].set);
}

- (void)testClearSettingsWhenNonePersisted
{
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://api2.twitter.com" error:nil];

    [SPDYSettingsStore clearSettingsForOrigin:origin];

    SPDYSettings *persistedSettings;
    persistedSettings = [SPDYSettingsStore settingsForOrigin:origin];
    XCTAssertTrue(persistedSettings == NULL);
}

@end

