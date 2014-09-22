//
//  SPDYFrameCodecTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#import <SenTestingKit/SenTestingKit.h>
#import "SPDYError.h"
#import "SPDYFrameEncoder.h"
#import "SPDYFrameDecoder.h"
#import "SPDYMockFrameDecoderDelegate.h"

@interface SPDYFrameCodecTest : SenTestCase
@end

@interface SPDYFrameDecoder (CodecTest) <SPDYFrameEncoderDelegate>
- (void)didEncodeData:(NSData *)data frameEncoder:(SPDYFrameEncoder *)encoder;
@end

@implementation SPDYFrameDecoder (CodecTest)
- (void)didEncodeData:(NSData *)data frameEncoder:(SPDYFrameEncoder *)encoder
{
    NSError *error;
    [self decode:(uint8_t *)data.bytes length:data.length error:&error];
}

- (void)didEncodeData:(NSData *)data withTag:(uint32_t)tag frameEncoder:(SPDYFrameEncoder *)encoder
{
    NSError *error;
    [self decode:(uint8_t *)data.bytes length:data.length error:&error];
}
@end

@implementation SPDYFrameCodecTest
{
    SPDYMockFrameDecoderDelegate *_mock;
    SPDYFrameEncoder *_encoder;
    SPDYFrameDecoder *_decoder;
}

#define AssertLastFrameClass(CLASS_NAME) \
    STAssertEqualObjects(NSStringFromClass([_mock.lastFrame class]), CLASS_NAME, @"expected mock delegate's last frame received to be of class %@, but was %@", CLASS_NAME, NSStringFromClass([_mock.lastFrame class]))

#define AssertFramesReceivedCount(COUNT) \
    STAssertTrue(_mock.frameCount == COUNT, @"expected property framesReceived of mock delegate to contain %d elements, but had %d elements", COUNT, _mock.frameCount)

#define AssertLastDelegateMessage(SELECTOR_NAME) \
    STAssertEqualObjects(_mock.lastDelegateMessage, SELECTOR_NAME, @"expected mock delegate's last message received to be %@ but was %@", SELECTOR_NAME, _mock.lastDelegateMessage)

#define AssertDecodedFrameLength(LENGTH) \
    STAssertEquals(((SPDYFrame *)_mock.lastFrame).encodedLength, (NSUInteger)LENGTH, @"expected the decoded frame to be %d bytes but got %d bytes", LENGTH, ((SPDYFrame *)_mock.lastFrame).encodedLength)

NSDictionary *testHeaders()
{
    return @{
        @":method"  : @"GET",
        @":path"    : @"/search?q=pokemans",
        @":version" : @"HTTP/1.1",
        @":host"    : @"www.google.com:443",
        @":scheme"  : @"https",
        @"pokemans" : @[@"pikachu", @"charmander", @"squirtle", @"bulbasaur"]
    };
}

- (void)setUp
{
    [super setUp];

    _mock = [[SPDYMockFrameDecoderDelegate alloc] init];
    _decoder = [[SPDYFrameDecoder alloc] initWithDelegate:_mock];
    _encoder = [[SPDYFrameEncoder alloc] initWithDelegate:_decoder
                                   headerCompressionLevel:9];
}

