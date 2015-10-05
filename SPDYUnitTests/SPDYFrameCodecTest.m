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

#import <XCTest/XCTest.h>
#import "SPDYError.h"
#import "SPDYFrameEncoder.h"
#import "SPDYFrameDecoder.h"
#import "SPDYMockFrameDecoderDelegate.h"

static NSUInteger gMaxDecodeChunkSize = 0;

@interface SPDYFrameCodecTest : XCTestCase
@end

@interface SPDYFrameDecoder (CodecTest) <SPDYFrameEncoderDelegate>
- (void)didEncodeData:(NSData *)data frameEncoder:(SPDYFrameEncoder *)encoder;
@end

@implementation SPDYFrameDecoder (CodecTest)
- (void)_decodeData:(NSData *)data
{
    NSError *error;
    if (gMaxDecodeChunkSize == 0) {
        [self decode:(uint8_t *)data.bytes length:data.length error:&error];
    } else {
        NSUInteger remaining = data.length;
        uint8_t *dataPtr = (uint8_t *)data.bytes;
        while (remaining > 0) {
            NSUInteger chunkSize = MIN(gMaxDecodeChunkSize, remaining);
            [self decode:dataPtr length:chunkSize error:&error];
            remaining -= chunkSize;
            dataPtr += chunkSize;
        }
    }
}

- (void)didEncodeData:(NSData *)data frameEncoder:(SPDYFrameEncoder *)encoder
{
    [self _decodeData:data];
}

- (void)didEncodeData:(NSData *)data withTag:(uint32_t)tag frameEncoder:(SPDYFrameEncoder *)encoder
{
    [self _decodeData:data];
}

@end

@implementation SPDYFrameCodecTest
{
    SPDYMockFrameDecoderDelegate *_mock;
    SPDYFrameEncoder *_encoder;
    SPDYFrameDecoder *_decoder;
}

#define AssertLastFrameClass(CLASS_NAME) \
    XCTAssertEqualObjects(NSStringFromClass([_mock.lastFrame class]), CLASS_NAME, @"expected mock delegate's last frame received to be of class %@, but was %@", CLASS_NAME, NSStringFromClass([_mock.lastFrame class]))

#define AssertFramesReceivedCount(COUNT) \
    XCTAssertTrue(_mock.frameCount == COUNT, @"expected property framesReceived of mock delegate to contain %d elements, but had %tu elements", COUNT, _mock.frameCount)

#define AssertLastDelegateMessage(SELECTOR_NAME) \
    XCTAssertEqualObjects(_mock.lastDelegateMessage, SELECTOR_NAME, @"expected mock delegate's last message received to be %@ but was %tu", SELECTOR_NAME, _mock.lastDelegateMessage)

#define AssertDecodedFrameLength(LENGTH) \
    XCTAssertEqual(((SPDYFrame *)_mock.lastFrame).encodedLength, (NSUInteger)LENGTH, @"expected the decoded frame to be %zd bytes but got %tu bytes", LENGTH, ((SPDYFrame *)_mock.lastFrame).encodedLength)

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

    gMaxDecodeChunkSize = 0;  // reset on every test
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
    XCTAssertEqual(bytesEncoded, 108);

    AssertLastFrameClass(@"SPDYDataFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYDataFrame *outFrame = _mock.lastFrame;

    XCTAssertEqual(inFrame.streamId, outFrame.streamId);
    XCTAssertEqual(inFrame.last, outFrame.last);
    XCTAssertEqual(inFrame.data.length, outFrame.data.length);
    XCTAssertEqual(outFrame.headerLength, (NSUInteger)8);
    for (uint8_t i = 0; i < 100; i++) {
        XCTAssertEqual(((uint8_t *)inFrame.data.bytes)[i], ((uint8_t *)outFrame.data.bytes)[i]);
    }
}

