//
//  SPDYFrameEncoderAccumulator.m
//  SPDY
//
//  Created by Klemen Verdnik on 6/10/14.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "SPDYFrameEncoderAccumulator.h"

@implementation SPDYFrameEncoderAccumulator

- (void)didEncodeData:(NSData *)data frameEncoder:(SPDYFrameEncoder *)encoder
{
    self.lastEncodedData = data;
}

- (void)didEncodeData:(NSData *)data withTag:(uint32_t)tag frameEncoder:(SPDYFrameEncoder *)encoder;
{
    self.lastEncodedData = data;
}

@end
