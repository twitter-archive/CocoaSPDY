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

static const NSString *logLevels[4] = { @"ERROR", @"WARNING", @"INFO", @"DEBUG" };

@implementation SPDYCommonLogger

static dispatch_once_t __initialized;
dispatch_queue_t __sharedLoggerQueue;
static id<SPDYLogger> __sharedLogger;
volatile SPDYLogLevel __sharedLoggerLevel;

+ (void)initialize
{
    dispatch_once(&__initialized, ^{
        __sharedLoggerQueue = dispatch_queue_create("com.twitter.SPDYProtocolLoggerQueue", DISPATCH_QUEUE_SERIAL);
        __sharedLogger = nil;
#ifdef DEBUG
        __sharedLoggerLevel = SPDYLogLevelDebug;
#else
        __sharedLoggerLevel = SPDYLogLevelError;
#endif
    });
}

+ (void)setLogger:(id<SPDYLogger>)logger
{
    dispatch_async(__sharedLoggerQueue, ^{
        __sharedLogger = logger;
    });
}

+ (id<SPDYLogger>)currentLogger
{
    id<SPDYLogger> __block sharedLogger;
    dispatch_sync(__sharedLoggerQueue, ^{
        sharedLogger = __sharedLogger;
    });
    return sharedLogger;
}

+ (void)setLoggerLevel:(SPDYLogLevel)level
{
    __sharedLoggerLevel = level;
}

+ (SPDYLogLevel)currentLoggerLevel
{
    return __sharedLoggerLevel;
}

+ (void)log:(NSString *)format atLevel:(SPDYLogLevel)level, ... NS_FORMAT_FUNCTION(1,3)
{
    va_list args;
    va_start(args, level);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

#ifdef DEBUG
    if (__sharedLogger == nil) {
        NSLog(@"SPDY [%@] %@", logLevels[level], message);
    }
#endif
    
    dispatch_async(__sharedLoggerQueue, ^{
        if (__sharedLogger) {
            [__sharedLogger log:message atLevel:level];
        }
    });
}

+ (void)flush
{
    dispatch_sync(__sharedLoggerQueue, ^{
    });
}

@end