- (void)testDecodePartialDataFrame
{
    gMaxDecodeChunkSize = 90;

    SPDYDataFrame *inFrame = [[SPDYDataFrame alloc] init];
    inFrame.streamId = arc4random() & 0x7FFFFFFF;
    inFrame.last = YES;

    uint8_t data[100];
    for (uint8_t i = 0; i < 100; i++) {
        data[i] = i;
    }

    inFrame.data = [[NSData alloc] initWithBytes:data length:100];

    NSInteger bytesEncoded = [_encoder encodeDataFrame:inFrame];
    XCTAssertEqual(bytesEncoded, 108);

    AssertLastFrameClass(@"SPDYDataFrame");
    AssertFramesReceivedCount(2);

    SPDYDataFrame *outFrame1 = (SPDYDataFrame *)_mock.framesReceived[0];
    SPDYDataFrame *outFrame2 = (SPDYDataFrame *)_mock.framesReceived[1];


    XCTAssertEqual(inFrame.streamId, outFrame1.streamId);
    XCTAssertEqual(inFrame.streamId, outFrame2.streamId);
    XCTAssertFalse(outFrame1.last);
    XCTAssertTrue(outFrame2.last);

    const NSUInteger outFrame1DataLength = gMaxDecodeChunkSize;
    XCTAssertEqual(outFrame1.encodedLength, (NSUInteger)bytesEncoded);
    XCTAssertEqual(outFrame1.data.length, outFrame1DataLength);
    XCTAssertEqual(outFrame1.headerLength, (NSUInteger)8);
    for (uint8_t i = 0; i < outFrame1DataLength; i++) {
        XCTAssertEqual(((uint8_t *)inFrame.data.bytes)[i], ((uint8_t *)outFrame1.data.bytes)[i]);
    }

    const NSUInteger outFrame2DataLength = inFrame.data.length - outFrame1DataLength;
    XCTAssertEqual(outFrame2.encodedLength, (NSUInteger)bytesEncoded);
    XCTAssertEqual(outFrame2.data.length, (NSUInteger)outFrame2DataLength);
    XCTAssertEqual(outFrame2.headerLength, (NSUInteger)0);
    for (uint8_t i = 0; i < outFrame2DataLength; i++) {
        XCTAssertEqual(((uint8_t *)inFrame.data.bytes)[outFrame1DataLength + i], ((uint8_t *)outFrame2.data.bytes)[i]);
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
    XCTAssertTrue(bytesEncoded > 18);

    AssertLastFrameClass(@"SPDYSynStreamFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYSynStreamFrame *outFrame = _mock.lastFrame;

    XCTAssertEqual(inFrame.streamId, outFrame.streamId);
    XCTAssertEqual(inFrame.associatedToStreamId, outFrame.associatedToStreamId);
    XCTAssertEqual(inFrame.unidirectional, outFrame.unidirectional);
    XCTAssertEqual(inFrame.last, outFrame.last);
    XCTAssertEqual(inFrame.priority, outFrame.priority);
    XCTAssertEqual(inFrame.slot, outFrame.slot);
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
    XCTAssertTrue(bytesEncoded > 18);

    AssertLastFrameClass(@"SPDYSynStreamFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYSynStreamFrame *outFrame = _mock.lastFrame;

    XCTAssertEqual(inFrame.streamId, outFrame.streamId);
    XCTAssertEqual(inFrame.associatedToStreamId, outFrame.associatedToStreamId);
    XCTAssertEqual(inFrame.unidirectional, outFrame.unidirectional);
    XCTAssertEqual(inFrame.last, outFrame.last);
    XCTAssertEqual(inFrame.priority, outFrame.priority);
    XCTAssertEqual(inFrame.slot, outFrame.slot);
    for (NSString *key in inFrame.headers) {
        XCTAssertTrue([inFrame.headers[key] isEqual:outFrame.headers[key]]);
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
    XCTAssertEqual([_encoder encodeSynStreamFrame:inFrame error:nil], -1);
    AssertFramesReceivedCount(0);

    // Try with error parameter
    NSError *error;
    XCTAssertEqual([_encoder encodeSynStreamFrame:inFrame error:&error], -1);
    AssertFramesReceivedCount(0);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.domain, SPDYCodecErrorDomain);
    XCTAssertEqual(error.code, SPDYHeaderBlockEncodingError);
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
    XCTAssertEqual([_encoder encodeSynStreamFrame:inFrame error:&error], -1);
    AssertFramesReceivedCount(0);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.domain, SPDYCodecErrorDomain);
    XCTAssertEqual(error.code, SPDYHeaderBlockEncodingError);
}

- (void)testSynReplyFrame
{
    SPDYSynReplyFrame *inFrame = [[SPDYSynReplyFrame alloc] init];
    inFrame.streamId = arc4random() & 0x7FFFFFFF;
    inFrame.last = (bool)(arc4random() & 1);

    // Header block is compressed. Hard to figure out exact size, so we'll use a lower bound.
    NSInteger bytesEncoded = [_encoder encodeSynReplyFrame:inFrame error:nil];
    XCTAssertTrue(bytesEncoded > 12);

    AssertLastFrameClass(@"SPDYSynReplyFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYSynReplyFrame *outFrame = _mock.lastFrame;

    XCTAssertEqual(inFrame.streamId, outFrame.streamId);
    XCTAssertEqual(inFrame.last, outFrame.last);
}

- (void)testSynReplyFrameWithHeaders
{
    SPDYSynReplyFrame *inFrame = [[SPDYSynReplyFrame alloc] init];
    inFrame.streamId = arc4random() & 0x7FFFFFFF;
    inFrame.last = (bool)(arc4random() & 1);
    inFrame.headers = testHeaders();

    NSInteger bytesEncoded = [_encoder encodeSynReplyFrame:inFrame error:nil];
    XCTAssertTrue(bytesEncoded > 12);

    AssertLastFrameClass(@"SPDYSynReplyFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYSynReplyFrame *outFrame = _mock.lastFrame;

    XCTAssertEqual(inFrame.streamId, outFrame.streamId);
    XCTAssertEqual(inFrame.last, outFrame.last);
    for (NSString *key in inFrame.headers) {
        XCTAssertTrue([inFrame.headers[key] isEqual:outFrame.headers[key]]);
    }
}

- (void)testRstStreamFrame
{
    SPDYRstStreamFrame *inFrame = [[SPDYRstStreamFrame alloc] init];
    inFrame.streamId = arc4random() & 0x7FFFFFFF;
    inFrame.statusCode = (SPDYStreamStatus)(arc4random() % 11 + 1);

    NSInteger bytesEncoded = [_encoder encodeRstStreamFrame:inFrame];
    XCTAssertEqual(bytesEncoded, 16);

    AssertLastFrameClass(@"SPDYRstStreamFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYRstStreamFrame *outFrame = _mock.lastFrame;

    XCTAssertEqual(inFrame.streamId, outFrame.streamId);
    XCTAssertEqual(inFrame.statusCode, outFrame.statusCode);
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
    XCTAssertEqual(bytesEncoded, 12 + (k * 8));

    AssertLastFrameClass(@"SPDYSettingsFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYSettingsFrame *outFrame = _mock.lastFrame;

    XCTAssertEqual(inFrame.clearSettings, outFrame.clearSettings);
    SPDY_SETTINGS_ITERATOR(i) {
        XCTAssertEqual(inFrame.settings[i].set, outFrame.settings[i].set);
        if (inFrame.settings[i].set) {
            XCTAssertEqual(inFrame.settings[i].flags, outFrame.settings[i].flags);
            XCTAssertEqual(inFrame.settings[i].value, outFrame.settings[i].value);
        }
    }
}

- (void)testPingFrame
{
    SPDYPingFrame *inFrame = [[SPDYPingFrame alloc] init];
    inFrame.pingId = arc4random() & 0xFFFFFFFE;

    NSInteger bytesEncoded = [_encoder encodePingFrame:inFrame];
    XCTAssertEqual(bytesEncoded, 12);

    AssertLastFrameClass(@"SPDYPingFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYPingFrame *outFrame = _mock.lastFrame;

    XCTAssertEqual(inFrame.pingId, outFrame.pingId);
}

- (void)testGoAwayFrame
{
    SPDYGoAwayFrame *inFrame = [[SPDYGoAwayFrame alloc] init];
    inFrame.statusCode = (SPDYSessionStatus)(arc4random() % 3);

    NSInteger bytesEncoded = [_encoder encodeGoAwayFrame:inFrame];
    XCTAssertEqual(bytesEncoded, 16);

    AssertLastFrameClass(@"SPDYGoAwayFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYGoAwayFrame *outFrame = _mock.lastFrame;

    XCTAssertEqual(inFrame.statusCode, outFrame.statusCode);
}

- (void)testHeadersFrame
{
    SPDYHeadersFrame *inFrame = [[SPDYHeadersFrame alloc] init];
    inFrame.streamId = arc4random() & 0x7FFFFFFF;
    inFrame.last = (bool)(arc4random() & 1);

    // Header block is compressed. Hard to figure out exact size, so we'll use a lower bound.
    NSInteger bytesEncoded = [_encoder encodeHeadersFrame:inFrame error:nil];
    XCTAssertTrue(bytesEncoded > 12);

    AssertLastFrameClass(@"SPDYHeadersFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYHeadersFrame *outFrame = _mock.lastFrame;

    XCTAssertEqual(inFrame.streamId, outFrame.streamId);
    XCTAssertEqual(inFrame.last, outFrame.last);
}

- (void)testHeadersFrameWithHeaders
{
    SPDYHeadersFrame *inFrame = [[SPDYHeadersFrame alloc] init];
    inFrame.streamId = arc4random() & 0x7FFFFFFF;
    inFrame.last = (bool)(arc4random() & 1);
    inFrame.headers = testHeaders();

    NSInteger bytesEncoded = [_encoder encodeHeadersFrame:inFrame error:nil];
    XCTAssertTrue(bytesEncoded > 12);

    AssertLastFrameClass(@"SPDYHeadersFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYHeadersFrame *outFrame = _mock.lastFrame;

    XCTAssertEqual(inFrame.streamId, outFrame.streamId);
    XCTAssertEqual(inFrame.last, outFrame.last);
    for (NSString *key in inFrame.headers) {
        XCTAssertTrue([inFrame.headers[key] isEqual:outFrame.headers[key]]);
    }
}

- (void)testWindowUpdateFrame
{
    SPDYWindowUpdateFrame *inFrame = [[SPDYWindowUpdateFrame alloc] init];
    inFrame.streamId = arc4random() & 0x7FFFFFFF;
    inFrame.deltaWindowSize = arc4random() & 0x7FFFFFFF;

    NSInteger bytesEncoded = [_encoder encodeWindowUpdateFrame:inFrame];
    XCTAssertEqual(bytesEncoded, 16);

    AssertLastFrameClass(@"SPDYWindowUpdateFrame");
    AssertFramesReceivedCount(1);
    AssertDecodedFrameLength(bytesEncoded);

    SPDYWindowUpdateFrame *outFrame = _mock.lastFrame;

    XCTAssertEqual(inFrame.streamId, outFrame.streamId);
    XCTAssertEqual(inFrame.deltaWindowSize, outFrame.deltaWindowSize);
}

- (void)tearDown
{
    [super tearDown];
}

@end
