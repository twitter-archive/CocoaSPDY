//
//  SPDYCommonLogger.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "This file requires ARC support."
#endif

#import "SPDYCommonLogger.h"

#ifdef DEBUG
#define SPDY_DEBUG_LOGGING 1
#endif

static const NSString *logLevels[4] = { @"ERROR", @"WARNING", @"INFO", @"DEBUG" };

@implementation SPDYCommonLogger

static dispatch_once_t initialized;
static dispatch_queue_t loggerQueue;
static id<SPDYLogger> sharedLogger;

+ (void)initialize
{
    dispatch_once(&initialized, ^{
        loggerQueue = dispatch_queue_create("com.twitter.SPDYProtocolLoggerQueue", DISPATCH_QUEUE_SERIAL);
    });
}

+ (void)setLogger:(id<SPDYLogger>)logger
{
    dispatch_async(loggerQueue, ^{
        sharedLogger = logger;
    });
}

+ (void)log:(NSString *)format atLevel:(SPDYLogLevel)level, ... NS_FORMAT_FUNCTION(1,3)
{
    va_list args;
    va_start(args, level);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

#if SPDY_DEBUG_LOGGING
    NSLog(@"SPDY [%@] %@", logLevels[level], message);
#else
    dispatch_async(loggerQueue, ^{
        if (sharedLogger) {
            [sharedLogger log:message atLevel:level];
        }
    });
#endif
}

@end
