//
//  SPDYMockFrameDecoderDelegate.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#import "SPDYMockFrameDecoderDelegate.h"


#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
@implementation SPDYMockFrameDecoderDelegate
#pragma clang diagnostic pop
{
    NSMutableArray *_framesReceived;
}

- (id)init
{
    self = [super init];
    if (self) {
        _framesReceived = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
    _lastDelegateMessage = NSStringFromSelector([invocation selector]);
    __unsafe_unretained SPDYFrame *frame;
    [invocation getArgument:&frame atIndex:2];
    [_framesReceived addObject:frame];
}

- (id)lastFrame
{
    return _framesReceived.lastObject;
}

- (NSUInteger)frameCount
{
    return _framesReceived.count;
}

- (void)clear
{
    [_framesReceived removeAllObjects];
}

@end
