//
//  SPDYStopwatch.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier
//

#import <mach/mach_time.h>
#import "SPDYStopwatch.h"

@implementation SPDYStopwatch

static dispatch_once_t __initTimebase;
static dispatch_queue_t __stopwatchQueue;
static double __machTimebaseToSeconds;
static mach_timebase_info_data_t __machTimebase;
static SPDYTimeInterval __currentTimeOffset;

+ (void)initialize
{
    dispatch_once(&__initTimebase, ^{
        __stopwatchQueue = dispatch_queue_create("com.twitter.SPDYStopwatchQueue", DISPATCH_QUEUE_SERIAL);
        __currentTimeOffset = 0;
        kern_return_t status = mach_timebase_info(&__machTimebase);
        // Everything will be 0 if this fails.
        if (status != KERN_SUCCESS) {
            __machTimebase.numer = 0;
            __machTimebase.denom = 1;
        }
        __machTimebaseToSeconds = (double)__machTimebase.numer / ((double)__machTimebase.denom * 1000000000.0);
    });
}

+ (SPDYTimeInterval)currentSystemTime
{
    SPDYTimeInterval __block offset = 0;
#if COVERAGE
    dispatch_sync(__stopwatchQueue, ^{
        offset = __currentTimeOffset;
    });
#endif
    uint64_t now = mach_absolute_time();
    return (SPDYTimeInterval)now * __machTimebaseToSeconds + offset;
}

+ (SPDYTimeInterval)currentAbsoluteTime
{
    SPDYTimeInterval __block offset = 0;
#if COVERAGE
    dispatch_sync(__stopwatchQueue, ^{
        offset = __currentTimeOffset;
    });
#endif
    return CFAbsoluteTimeGetCurrent() + offset;
}

#if COVERAGE
+ (void)sleep:(SPDYTimeInterval)delay
{
    dispatch_async(__stopwatchQueue, ^{
        __currentTimeOffset += delay;
    });
}
#endif

- (id)init
{
    self = [super init];
    if (self) {
        _startTime = [SPDYStopwatch currentAbsoluteTime];
        _startSystemTime = [SPDYStopwatch currentSystemTime];
    }
    return self;
}

- (void)reset
{
    _startTime = [SPDYStopwatch currentAbsoluteTime];
    _startSystemTime = [SPDYStopwatch currentSystemTime];
}

- (SPDYTimeInterval)elapsedSeconds
{
    return [SPDYStopwatch currentAbsoluteTime] - _startTime;
}

@end
