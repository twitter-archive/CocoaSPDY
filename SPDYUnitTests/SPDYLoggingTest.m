//
//  SPDYLoggingTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier.
//

#import <SenTestingKit/SenTestingKit.h>
#import "SPDYCommonLogger.h"

@interface SPDYLoggingTest : SenTestCase <SPDYLogger>
@end

@implementation SPDYLoggingTest
{
    NSString *_lastMessage;
    SPDYLogLevel _lastLevel;

    dispatch_queue_t _loggerQueue;
}

- (void)log:(NSString *)message atLevel:(SPDYLogLevel)logLevel
{
    _lastMessage = message;
    _lastLevel = logLevel;
}

- (void)setUp
{
    _lastMessage = nil;
    _lastLevel = -1;
    _loggerQueue = dispatch_queue_create("spdy.unittest.logqueue", DISPATCH_QUEUE_SERIAL);
}

- (void)tearDown
{
    [SPDYCommonLogger setLogger:nil queue:_loggerQueue];
}

- (BOOL)logAndWaitAtLevel:(SPDYLogLevel)level expectLog:(BOOL)expectLog
{
    _lastMessage = nil;
    _lastLevel = -1;

    switch (level) {
        case SPDYLogLevelDebug:
            SPDY_DEBUG(@"debug %d", 1);
            break;
        case SPDYLogLevelInfo:
            SPDY_INFO(@"info %d", 1);
            break;
        case SPDYLogLevelWarning:
            SPDY_WARNING(@"warning %d", 1);
            break;
        case SPDYLogLevelError:
            SPDY_ERROR(@"error %d", 1);
            break;
        case SPDYLogLevelDisabled:
            STAssertTrue(NO, @"not a valid log level");
            break;
    }


    dispatch_sync(_loggerQueue, ^{
        // Don't need to do anything. Just need this to run and return.
    });

    if (_lastMessage == nil && !expectLog) {
        return YES;
    }

    switch (level) {
        case SPDYLogLevelDebug:
            STAssertEqualObjects(_lastMessage, @"debug 1", nil);
            STAssertEquals(_lastLevel, SPDYLogLevelDebug, nil);
            break;
        case SPDYLogLevelInfo:
            STAssertEqualObjects(_lastMessage, @"info 1", nil);
            STAssertEquals(_lastLevel, SPDYLogLevelInfo, nil);
            break;
        case SPDYLogLevelWarning:
            STAssertEqualObjects(_lastMessage, @"warning 1", nil);
            STAssertEquals(_lastLevel, SPDYLogLevelWarning, nil);
            break;
        case SPDYLogLevelError:
            STAssertEqualObjects(_lastMessage, @"error 1", nil);
            STAssertEquals(_lastLevel, SPDYLogLevelError, nil);
            break;
        case SPDYLogLevelDisabled:
            break;
    }

    return NO;
}

- (void)testLoggingAtDebugLevel
{
    [SPDYCommonLogger setLogger:self queue:_loggerQueue];
    [SPDYCommonLogger setLoggerLevel:SPDYLogLevelDebug];

    [self logAndWaitAtLevel:SPDYLogLevelDebug expectLog:YES];
    [self logAndWaitAtLevel:SPDYLogLevelInfo expectLog:YES];
    [self logAndWaitAtLevel:SPDYLogLevelWarning expectLog:YES];
    [self logAndWaitAtLevel:SPDYLogLevelError expectLog:YES];
}

- (void)testLoggingAtInfoLevel
{
    [SPDYCommonLogger setLogger:self queue:_loggerQueue];
    [SPDYCommonLogger setLoggerLevel:SPDYLogLevelInfo];

    [self logAndWaitAtLevel:SPDYLogLevelDebug expectLog:NO];
    [self logAndWaitAtLevel:SPDYLogLevelInfo expectLog:YES];
    [self logAndWaitAtLevel:SPDYLogLevelWarning expectLog:YES];
    [self logAndWaitAtLevel:SPDYLogLevelError expectLog:YES];
}

