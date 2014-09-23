//
//  SPDYSessionManagerTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Blake Watters on 5/29/14.
//

#import <SenTestingKit/SenTestingKit.h>
#import "SPDYSession.h"
#import "SPDYSessionManager.h"

@interface SPDYSessionManagerTest : SenTestCase

@end

@implementation SPDYSessionManagerTest

- (void)testSessionManagerWillNotDequeueClosedSession
{
    // Get a session into the pool
    // Close it
    // Try to dequeue again
    SPDYSession *session = [SPDYSessionManager sessionForURL:[NSURL URLWithString:@"http://layer.com"] error:nil];
    STAssertNotNil(session, @"session should not be `nil`");
    [session close];
    SPDYSession *session2 = [SPDYSessionManager sessionForURL:[NSURL URLWithString:@"http://layer.com"] error:nil];
    STAssertFalse([session isEqual:session2], @"Should not dequeue closed session");
}

@end
