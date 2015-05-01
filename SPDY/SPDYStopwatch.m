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
static double __machTimebaseToSeconds;
static mach_timebase_info_data_t __machTimebase;
#if COVERAGE
static SPDYTimeInterval __currentTimeOffset;
#endif

+ (void)initialize
{
    dispatch_once(&__initTimebase, ^{
        kern_return_t status = mach_timebase_info(&__machTimebase);
        // Everything will be 0 if this fails.
        if (status != KERN_SUCCESS) {
            __machTimebase.numer = 0;
            __machTimebase.denom = 1;
        }
        __machTimebaseToSeconds = (double)__machTimebase.numer / ((double)__machTimebase.denom * 1000000000.0);
#if COVERAGE
        __currentTimeOffset = 0;
#endif
    });
}

+ (SPDYTimeInterval)currentSystemTime
{
#if COVERAGE
    return (SPDYTimeInterval)mach_absolute_time() * __machTimebaseToSeconds + __currentTimeOffset;
#else
    return (SPDYTimeInterval)mach_absolute_time() * __machTimebaseToSeconds;
#endif
}

+ (SPDYTimeInterval)currentAbsoluteTime
{
#if COVERAGE
    return CFAbsoluteTimeGetCurrent() + __currentTimeOffset;
#else
    return CFAbsoluteTimeGetCurrent();
#endif
}

#if COVERAGE
+ (void)sleep:(SPDYTimeInterval)delay
{
    __currentTimeOffset += delay;
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
