//
//  SPDYLogger.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

typedef enum {
    SPDYLogLevelError = 0,
    SPDYLogLevelWarning,
    SPDYLogLevelInfo,
    SPDYLogLevelDebug
} SPDYLogLevel;

@protocol SPDYLogger <NSObject>
- (void)log:(NSString *)message atLevel:(SPDYLogLevel)logLevel;
@end
