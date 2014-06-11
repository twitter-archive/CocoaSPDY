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
#import "SPDYFrameEncoder.h"
#import "SPDYFrameDecoder.h"
#import "SPDYMockFrameDecoderDelegate.h"

@interface SPDYFrameCodecTest : XCTestCase
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
    XCTAssertEqualObjects(NSStringFromClass([_mock.lastFrame class]), CLASS_NAME, @"expected mock delegate's last frame received to be of class %@, but was %@", CLASS_NAME, NSStringFromClass([_mock.lastFrame class]))

#define AssertFramesReceivedCount(COUNT) \
    XCTAssertTrue(_mock.frameCount == COUNT, @"expected property framesReceived of mock delegate to contain %d elements, but had %d elements", COUNT, _mock.frameCount)

#define AssertLastDelegateMessage(SELECTOR_NAME) \
    XCTAssertEqualObjects(_mock.lastDelegateMessage, SELECTOR_NAME, @"expected mock delegate's last message received to be %@ but was %@", SELECTOR_NAME, _mock.lastDelegateMessage)

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

    [_encoder encodeDataFrame:inFrame];

    AssertLastFrameClass(@"SPDYDataFrame");
    AssertFramesReceivedCount(1);

    SPDYDataFrame *outFrame = _mock.lastFrame;

    XCTAssertEqual(inFrame.streamId, outFrame.streamId);
    XCTAssertEqual(inFrame.last, outFrame.last);
    XCTAssertEqual(inFrame.data.length, outFrame.data.length);
    for (uint8_t i = 0; i < 100; i++) {
        XCTAssertEqual(((uint8_t *)inFrame.data.bytes)[i], ((uint8_t *)outFrame.data.bytes)[i]);
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

    [_encoder encodeSynStreamFrame:inFrame];

    AssertLastFrameClass(@"SPDYSynStreamFrame");
    AssertFramesReceivedCount(1);

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

    [_encoder encodeSynStreamFrame:inFrame];

    AssertLastFrameClass(@"SPDYSynStreamFrame");
    AssertFramesReceivedCount(1);

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

- (void)testSynReplyFrame
{
    SPDYSynReplyFrame *inFrame = [[SPDYSynReplyFrame alloc] init];
    inFrame.streamId = arc4random() & 0x7FFFFFFF;
    inFrame.last = (bool)(arc4random() & 1);

    [_encoder encodeSynReplyFrame:inFrame];

    AssertLastFrameClass(@"SPDYSynReplyFrame");
    AssertFramesReceivedCount(1);

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

    [_encoder encodeSynReplyFrame:inFrame];

    AssertLastFrameClass(@"SPDYSynReplyFrame");
    AssertFramesReceivedCount(1);

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

    [_encoder encodeRstStreamFrame:inFrame];

    AssertLastFrameClass(@"SPDYRstStreamFrame");
    AssertFramesReceivedCount(1);

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

    [_encoder encodeSettingsFrame:inFrame];

    AssertLastFrameClass(@"SPDYSettingsFrame");
    AssertFramesReceivedCount(1);

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

    [_encoder encodePingFrame:inFrame];

    AssertLastFrameClass(@"SPDYPingFrame");
    AssertFramesReceivedCount(1);

    SPDYPingFrame *outFrame = _mock.lastFrame;

    XCTAssertEqual(inFrame.pingId, outFrame.pingId);
}

- (void)testGoAwayFrame
{
    SPDYGoAwayFrame *inFrame = [[SPDYGoAwayFrame alloc] init];
    inFrame.statusCode = (SPDYSessionStatus)(arc4random() % 3);

    [_encoder encodeGoAwayFrame:inFrame];

    AssertLastFrameClass(@"SPDYGoAwayFrame");
    AssertFramesReceivedCount(1);

    SPDYGoAwayFrame *outFrame = _mock.lastFrame;

    XCTAssertEqual(inFrame.statusCode, outFrame.statusCode);
}

- (void)testHeadersFrame
{
    SPDYHeadersFrame *inFrame = [[SPDYHeadersFrame alloc] init];
    inFrame.streamId = arc4random() & 0x7FFFFFFF;
    inFrame.last = (bool)(arc4random() & 1);

    [_encoder encodeHeadersFrame:inFrame];

    AssertLastFrameClass(@"SPDYHeadersFrame");
    AssertFramesReceivedCount(1);

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

    [_encoder encodeHeadersFrame:inFrame];

    AssertLastFrameClass(@"SPDYHeadersFrame");
    AssertFramesReceivedCount(1);

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

    [_encoder encodeWindowUpdateFrame:inFrame];

    AssertLastFrameClass(@"SPDYWindowUpdateFrame");
    AssertFramesReceivedCount(1);

    SPDYWindowUpdateFrame *outFrame = _mock.lastFrame;

    XCTAssertEqual(inFrame.streamId, outFrame.streamId);
    XCTAssertEqual(inFrame.deltaWindowSize, outFrame.deltaWindowSize);
}

- (void)tearDown
{
    [super tearDown];
}

@end
