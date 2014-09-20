//
//  SPDYFrameAccumulators.h
//  SPDY
//
//  Created by Kevin Goodier on 9/19/2014.
//  Copyright (c) 2014 Twitter. All rights reserved.
//

#import "SPDYFrameAccumulators.h"

#pragma mark SPDYFrameEncoderAccumulator

@implementation SPDYFrameEncoderAccumulator

- (id)init
{
    self = [super initWithDelegate:self headerCompressionLevel:0];
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

#pragma mark SPDYFrameDecoderAccumulator

@implementation SPDYFrameDecoderAccumulator

- (id)init
{
    self = [super initWithDelegate:self];
    return self;
}

- (void)didReadDataFrame:(SPDYDataFrame *)dataFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder {
    _lastDecodedFrame = dataFrame;
}

- (void)didReadSynStreamFrame:(SPDYSynStreamFrame *)synStreamFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder {
    _lastDecodedFrame = synStreamFrame;
}

- (void)didReadSynReplyFrame:(SPDYSynReplyFrame *)synReplyFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder {
    _lastDecodedFrame = synReplyFrame;
}

- (void)didReadRstStreamFrame:(SPDYRstStreamFrame *)rstStreamFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder {
    _lastDecodedFrame = rstStreamFrame;
}

- (void)didReadSettingsFrame:(SPDYSettingsFrame *)settingsFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder {
    _lastDecodedFrame = settingsFrame;
}

- (void)didReadPingFrame:(SPDYPingFrame *)pingFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder {
    _lastDecodedFrame = pingFrame;
}

- (void)didReadGoAwayFrame:(SPDYGoAwayFrame *)goAwayFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder {
    _lastDecodedFrame = goAwayFrame;
}

- (void)didReadHeadersFrame:(SPDYHeadersFrame *)headersFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder {
    _lastDecodedFrame = headersFrame;
}

- (void)didReadWindowUpdateFrame:(SPDYWindowUpdateFrame *)windowUpdateFrame frameDecoder:(SPDYFrameDecoder *)frameDecoder {
    _lastDecodedFrame = windowUpdateFrame;
}

- (void)clear
{
    _lastDecodedFrame = nil;
}

@end

