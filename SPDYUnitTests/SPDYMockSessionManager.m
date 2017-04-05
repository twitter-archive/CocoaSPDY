//
//  SPDYMockSessionManager.m
//  SPDY
//
//  Copyright (c) 2015 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier on 11/30/15.
//

#import <Foundation/Foundation.h>
#import "SPDYMockSessionManager.h"
#import "SPDYOrigin.h"
#import "SPDYPushStreamManager.h"
#import "SPDYStream.h"
#import <objc/runtime.h>

@implementation SPDYMockSessionManager

#pragma mark Mock methods

+ (void)performSwizzling:(BOOL)performSwizzling
{
    Method original, swizzle;

    original = class_getClassMethod([SPDYSessionManager class], @selector(localManagerForOrigin:));
    swizzle = class_getClassMethod([SPDYMockSessionManager class], @selector(swizzled_localManagerForOrigin:));
    if (performSwizzling) {
        method_exchangeImplementations(original, swizzle);
    } else {
        method_exchangeImplementations(swizzle, original);
    }
}

+ (SPDYSessionManager *)swizzled_localManagerForOrigin:(SPDYOrigin *)origin
{
    return [SPDYMockSessionManager shared];
}

+ (SPDYMockSessionManager *)shared
{
    static dispatch_once_t once;
    static SPDYMockSessionManager *instance;
    dispatch_once(&once, ^{
        instance = [[SPDYMockSessionManager alloc] init];
    });
    return instance;
}

#pragma mark SPDYSessionManager methods

- (SPDYPushStreamManager *)pushStreamManager
{
    // Not needed
    return nil;
}

- (void)queueStream:(SPDYStream *)stream
{
    // stream.delegate =
    [stream startWithStreamId:1 sendWindowSize:1000 receiveWindowSize:1000];
    stream.localSideClosed = YES;

    if (_streamQueuedBlock) {
        _streamQueuedBlock(stream);
    }

    // NSURL system won't make the didReceiveResponse callback until either data is received
    // or the response finishes. At least for iOS 9. Odd. So we'll force the didFinishLoading
    // callback to flush out the other.
    stream.remoteSideClosed = YES;
}

@end
