//
//  SPDYProtocolTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier.
//

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>
#import "NSURLRequest+SPDYURLRequest.h"
#import "SPDYProtocol.h"
#import "SPDYTLSTrustEvaluator.h"

@interface SPDYProtocolTest : XCTestCase<SPDYTLSTrustEvaluator>
@end

@implementation SPDYProtocolTest
{
    NSString *_lastTLSTrustHost;
}

- (void)tearDown
{
    _lastTLSTrustHost = nil;
    [SPDYURLConnectionProtocol unregisterAllAliases];
    [SPDYURLConnectionProtocol unregisterAllOrigins];
    [SPDYProtocol setTLSTrustEvaluator:nil];
}

- (NSMutableURLRequest *)makeRequest:(NSString *)url
{
    return [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
}

#pragma mark SPDYTLSTrustEvaluator

- (BOOL)evaluateServerTrust:(SecTrustRef)trust forHost:(NSString *)host
{
    _lastTLSTrustHost = host;
    return NO;
}

#pragma mark Tests

- (void)testURLSessionCanInitTrue
{
    XCTAssertTrue([SPDYURLSessionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com"]]);
    XCTAssertTrue([SPDYURLSessionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com/foo"]]);
    XCTAssertTrue([SPDYURLSessionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com:443/foo"]]);
    XCTAssertTrue([SPDYURLSessionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com:8888/foo"]]);
    XCTAssertTrue([SPDYURLSessionProtocol canInitWithRequest:[self makeRequest:@"http://api.twitter.com/foo"]]);
}

- (void)testURLSessionCanInitFalse
{
    XCTAssertFalse([SPDYURLSessionProtocol canInitWithRequest:[self makeRequest:@"ftp://api.twitter.com"]]);
    XCTAssertFalse([SPDYURLSessionProtocol canInitWithRequest:[self makeRequest:@"://api.twitter.com"]]);
    XCTAssertFalse([SPDYURLSessionProtocol canInitWithRequest:[self makeRequest:@"api.twitter.com"]]);
}

- (void)testURLSessionWithBypassCanInitFalse
{
    NSMutableURLRequest *request = [self makeRequest:@"https://api.twitter.com"];
    request.SPDYBypass = YES;
    XCTAssertFalse([SPDYURLSessionProtocol canInitWithRequest:request]);
}

- (void)testURLConnectionCanInitTrue
{
    [SPDYURLConnectionProtocol registerOrigin:@"https://api.twitter.com"];
    XCTAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com"]]);
    XCTAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com/foo"]]);
    XCTAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com:443/foo"]]);
}

- (void)testURLConnectionCanInitFalse
{
    [SPDYURLConnectionProtocol registerOrigin:@"https://api.twitter.com"];
    XCTAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com:8888/foo"]]);
    XCTAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"http://api.twitter.com"]]);
    XCTAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://twitter.com"]]);
    XCTAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://foo.api.twitter.com"]]);
    XCTAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://twitter.com:80"]]);
    XCTAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"http://api.twitter.com:443"]]);
    XCTAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"://api.twitter.com"]]);
}

- (void)testURLConnectionWithBypassCanInitFalse
{
    [SPDYURLConnectionProtocol registerOrigin:@"https://api.twitter.com"];
    NSMutableURLRequest *request = [self makeRequest:@"https://api.twitter.com"];
    request.SPDYBypass = YES;
    XCTAssertFalse([SPDYURLSessionProtocol canInitWithRequest:request]);
}

- (void)testURLConnectionAliasCanInitTrue
{
    [SPDYURLConnectionProtocol registerOrigin:@"https://api.twitter.com"];
    [SPDYURLConnectionProtocol registerOrigin:@"https://1.2.3.4"];
    [SPDYProtocol registerAlias:@"https://alias.twitter.com" forOrigin:@"https://api.twitter.com"];
    [SPDYProtocol registerAlias:@"https://bare.twitter.com" forOrigin:@"https://1.2.3.4"];

    XCTAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com/foo"]]);
    XCTAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://1.2.3.4/foo"]]);
    XCTAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://alias.twitter.com/foo"]]);
    XCTAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://bare.twitter.com/foo"]]);

    // TODO: Replace with unregisterAllAliases when available
    [SPDYProtocol unregisterAlias:@"https://alias.twitter.com"];
    [SPDYProtocol unregisterAlias:@"https://bare.twitter.com"];
}

