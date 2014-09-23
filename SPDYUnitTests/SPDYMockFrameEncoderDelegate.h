//
//  SPDYMockFrameEncoderDelegate.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier on 9/19/2014.
//

#import "SPDYFrameEncoder.h"
#import "SPDYFrameDecoder.h"

// These are used by test classes to encode frames into an NSMutableData structure, which can
// be provided to the spdy socket. Or, the test can take the last bytes written to the socket
// and decode them into a frame.

@interface SPDYMockFrameEncoderDelegate : NSObject <SPDYFrameEncoderDelegate>
@property (nonatomic) NSMutableData *lastEncodedData;
- (void)clear;
@end
