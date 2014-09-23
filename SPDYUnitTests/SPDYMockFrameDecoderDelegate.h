//
//  SPDYMockFrameDecoderDelegate.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#import <Foundation/Foundation.h>
#import "SPDYFrameDecoder.h"

@interface SPDYMockFrameDecoderDelegate : NSObject <SPDYFrameDecoderDelegate>
@property (nonatomic, strong, readonly) NSArray *framesReceived;
@property (nonatomic, strong, readonly) id lastFrame;
@property (nonatomic, readonly) NSString *lastDelegateMessage;
@property (nonatomic, readonly) NSUInteger frameCount;
- (void)clear;
@end

