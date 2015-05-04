//
//  SPDYStopwatch.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier.
//

#import "SPDYDefinitions.h"

@interface SPDYStopwatch : NSObject

+ (SPDYTimeInterval)currentSystemTime;
+ (SPDYTimeInterval)currentAbsoluteTime;

@property (nonatomic, readonly) SPDYTimeInterval startTime;
@property (nonatomic, readonly) SPDYTimeInterval startSystemTime;

- (id)init;
- (void)reset;
- (SPDYTimeInterval)elapsedSeconds;

// Unit tests only
#if COVERAGE
+ (void)sleep:(SPDYTimeInterval)delay;
#endif

@end
