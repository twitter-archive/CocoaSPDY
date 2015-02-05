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
#import "SPDYProtocol.h"

// Private to SPDYProtocol.m but need access to test
@interface SPDYAssertionHandler : NSAssertionHandler
@property (nonatomic) BOOL abortOnFailure;
@end

@interface SPDYLoggingTest : SenTestCase <SPDYLogger>
@end

@implementation SPDYLoggingTest
{
    NSString *_lastMessage;
    SPDYLogLevel _lastLevel;
}

- (void)log:(NSString *)message atLevel:(SPDYLogLevel)logLevel
{
    NSLog(@"Got log message: %@", message);
    _lastMessage = message;
    _lastLevel = logLevel;

    if ([message rangeOfString:@"delay"].length != 0) {
        sleep(1);
    }
}

- (void)setUp
{
    _lastMessage = nil;
    _lastLevel = -1;
}

- (void)tearDown
{
    [SPDYProtocol setLogger:nil];
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

    [SPDYCommonLogger flush];

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

- (void)testAccessors
{
    [SPDYProtocol setLogger:self];
    [SPDYProtocol setLoggerLevel:SPDYLogLevelDebug];

    STAssertEquals([SPDYProtocol currentLogger], self, nil);
    STAssertEquals([SPDYProtocol currentLoggerLevel], SPDYLogLevelDebug, nil);

    [SPDYProtocol setLogger:nil];
    [SPDYProtocol setLoggerLevel:SPDYLogLevelDisabled];

    STAssertNil([SPDYProtocol currentLogger], nil);
    STAssertEquals([SPDYProtocol currentLoggerLevel], SPDYLogLevelDisabled, nil);
}

- (void)testLoggingAtDebugLevel
{
    [SPDYProtocol setLogger:self];
    [SPDYProtocol setLoggerLevel:SPDYLogLevelDebug];

    [self logAndWaitAtLevel:SPDYLogLevelDebug expectLog:YES];
    [self logAndWaitAtLevel:SPDYLogLevelInfo expectLog:YES];
    [self logAndWaitAtLevel:SPDYLogLevelWarning expectLog:YES];
    [self logAndWaitAtLevel:SPDYLogLevelError expectLog:YES];
}

- (void)testLoggingAtInfoLevel
{
    [SPDYProtocol setLogger:self];
    [SPDYProtocol setLoggerLevel:SPDYLogLevelInfo];

    [self logAndWaitAtLevel:SPDYLogLevelDebug expectLog:NO];
    [self logAndWaitAtLevel:SPDYLogLevelInfo expectLog:YES];
    [self logAndWaitAtLevel:SPDYLogLevelWarning expectLog:YES];
    [self logAndWaitAtLevel:SPDYLogLevelError expectLog:YES];
}

- (void)testLoggingAtWarningLevel
{
    [SPDYProtocol setLogger:self];
    [SPDYProtocol setLoggerLevel:SPDYLogLevelWarning];

    [self logAndWaitAtLevel:SPDYLogLevelDebug expectLog:NO];
    [self logAndWaitAtLevel:SPDYLogLevelInfo expectLog:NO];
    [self logAndWaitAtLevel:SPDYLogLevelWarning expectLog:YES];
    [self logAndWaitAtLevel:SPDYLogLevelError expectLog:YES];
}

- (void)testLoggingAtErrorLevel
{
    [SPDYProtocol setLogger:self];
    [SPDYProtocol setLoggerLevel:SPDYLogLevelError];

    [self logAndWaitAtLevel:SPDYLogLevelDebug expectLog:NO];
    [self logAndWaitAtLevel:SPDYLogLevelInfo expectLog:NO];
    [self logAndWaitAtLevel:SPDYLogLevelWarning expectLog:NO];
    [self logAndWaitAtLevel:SPDYLogLevelError expectLog:YES];
}

- (void)testLoggingWhenDisabled
{
    [SPDYProtocol setLogger:self];
    [SPDYProtocol setLoggerLevel:SPDYLogLevelDisabled];

    [self logAndWaitAtLevel:SPDYLogLevelDebug expectLog:NO];
    [self logAndWaitAtLevel:SPDYLogLevelInfo expectLog:NO];
    [self logAndWaitAtLevel:SPDYLogLevelWarning expectLog:NO];
    [self logAndWaitAtLevel:SPDYLogLevelError expectLog:NO];
}

- (void)testLoggingWhenNil
{
    [SPDYProtocol setLogger:nil];
    [SPDYProtocol setLoggerLevel:SPDYLogLevelError];

    SPDY_DEBUG(@"debug %d", 1);
    STAssertNil(_lastMessage,  nil);

    SPDY_INFO(@"info %d", 1);
    STAssertNil(_lastMessage,  nil);

    SPDY_WARNING(@"warning %d", 1);
    STAssertNil(_lastMessage,  nil);

    SPDY_ERROR(@"error %d", 1);
    STAssertNil(_lastMessage,  nil);
}

- (void)testAssertionHandler
{
    [SPDYProtocol setLogger:self];
    [SPDYProtocol setLoggerLevel:SPDYLogLevelError];

    // Register SPDYProtocol's assertion handler on our thread, but disable the abort() call.
    SPDYAssertionHandler *assertionHandler = [[SPDYAssertionHandler alloc] init];
    assertionHandler.abortOnFailure = NO;
    [NSThread currentThread].threadDictionary[NSAssertionHandlerKey] = assertionHandler;

    NSAssert(NO, @"test failing method");
    STAssertNotNil(_lastMessage, nil);
    STAssertEquals(_lastLevel, SPDYLogLevelError, nil);

    _lastMessage = nil;
    _lastLevel = nil;
    NSCAssert(NO, @"test failing function");
    STAssertNotNil(_lastMessage, nil);
    STAssertEquals(_lastLevel, SPDYLogLevelError, nil);

    // All done
    [[NSThread currentThread].threadDictionary removeObjectForKey:NSAssertionHandlerKey];
}

@end
