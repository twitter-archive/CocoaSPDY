//
//  SPDYMockFrameEncoderDelegate.h
//  SPDY
//
//  Created by Kevin Goodier on 9/19/2014.
//  Copyright (c) 2014 Twitter. All rights reserved.
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
