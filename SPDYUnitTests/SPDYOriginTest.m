//
//  SPDYOriginTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#import <XCTest/XCTest.h>
#import "SPDYOrigin.h"

@interface SPDYOriginTest : XCTestCase
@end

@implementation SPDYOriginTest

- (void)testInitEquivalency
{
    NSError *error;
    NSURL *url;
    NSString *originStr;
    SPDYOrigin *o1, *o2, *o3, *o4, *o5, *o6, *o7;

    originStr = @"http://twitter.com";
    o1 = [[SPDYOrigin alloc] initWithString:originStr error:&error];
    XCTAssertTrue(error == nil);

    url = [[NSURL alloc] initWithString:originStr];
    o2 = [[SPDYOrigin alloc] initWithURL:url error:&error];
    XCTAssertTrue(error == nil);

    o3 = [[SPDYOrigin alloc] initWithScheme:@"http"
                                       host:@"twitter.com"
                                       port:0
                                      error:&error];
    XCTAssertTrue(error == nil);

    originStr = @"http://twitter.com:80";
    o4 = [[SPDYOrigin alloc] initWithString:originStr error:&error];
    XCTAssertTrue(error == nil);

    url = [[NSURL alloc] initWithString:originStr];
    o5 = [[SPDYOrigin alloc] initWithURL:url error:&error];
    XCTAssertTrue(error == nil);

    o6 = [[SPDYOrigin alloc] initWithScheme:@"http"
                                       host:@"twitter.com"
                                       port:80
                                      error:&error];
    XCTAssertTrue(error == nil);

    o7 = [o6 copy];

    XCTAssertTrue([o1 isEqual:o2]);
    XCTAssertTrue([o1 hash] == [o2 hash]);

    XCTAssertTrue([o2 isEqual:o3]);
    XCTAssertTrue([o2 hash] == [o3 hash]);

    XCTAssertTrue([o3 isEqual:o4]);
    XCTAssertTrue([o3 hash] == [o4 hash]);

    XCTAssertTrue([o4 isEqual:o5]);
    XCTAssertTrue([o4 hash] == [o5 hash]);

    XCTAssertTrue([o5 isEqual:o6]);
    XCTAssertTrue([o5 hash] == [o6 hash]);

    XCTAssertFalse(o6 == o7);
    XCTAssertTrue([o6 isEqual:o7]);
    XCTAssertTrue([o6 hash] == [o7 hash]);
}

- (void)testInitWithInvalidOrigins
{
    NSError *error = nil;
    SPDYOrigin *origin = nil;

    NSArray *badOrigins = @[
        @"http://",
        @"twitter.com",
        @"ftp://twitter.com",
    ];

    for (NSString *originStr in badOrigins) {
        error = nil;
        origin = [[SPDYOrigin alloc] initWithString:originStr error:&error];
        XCTAssertTrue(error != nil);
        XCTAssertTrue(origin == nil);
    }
}

- (void)testImmutability
{
    NSMutableString *scheme = [[NSMutableString alloc] initWithString:@"http"];
    NSMutableString *host = [[NSMutableString alloc] initWithString:@"twitter.com"];

    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithScheme:scheme
                                                       host:host
                                                       port:80
                                                      error:nil];

    XCTAssertTrue([origin.scheme isEqualToString:scheme]);
    XCTAssertTrue([origin.host isEqualToString:host]);
    NSUInteger hash1 = [origin hash];

    [scheme appendString:@"s"];
    [host appendString:@".jp"];
    NSUInteger hash2 = [origin hash];

    XCTAssertFalse([origin.scheme isEqualToString:scheme]);
    XCTAssertFalse([origin.host isEqualToString:host]);

    XCTAssertTrue(hash1 == hash2);
}

@end
