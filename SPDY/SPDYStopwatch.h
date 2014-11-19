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

typedef double SPDYTimeInterval;

@interface SPDYStopwatch : NSObject
+ (SPDYTimeInterval)currentSystemTime;
- (id)init;
- (void)reset;
- (SPDYTimeInterval)elapsedSeconds;
@end