- (void)testDataFrame
{
    SPDYDataFrame *inFrame = [[SPDYDataFrame alloc] init];
    inFrame.streamId = arc4random() & 0x7FFFFFFF;
    inFrame.last = YES;

    uint8_t data[100];
    for (uint8_t i = 0; i < 100; i++) {
        data[i] = i;
    }

    inFrame.data = [[NSData alloc] initWithBytes:data length:100];

    NSInteger bytesEncoded = [_encoder encodeDataFrame:inFrame];
    STAssertEquals(bytesEncoded, 108, nil);

    AssertLastFrameClass(@"SPDYDataFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYDataFrame *outFrame = _mock.lastFrame;

    STAssertEquals(inFrame.streamId, outFrame.streamId, nil);
    STAssertEquals(inFrame.last, outFrame.last, nil);
    STAssertEquals(inFrame.data.length, outFrame.data.length, nil);
    for (uint8_t i = 0; i < 100; i++) {
        STAssertEquals(((uint8_t *)inFrame.data.bytes)[i], ((uint8_t *)outFrame.data.bytes)[i], nil);
    }
}

- (void)testSynStreamFrame
{
    SPDYSynStreamFrame *inFrame = [[SPDYSynStreamFrame alloc] init];
    inFrame.streamId = arc4random() & 0x7FFFFFFF;
    inFrame.associatedToStreamId = arc4random() & 0x7FFFFFFF;
    inFrame.unidirectional = (bool)(arc4random() & 1);
    inFrame.last = (bool)(arc4random() & 1);
    inFrame.priority = (uint8_t)(arc4random() & 7);
    inFrame.slot = 0;

    // Header block is compressed. Hard to figure out exact size, so we'll use a lower bound.
    NSInteger bytesEncoded = [_encoder encodeSynStreamFrame:inFrame error:nil];
    STAssertTrue(bytesEncoded > 18, nil);

    AssertLastFrameClass(@"SPDYSynStreamFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYSynStreamFrame *outFrame = _mock.lastFrame;

    STAssertEquals(inFrame.streamId, outFrame.streamId, nil);
    STAssertEquals(inFrame.associatedToStreamId, outFrame.associatedToStreamId, nil);
    STAssertEquals(inFrame.unidirectional, outFrame.unidirectional, nil);
    STAssertEquals(inFrame.last, outFrame.last, nil);
    STAssertEquals(inFrame.priority, outFrame.priority, nil);
    STAssertEquals(inFrame.slot, outFrame.slot, nil);
}

- (void)testSynStreamFrameWithHeaders
{
    SPDYSynStreamFrame *inFrame = [[SPDYSynStreamFrame alloc] init];
    inFrame.streamId = arc4random() & 0x7FFFFFFF;
    inFrame.associatedToStreamId = arc4random() & 0x7FFFFFFF;
    inFrame.unidirectional = (bool)(arc4random() & 1);
    inFrame.last = (bool)(arc4random() & 1);
    inFrame.priority = (uint8_t)(arc4random() & 7);
    inFrame.slot = 0;
    inFrame.headers = testHeaders();

    NSInteger bytesEncoded = [_encoder encodeSynStreamFrame:inFrame error:nil];
    STAssertTrue(bytesEncoded > 18, nil);

    AssertLastFrameClass(@"SPDYSynStreamFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYSynStreamFrame *outFrame = _mock.lastFrame;

    STAssertEquals(inFrame.streamId, outFrame.streamId, nil);
    STAssertEquals(inFrame.associatedToStreamId, outFrame.associatedToStreamId, nil);
    STAssertEquals(inFrame.unidirectional, outFrame.unidirectional, nil);
    STAssertEquals(inFrame.last, outFrame.last, nil);
    STAssertEquals(inFrame.priority, outFrame.priority, nil);
    STAssertEquals(inFrame.slot, outFrame.slot, nil);
    for (NSString *key in inFrame.headers) {
        STAssertTrue([inFrame.headers[key] isEqual:outFrame.headers[key]], nil);
    }
}

- (void)testSynStreamFrameWithTooLargeHeaders
{
    SPDYSynStreamFrame *inFrame = [[SPDYSynStreamFrame alloc] init];
    inFrame.streamId = arc4random() & 0x7FFFFFFF;
    inFrame.associatedToStreamId = arc4random() & 0x7FFFFFFF;
    inFrame.unidirectional = (bool)(arc4random() & 1);
    inFrame.last = (bool)(arc4random() & 1);
    inFrame.priority = (uint8_t)(arc4random() & 7);
    inFrame.slot = 0;

    // This header value alone is the entire allowed size of the headers. The header value
    // will be the item that triggers the overflow.
    inFrame.headers = @{
        @"bigheader" :  [@"" stringByPaddingToLength:MAX_HEADER_BLOCK_LENGTH
                                          withString:@"1234567890"
                                     startingAtIndex:0]
    };

    // Try with no error parameter
    STAssertEquals([_encoder encodeSynStreamFrame:inFrame error:nil], -1, nil);
    AssertFramesReceivedCount(0);

    // Try with error parameter
    NSError *error;
    STAssertEquals([_encoder encodeSynStreamFrame:inFrame error:&error], -1, nil);
    AssertFramesReceivedCount(0);
    STAssertNotNil(error, nil);
    STAssertEquals(error.domain, SPDYCodecErrorDomain, nil);
    STAssertEquals(error.code, SDPYHeaderBlockEncodingError, nil);
}

- (void)testSynStreamFrameWithTooLargeHeadersOnSizeField
{
    SPDYSynStreamFrame *inFrame = [[SPDYSynStreamFrame alloc] init];
    inFrame.streamId = arc4random() & 0x7FFFFFFF;
    inFrame.associatedToStreamId = arc4random() & 0x7FFFFFFF;
    inFrame.unidirectional = (bool)(arc4random() & 1);
    inFrame.last = (bool)(arc4random() & 1);
    inFrame.priority = (uint8_t)(arc4random() & 7);
    inFrame.slot = 0;

    // This will consume all the space except the last byte. Don't forget the header count (4)
    // and size of key (4). Encoding the size of the header value will overflow.
    NSString *headerKey = [@"" stringByPaddingToLength:(MAX_HEADER_BLOCK_LENGTH - 8 - 1)
                                            withString:@"1234567890"
                                       startingAtIndex:0];
    inFrame.headers = @{
            headerKey : @"headervalue"
    };

    NSError *error;
    STAssertEquals([_encoder encodeSynStreamFrame:inFrame error:&error], -1, nil);
    AssertFramesReceivedCount(0);
    STAssertNotNil(error, nil);
    STAssertEquals(error.domain, SPDYCodecErrorDomain, nil);
    STAssertEquals(error.code, SDPYHeaderBlockEncodingError, nil);
}

- (void)testSynReplyFrame
{
    SPDYSynReplyFrame *inFrame = [[SPDYSynReplyFrame alloc] init];
    inFrame.streamId = arc4random() & 0x7FFFFFFF;
    inFrame.last = (bool)(arc4random() & 1);

    // Header block is compressed. Hard to figure out exact size, so we'll use a lower bound.
    NSInteger bytesEncoded = [_encoder encodeSynReplyFrame:inFrame error:nil];
    STAssertTrue(bytesEncoded > 12, nil);

    AssertLastFrameClass(@"SPDYSynReplyFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYSynReplyFrame *outFrame = _mock.lastFrame;

    STAssertEquals(inFrame.streamId, outFrame.streamId, nil);
    STAssertEquals(inFrame.last, outFrame.last, nil);
}

- (void)testSynReplyFrameWithHeaders
{
    SPDYSynReplyFrame *inFrame = [[SPDYSynReplyFrame alloc] init];
    inFrame.streamId = arc4random() & 0x7FFFFFFF;
    inFrame.last = (bool)(arc4random() & 1);
    inFrame.headers = testHeaders();

    NSInteger bytesEncoded = [_encoder encodeSynReplyFrame:inFrame error:nil];
    STAssertTrue(bytesEncoded > 12, nil);

    AssertLastFrameClass(@"SPDYSynReplyFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYSynReplyFrame *outFrame = _mock.lastFrame;

    STAssertEquals(inFrame.streamId, outFrame.streamId, nil);
    STAssertEquals(inFrame.last, outFrame.last, nil);
    for (NSString *key in inFrame.headers) {
        STAssertTrue([inFrame.headers[key] isEqual:outFrame.headers[key]], nil);
    }
}

- (void)testRstStreamFrame
{
    SPDYRstStreamFrame *inFrame = [[SPDYRstStreamFrame alloc] init];
    inFrame.streamId = arc4random() & 0x7FFFFFFF;
    inFrame.statusCode = (SPDYStreamStatus)(arc4random() % 11 + 1);

    NSInteger bytesEncoded = [_encoder encodeRstStreamFrame:inFrame];
    STAssertEquals(bytesEncoded, 16, nil);

    AssertLastFrameClass(@"SPDYRstStreamFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYRstStreamFrame *outFrame = _mock.lastFrame;

    STAssertEquals(inFrame.streamId, outFrame.streamId, nil);
    STAssertEquals(inFrame.statusCode, outFrame.statusCode, nil);
}

- (void)testSettingsFrame
{
    SPDYSettingsFrame *inFrame = [[SPDYSettingsFrame alloc] init];
    inFrame.clearSettings = (bool)(arc4random() & 1);

    int k = arc4random() % (_SPDY_SETTINGS_RANGE_END - _SPDY_SETTINGS_RANGE_START) + 1;
    SPDYSettingsId chosenIds[k];

    int j = 0;
    SPDY_SETTINGS_ITERATOR(i) {
        if (j < k) {
            chosenIds[j] = i;
        } else if ( (arc4random() / (double)UINT32_MAX) < (k / (j+1.0)) ) {
            chosenIds[arc4random() % k] = i;
        }
        j++;
    }

    bool persisted = (bool)(arc4random() & 1);

    for (int i = 0; i < k; i++) {
        inFrame.settings[chosenIds[i]].set = YES;
        inFrame.settings[chosenIds[i]].flags = SPDY_SETTINGS_FLAG_PERSISTED * persisted;
        inFrame.settings[chosenIds[i]].value = arc4random();
    }

    NSInteger bytesEncoded = [_encoder encodeSettingsFrame:inFrame];
    STAssertEquals(bytesEncoded, 12 + (k * 8), nil);

    AssertLastFrameClass(@"SPDYSettingsFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYSettingsFrame *outFrame = _mock.lastFrame;

    STAssertEquals(inFrame.clearSettings, outFrame.clearSettings, nil);
    SPDY_SETTINGS_ITERATOR(i) {
        STAssertEquals(inFrame.settings[i].set, outFrame.settings[i].set, nil);
        if (inFrame.settings[i].set) {
            STAssertEquals(inFrame.settings[i].flags, outFrame.settings[i].flags, nil);
            STAssertEquals(inFrame.settings[i].value, outFrame.settings[i].value, nil);
        }
    }
}

- (void)testPingFrame
{
    SPDYPingFrame *inFrame = [[SPDYPingFrame alloc] init];
    inFrame.pingId = arc4random() & 0xFFFFFFFE;

    NSInteger bytesEncoded = [_encoder encodePingFrame:inFrame];
    STAssertEquals(bytesEncoded, 12, nil);

    AssertLastFrameClass(@"SPDYPingFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYPingFrame *outFrame = _mock.lastFrame;

    STAssertEquals(inFrame.pingId, outFrame.pingId, nil);
}

- (void)testGoAwayFrame
{
    SPDYGoAwayFrame *inFrame = [[SPDYGoAwayFrame alloc] init];
    inFrame.statusCode = (SPDYSessionStatus)(arc4random() % 3);

    NSInteger bytesEncoded = [_encoder encodeGoAwayFrame:inFrame];
    STAssertEquals(bytesEncoded, 16, nil);

    AssertLastFrameClass(@"SPDYGoAwayFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYGoAwayFrame *outFrame = _mock.lastFrame;

    STAssertEquals(inFrame.statusCode, outFrame.statusCode, nil);
}

- (void)testHeadersFrame
{
    SPDYHeadersFrame *inFrame = [[SPDYHeadersFrame alloc] init];
    inFrame.streamId = arc4random() & 0x7FFFFFFF;
    inFrame.last = (bool)(arc4random() & 1);

    // Header block is compressed. Hard to figure out exact size, so we'll use a lower bound.
    NSInteger bytesEncoded = [_encoder encodeHeadersFrame:inFrame error:nil];
    STAssertTrue(bytesEncoded > 12, nil);

    AssertLastFrameClass(@"SPDYHeadersFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYHeadersFrame *outFrame = _mock.lastFrame;

    STAssertEquals(inFrame.streamId, outFrame.streamId, nil);
    STAssertEquals(inFrame.last, outFrame.last, nil);
}

- (void)testHeadersFrameWithHeaders
{
    SPDYHeadersFrame *inFrame = [[SPDYHeadersFrame alloc] init];
    inFrame.streamId = arc4random() & 0x7FFFFFFF;
    inFrame.last = (bool)(arc4random() & 1);
    inFrame.headers = testHeaders();

    NSInteger bytesEncoded = [_encoder encodeHeadersFrame:inFrame error:nil];
    STAssertTrue(bytesEncoded > 12, nil);

    AssertLastFrameClass(@"SPDYHeadersFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYHeadersFrame *outFrame = _mock.lastFrame;

    STAssertEquals(inFrame.streamId, outFrame.streamId, nil);
    STAssertEquals(inFrame.last, outFrame.last, nil);
    for (NSString *key in inFrame.headers) {
        STAssertTrue([inFrame.headers[key] isEqual:outFrame.headers[key]], nil);
    }
}

- (void)testWindowUpdateFrame
{
    SPDYWindowUpdateFrame *inFrame = [[SPDYWindowUpdateFrame alloc] init];
    inFrame.streamId = arc4random() & 0x7FFFFFFF;
    inFrame.deltaWindowSize = arc4random() & 0x7FFFFFFF;

    NSInteger bytesEncoded = [_encoder encodeWindowUpdateFrame:inFrame];
    STAssertEquals(bytesEncoded, 16, nil);

    AssertLastFrameClass(@"SPDYWindowUpdateFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYWindowUpdateFrame *outFrame = _mock.lastFrame;

    STAssertEquals(inFrame.streamId, outFrame.streamId, nil);
    STAssertEquals(inFrame.deltaWindowSize, outFrame.deltaWindowSize, nil);
}

- (void)tearDown
{
    [super tearDown];
}

@end
