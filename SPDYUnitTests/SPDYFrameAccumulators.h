//
//  SPDYFrameAccumulators.h
//  SPDY
//
//  Created by Kevin Goodier on 9/19/2014.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "SPDYFrameEncoder.h"
#import "SPDYFrameDecoder.h"

// These are used by test classes to encode frames into an NSMutableData structure, which can
// be provided to the spdy socket. Or, the test can take the last bytes written to the socket
// and decode them into a frame.

@interface SPDYFrameEncoderAccumulator : SPDYFrameEncoder <SPDYFrameEncoderDelegate>
@property (nonatomic) NSMutableData *lastEncodedData;
- (void)clear;
@end

@interface SPDYFrameDecoderAccumulator : SPDYFrameDecoder <SPDYFrameDecoderDelegate>
@property (nonatomic) SPDYFrame *lastDecodedFrame;
- (void)clear;
@end

