//
//  SPDYStopwatchTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier on 9/19/14.
//

#import <SenTestingKit/SenTestingKit.h>
#import <Foundation/Foundation.h>
#import "SPDYStopwatch.h"

@interface SPDYStopwatchTest : SenTestCase
@end

@implementation SPDYStopwatchTest

#pragma mark Tests

// Note: usleep will sleep for equal to or greater than the specified time interval, but not less.
// It may sleep for much longer if a big context switch occurs, so we use a large band here
// as we aren't mocking out the underlying time system call.
#define INTERVAL_USEC   100000
#define INTERVAL_SEC    0.1
#define UPPER_BOUND_SEC (INTERVAL_SEC * 100)

- (void)testTimeDoesMarchForward
{
    SPDYTimeInterval t1 = [SPDYStopwatch currentSystemTime];
    usleep(INTERVAL_USEC);
    SPDYTimeInterval t2 = [SPDYStopwatch currentSystemTime];
    STAssertTrue(t2 > t1, nil);
    STAssertTrue((t2 - t1) < UPPER_BOUND_SEC, nil);
}

- (void)testStopwatchElapsed
{
    SPDYStopwatch *stopwatch = [[SPDYStopwatch alloc] init];
    usleep(INTERVAL_USEC);
    SPDYTimeInterval elapsed = stopwatch.elapsedSeconds;
    STAssertTrue(elapsed >= INTERVAL_SEC, @"expect %f to be >= to %f", elapsed, INTERVAL_SEC);
    STAssertTrue(elapsed < UPPER_BOUND_SEC, nil);
}

- (void)testStopwatchMultipleElapsed
{
    SPDYStopwatch *stopwatch = [[SPDYStopwatch alloc] init];
    usleep(INTERVAL_USEC);
    SPDYTimeInterval elapsed1 = stopwatch.elapsedSeconds;
    usleep(INTERVAL_USEC);
    SPDYTimeInterval elapsed2 = stopwatch.elapsedSeconds;
    STAssertTrue(elapsed1 >= INTERVAL_SEC, @"expect %f to be >= to %f", elapsed1, INTERVAL_SEC);
    STAssertTrue(elapsed2 >= 2 * INTERVAL_SEC, @"expect %f to be >= to %f", elapsed2, 2 * INTERVAL_SEC);
    STAssertTrue(elapsed1 < elapsed2, @"expect %f to be < %f", elapsed1, elapsed2);
}

- (void)testStopwatchMultipleReset
{
    SPDYStopwatch *stopwatch = [[SPDYStopwatch alloc] init];
    usleep(INTERVAL_USEC);
    SPDYTimeInterval elapsed1 = stopwatch.elapsedSeconds;
    usleep(INTERVAL_USEC);
    [stopwatch reset];
    SPDYTimeInterval elapsed2 = stopwatch.elapsedSeconds;
    STAssertTrue(elapsed2 < elapsed1, nil);
}

@end

