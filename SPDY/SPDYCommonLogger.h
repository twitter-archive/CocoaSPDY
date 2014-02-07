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

#ifdef DEBUG
#define SPDY_LOG_LEVEL 4
#else
#define SPDY_LOG_LEVEL 0
#endif

#define SPDY_DEBUG(message, ...)
#define SPDY_INFO(message, ...)
#define SPDY_WARNING(message, ...)
#define SPDY_ERROR(message, ...)

#if SPDY_LOG_LEVEL >= 3
#undef SPDY_DEBUG
#define SPDY_DEBUG(message, ...) [SPDYCommonLogger log:message atLevel:SPDYLogLevelDebug, ##__VA_ARGS__]
#endif

#if SPDY_LOG_LEVEL >= 2
#undef SPDY_INFO
#define SPDY_INFO(message, ...) [SPDYCommonLogger log:message atLevel:SPDYLogLevelInfo, ##__VA_ARGS__]
#endif

#if SPDY_LOG_LEVEL >= 1
#undef SPDY_WARNING
#define SPDY_WARNING(message, ...) [SPDYCommonLogger log:message atLevel:SPDYLogLevelWarning, ##__VA_ARGS__]
#endif

#if SPDY_LOG_LEVEL >= 0
#undef SPDY_ERROR
#define SPDY_ERROR(message, ...) [SPDYCommonLogger log:message atLevel:SPDYLogLevelError, ##__VA_ARGS__]
#endif

@interface SPDYCommonLogger : NSObject
+ (void)setLogger:(id<SPDYLogger>)logger;
+ (void)log:(NSString *)format atLevel:(SPDYLogLevel)level, ... NS_FORMAT_FUNCTION(1,3);
@end
