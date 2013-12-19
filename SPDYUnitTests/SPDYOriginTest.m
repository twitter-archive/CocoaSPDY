//
//  SPDYOriginTest.m
//  SPDY
//
//  Copyright (c) 2013 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#import <SenTestingKit/SenTestingKit.h>
#import "SPDYOrigin.h"

@interface SPDYOriginTest : SenTestCase
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
    STAssertTrue(error == nil, nil);

    url = [[NSURL alloc] initWithString:originStr];
    o2 = [[SPDYOrigin alloc] initWithURL:url error:&error];
    STAssertTrue(error == nil, nil);

    o3 = [[SPDYOrigin alloc] initWithScheme:@"http"
                                       host:@"twitter.com"
                                       port:0
                                      error:&error];
    STAssertTrue(error == nil, nil);

    originStr = @"http://twitter.com:80";
    o4 = [[SPDYOrigin alloc] initWithString:originStr error:&error];
    STAssertTrue(error == nil, nil);

    url = [[NSURL alloc] initWithString:originStr];
    o5 = [[SPDYOrigin alloc] initWithURL:url error:&error];
    STAssertTrue(error == nil, nil);

    o6 = [[SPDYOrigin alloc] initWithScheme:@"http"
                                       host:@"twitter.com"
                                       port:80
                                      error:&error];
    STAssertTrue(error == nil, nil);

    o7 = [o6 copy];

    STAssertTrue([o1 isEqual:o2], nil);
    STAssertTrue([o1 hash] == [o2 hash], nil);

    STAssertTrue([o2 isEqual:o3], nil);
    STAssertTrue([o2 hash] == [o3 hash], nil);

    STAssertTrue([o3 isEqual:o4], nil);
    STAssertTrue([o3 hash] == [o4 hash], nil);

    STAssertTrue([o4 isEqual:o5], nil);
    STAssertTrue([o4 hash] == [o5 hash], nil);

    STAssertTrue([o5 isEqual:o6], nil);
    STAssertTrue([o5 hash] == [o6 hash], nil);

    STAssertFalse(o6 == o7, nil);
    STAssertTrue([o6 isEqual:o7], nil);
    STAssertTrue([o6 hash] == [o7 hash], nil);
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
        STAssertTrue(error != nil, nil);
        STAssertTrue(origin == nil, nil);
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

    STAssertTrue([origin.scheme isEqualToString:scheme], nil);
    STAssertTrue([origin.host isEqualToString:host], nil);
    NSUInteger hash1 = [origin hash];

    [scheme appendString:@"s"];
    [host appendString:@".jp"];
    NSUInteger hash2 = [origin hash];

    STAssertFalse([origin.scheme isEqualToString:scheme], nil);
    STAssertFalse([origin.host isEqualToString:host], nil);

    STAssertTrue(hash1 == hash2, nil);
}

@end
