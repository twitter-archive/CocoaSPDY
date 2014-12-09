//
//  SPDYCommonLogger.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#import <Foundation/Foundation.h>
#import "SPDYLogger.h"

extern volatile SPDYLogLevel __sharedLoggerLevel;

#define LOG_LEVEL_ENABLED(l) ((l) <= __sharedLoggerLevel)

#define SPDY_DEBUG(message, ...) do { \
    if (LOG_LEVEL_ENABLED(SPDYLogLevelDebug)) { \
       [SPDYCommonLogger log:message atLevel:SPDYLogLevelDebug, ##__VA_ARGS__]; \
    } \
} while (0)

#define SPDY_INFO(message, ...) do { \
    if (LOG_LEVEL_ENABLED(SPDYLogLevelInfo)) { \
       [SPDYCommonLogger log:message atLevel:SPDYLogLevelInfo, ##__VA_ARGS__]; \
    } \
} while (0)

#define SPDY_WARNING(message, ...) do { \
    if (LOG_LEVEL_ENABLED(SPDYLogLevelWarning)) { \
       [SPDYCommonLogger log:message atLevel:SPDYLogLevelWarning, ##__VA_ARGS__]; \
    } \
} while (0)

#define SPDY_ERROR(message, ...) do { \
    if (LOG_LEVEL_ENABLED(SPDYLogLevelError)) { \
       [SPDYCommonLogger log:message atLevel:SPDYLogLevelError, ##__VA_ARGS__]; \
    } \
} while (0)

@interface SPDYCommonLogger : NSObject
+ (void)setLogger:(id<SPDYLogger>)logger;
+ (id<SPDYLogger>)currentLogger;
+ (void)setLoggerLevel:(SPDYLogLevel)level;
+ (SPDYLogLevel)currentLoggerLevel;
+ (void)log:(NSString *)format atLevel:(SPDYLogLevel)level, ... NS_FORMAT_FUNCTION(1,3);
+ (void)flush;
@end
