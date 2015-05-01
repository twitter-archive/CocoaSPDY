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
#define INTERVAL_SEC    0.1000
#define LOWER_BOUND_SEC 0.0999
#define UPPER_BOUND_SEC (INTERVAL_SEC * 100)

- (void)testSystemTimeDoesMarchForward
{
    SPDYTimeInterval t1 = [SPDYStopwatch currentSystemTime];
    // Real sleep just to make sure currentSystemTime works
    usleep(INTERVAL_USEC);
    SPDYTimeInterval t2 = [SPDYStopwatch currentSystemTime];
    STAssertTrue(t2 > t1, nil);
    STAssertTrue((t2 - t1) < UPPER_BOUND_SEC, nil);
}

- (void)testAbsoluteTimeDoesMarchForward
{
    SPDYTimeInterval t1 = [SPDYStopwatch currentAbsoluteTime];
    // Real sleep just to make sure currentAbsoluteTime works
    usleep(INTERVAL_USEC);
    SPDYTimeInterval t2 = [SPDYStopwatch currentAbsoluteTime];
    STAssertTrue(t2 > t1, nil);
    STAssertTrue((t2 - t1) < UPPER_BOUND_SEC, nil);
}

- (void)testStopwatchElapsed
{
    SPDYStopwatch *stopwatch = [[SPDYStopwatch alloc] init];
    [SPDYStopwatch sleep:INTERVAL_SEC];
    SPDYTimeInterval elapsed = stopwatch.elapsedSeconds;
    STAssertTrue(elapsed >= LOWER_BOUND_SEC, @"expect %f to be >= to %f", elapsed, LOWER_BOUND_SEC);
    STAssertTrue(elapsed < UPPER_BOUND_SEC, nil);
}

- (void)testStopwatchMultipleElapsed
{
    SPDYStopwatch *stopwatch = [[SPDYStopwatch alloc] init];
    [SPDYStopwatch sleep:INTERVAL_SEC];
    SPDYTimeInterval elapsed1 = stopwatch.elapsedSeconds;
    [SPDYStopwatch sleep:INTERVAL_SEC];
    SPDYTimeInterval elapsed2 = stopwatch.elapsedSeconds;
    STAssertTrue(elapsed1 >= LOWER_BOUND_SEC, @"expect %f to be >= to %f", elapsed1, LOWER_BOUND_SEC);
    STAssertTrue(elapsed2 >= 2 * LOWER_BOUND_SEC, @"expect %f to be >= to %f", elapsed2, 2 * LOWER_BOUND_SEC);
    STAssertTrue(elapsed1 < elapsed2, @"expect %f to be < %f", elapsed1, elapsed2);
}

- (void)testStopwatchMultipleReset
{
    SPDYStopwatch *stopwatch = [[SPDYStopwatch alloc] init];
    [SPDYStopwatch sleep:INTERVAL_SEC];
    SPDYTimeInterval elapsed1 = stopwatch.elapsedSeconds;
    [SPDYStopwatch sleep:INTERVAL_SEC];
    [stopwatch reset];
    SPDYTimeInterval elapsed2 = stopwatch.elapsedSeconds;
    STAssertTrue(elapsed2 < elapsed1, nil);
}

- (void)testStopwatchStartTime
{
    SPDYTimeInterval startTime = [SPDYStopwatch currentAbsoluteTime];
    SPDYTimeInterval startSystemTime = [SPDYStopwatch currentSystemTime];

    SPDYStopwatch *stopwatch = [[SPDYStopwatch alloc] init];
    STAssertTrue(stopwatch.startTime >= startTime, nil);
    STAssertTrue(stopwatch.startSystemTime >= startSystemTime, nil);

    [SPDYStopwatch sleep:INTERVAL_SEC];
    [stopwatch reset];

    startTime += LOWER_BOUND_SEC;
    startSystemTime += LOWER_BOUND_SEC;
    STAssertTrue(stopwatch.startTime >= startTime, nil);
    STAssertTrue(stopwatch.startSystemTime >= startSystemTime, nil);
    STAssertTrue(stopwatch.startTime < (startTime + UPPER_BOUND_SEC), nil);
    STAssertTrue(stopwatch.startSystemTime < (startSystemTime + UPPER_BOUND_SEC), nil);
}

@end

