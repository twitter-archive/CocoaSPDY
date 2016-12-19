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

#import <Foundation/Foundation.h>

typedef NS_ENUM(int32_t, SPDYLogLevel) {
    SPDYLogLevelDisabled = -1,
    SPDYLogLevelError = 0,
    SPDYLogLevelWarning,
    SPDYLogLevelInfo,
    SPDYLogLevelDebug
};

@protocol SPDYLogger <NSObject>
- (void)log:(NSString *)message atLevel:(SPDYLogLevel)logLevel;
@end
