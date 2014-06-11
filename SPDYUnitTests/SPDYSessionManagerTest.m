//
//  SPDYSessionManagerTest.m
//  SPDY
//
//  Created by Blake Watters on 5/29/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "SPDYSession.h"
#import "SPDYSessionManager.h"

@interface SPDYSessionManagerTest : XCTestCase

@end

@implementation SPDYSessionManagerTest

- (void)testSessionManagerWillNotDequeueClosedSession
{
    // Get a session into the pool
    // Close it
    // Try to dequeue again
    SPDYSession *session = [SPDYSessionManager sessionForURL:[NSURL URLWithString:@"http://layer.com"] error:nil];
    XCTAssertNotNil(session, @"session should not be `nil`");
    [session close];
    SPDYSession *session2 = [SPDYSessionManager sessionForURL:[NSURL URLWithString:@"http://layer.com"] error:nil];
    XCTAssertFalse([session isEqual:session2], @"Should not dequeue closed session");
}

@end