- (void)testURLConnectionAliasToNoOriginCanInitFalse
{
    //[SPDYURLConnectionProtocol registerOrigin:@"https://api.twitter.com"];
    [SPDYProtocol registerAlias:@"https://alias.twitter.com" forOrigin:@"https://api.twitter.com"];
    [SPDYProtocol registerAlias:@"https://bare.twitter.com" forOrigin:@"https://1.2.3.4"];

    XCTAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com/foo"]]);
    XCTAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://1.2.3.4/foo"]]);
    XCTAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://alias.twitter.com/foo"]]);
    XCTAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://bare.twitter.com/foo"]]);

    // TODO: Replace with unregisterAllAliases when available
    [SPDYProtocol unregisterAlias:@"https://alias.twitter.com"];
    [SPDYProtocol unregisterAlias:@"https://bare.twitter.com"];
}

- (void)testURLConnectionBadAliasCanInitFalse
{
    [SPDYURLConnectionProtocol registerOrigin:@"https://api.twitter.com"];
    [SPDYProtocol registerAlias:@"ftp://alias.twitter.com" forOrigin:@"https://api.twitter.com"]; // bad alias

    XCTAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"ftp://alias.twitter.com/foo"]]);

    // TODO: Replace with unregisterAllAliases when available
    [SPDYProtocol unregisterAlias:@"ftp://alias.twitter.com"];
}

- (void)testURLConnectionCanInitTrueAfterWeirdOrigins
{
    [SPDYURLConnectionProtocol registerOrigin:@"https://api.twitter.com:8888"];
    XCTAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com:8888/foo"]]);
    XCTAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com/foo"]]);

    [SPDYURLConnectionProtocol registerOrigin:@"https://api.twitter.com"];
    XCTAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com:8888/foo"]]);
    XCTAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com/foo"]]);
    XCTAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com:8889/foo"]]);

    [SPDYURLConnectionProtocol registerOrigin:@"https://www.twitter.com/foo"];
    XCTAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://www.twitter.com/foo"]]);
    XCTAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://www.twitter.com"]]);
}

- (void)testURLConnectionCanInitFalseAfterBadOrigins
{
    [SPDYURLConnectionProtocol registerOrigin:@"ftp://api.twitter.com"];
    XCTAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com/foo"]]);
    XCTAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"ftp://api.twitter.com/foo"]]);

    [SPDYURLConnectionProtocol registerOrigin:@"https://"];
    XCTAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://"]]);
}

- (void)testURLConnectionCanInitFalseAfterUnregister
{
    [SPDYURLConnectionProtocol registerOrigin:@"https://api.twitter.com"];
    [SPDYURLConnectionProtocol registerOrigin:@"https://www.twitter.com"];
    XCTAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com"]]);
    XCTAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://www.twitter.com"]]);

    [SPDYURLConnectionProtocol unregisterOrigin:@"https://api.twitter.com"];
    XCTAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com"]]);
    XCTAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://www.twitter.com"]]);

    [SPDYURLConnectionProtocol unregisterAllOrigins];
    XCTAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://www.twitter.com"]]);
}

- (void)testTLSTrustEvaluatorReturnsYesWhenNotSet
{
    XCTAssertTrue([SPDYProtocol evaluateServerTrust:nil forHost:@"api.twitter.com"]);
}

- (void)testTLSTrustEvaluator
{
    [SPDYProtocol setTLSTrustEvaluator:self];
    XCTAssertFalse([SPDYProtocol evaluateServerTrust:nil forHost:@"api.twitter.com"]);
    XCTAssertEqualObjects(_lastTLSTrustHost, @"api.twitter.com");
}

- (void)testTLSTrustEvaluatorWithCertificateAlias
{
    [SPDYProtocol setTLSTrustEvaluator:self];
    [SPDYURLConnectionProtocol registerOrigin:@"https://api.twitter.com"];
    [SPDYURLConnectionProtocol registerOrigin:@"https://1.2.3.4"];
    [SPDYProtocol registerAlias:@"https://alias.twitter.com" forOrigin:@"https://api.twitter.com"];
    [SPDYProtocol registerAlias:@"https://bare.twitter.com" forOrigin:@"https://1.2.3.4"];

    XCTAssertFalse([SPDYProtocol evaluateServerTrust:nil forHost:@"api.twitter.com"]);
    XCTAssertEqualObjects(_lastTLSTrustHost, @"api.twitter.com");

    XCTAssertFalse([SPDYProtocol evaluateServerTrust:nil forHost:@"1.2.3.4"]);
    XCTAssertEqualObjects(_lastTLSTrustHost, @"bare.twitter.com");

    // TODO: Replace with unregisterAllAliases when available
    [SPDYProtocol unregisterAlias:@"https://alias.twitter.com"];
    [SPDYProtocol unregisterAlias:@"https://bare.twitter.com"];
}

@end