- (void)testLoggingAtWarningLevel
{
    [SPDYCommonLogger setLogger:self queue:_loggerQueue];
    [SPDYCommonLogger setLoggerLevel:SPDYLogLevelWarning];

    [self logAndWaitAtLevel:SPDYLogLevelDebug expectLog:NO];
    [self logAndWaitAtLevel:SPDYLogLevelInfo expectLog:NO];
    [self logAndWaitAtLevel:SPDYLogLevelWarning expectLog:YES];
    [self logAndWaitAtLevel:SPDYLogLevelError expectLog:YES];
}

- (void)testLoggingAtErrorLevel
{
    [SPDYCommonLogger setLogger:self queue:_loggerQueue];
    [SPDYCommonLogger setLoggerLevel:SPDYLogLevelError];

    [self logAndWaitAtLevel:SPDYLogLevelDebug expectLog:NO];
    [self logAndWaitAtLevel:SPDYLogLevelInfo expectLog:NO];
    [self logAndWaitAtLevel:SPDYLogLevelWarning expectLog:NO];
    [self logAndWaitAtLevel:SPDYLogLevelError expectLog:YES];
}

- (void)testLoggingWhenDisabled
{
    [SPDYCommonLogger setLogger:self queue:_loggerQueue];
    [SPDYCommonLogger setLoggerLevel:SPDYLogLevelDisabled];

    [self logAndWaitAtLevel:SPDYLogLevelDebug expectLog:NO];
    [self logAndWaitAtLevel:SPDYLogLevelInfo expectLog:NO];
    [self logAndWaitAtLevel:SPDYLogLevelWarning expectLog:NO];
    [self logAndWaitAtLevel:SPDYLogLevelError expectLog:NO];
}

- (void)testLoggingWhenNil
{
    [SPDYCommonLogger setLogger:nil queue:_loggerQueue];
    [SPDYCommonLogger setLoggerLevel:SPDYLogLevelError];

    SPDY_DEBUG(@"debug %d", 1);
    STAssertNil(_lastMessage,  nil);

    SPDY_INFO(@"info %d", 1);
    STAssertNil(_lastMessage,  nil);

    SPDY_WARNING(@"warning %d", 1);
    STAssertNil(_lastMessage,  nil);

    SPDY_ERROR(@"error %d", 1);
    STAssertNil(_lastMessage,  nil);
}

- (void)testLoggingQueue
{
    dispatch_queue_t newQueue = dispatch_queue_create("spdy.unittest.logqueue2", DISPATCH_QUEUE_SERIAL);

    [SPDYCommonLogger setLogger:self queue:_loggerQueue];
    [SPDYCommonLogger setLoggerLevel:SPDYLogLevelError];

    SPDY_ERROR(@"error %d", 1);

    dispatch_async(_loggerQueue, ^{
        STAssertEqualObjects(_lastMessage, @"error 1", nil);
        sleep(1);
    });

    SPDY_ERROR(@"error %d", 2);

    [SPDYCommonLogger setLogger:self queue:newQueue];

    dispatch_async(_loggerQueue, ^{
        STAssertEqualObjects(_lastMessage, @"error 2", nil);
        sleep(1);
    });

    SPDY_ERROR(@"error %d", 3);

    dispatch_sync(newQueue, ^{
        STAssertEqualObjects(_lastMessage, @"error 3", nil);
    });
}

- (void)testLoggingQueueDefault
{
    [SPDYCommonLogger setLogger:self queue:nil];
    SPDY_ERROR(@"error %d", 1);
    for (int i = 0; i < 10; i++) {
        if (_lastMessage != nil) {
            break;
        }
        usleep(100 * 1000);
    }
    STAssertEqualObjects(_lastMessage, @"error 1", nil);
}

@end
