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
volatile atomic_int_fast32_t __sharedLoggerLevel = ATOMIC_VAR_INIT(SPDYLogLevelError);

+ (void)initialize
{
    dispatch_once(&__initialized, ^{
        __sharedLoggerQueue = dispatch_queue_create("com.twitter.SPDYProtocolLoggerQueue", DISPATCH_QUEUE_SERIAL);
        __sharedLogger = nil;
#ifdef DEBUG
        atomic_store(&__sharedLoggerLevel, SPDYLogLevelDebug);
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
#if defined(__has_feature)
#  if __has_feature(thread_sanitizer)
// not performing thread-sanitizer on this because __sharedLoggerLevel has been declared volatile
 __attribute__((no_sanitize("thread")))
#  endif // #  if __has_Feature(thread_sanitizer)
#endif // #if defined(__has_feature)
{
    atomic_store(&__sharedLoggerLevel, level);
}

+ (SPDYLogLevel)currentLoggerLevel
{
    return atomic_load(&__sharedLoggerLevel);
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
