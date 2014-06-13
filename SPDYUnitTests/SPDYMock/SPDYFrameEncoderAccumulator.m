//
//  SPDYFrameEncoderAccumulator.m
//  SPDY
//
//  Created by Klemen Verdnik on 6/10/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "SPDYFrameEncoderAccumulator.h"

@implementation SPDYFrameEncoderAccumulator

- (instancetype)init
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
