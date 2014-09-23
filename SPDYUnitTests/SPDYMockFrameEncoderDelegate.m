//
//  SPDYMockFrameEncoderDelegate.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier on 9/19/2014.
//

#import "SPDYMockFrameEncoderDelegate.h"

#pragma mark SPDYFrameEncoderAccumulator

@implementation SPDYMockFrameEncoderDelegate

- (id)init
{
    self = [super init];
    if (self) {
        _lastEncodedData = [NSMutableData data];
    }
    return self;
}

- (void)didEncodeData:(NSData *)data frameEncoder:(SPDYFrameEncoder *)encoder
{
    [self.lastEncodedData appendData:data];
}

- (void)didEncodeData:(NSData *)data withTag:(uint32_t)tag frameEncoder:(SPDYFrameEncoder *)encoder;
{
    [self.lastEncodedData appendData:data];
}

- (void)clear
{
    [self.lastEncodedData setLength:0];
}

@end
