//
//  SPDYMetadataTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier.
//

#import <SenTestingKit/SenTestingKit.h>
#import "SPDYMetadata.h"
#import "SPDYProtocol.h"

@interface SPDYMetadataTest : SenTestCase
@end

@implementation SPDYMetadataTest

- (void)setUp {
    [super setUp];
}

- (void)tearDown
{
    [super tearDown];
}

- (SPDYMetadata *)createTestMetadata
{
    SPDYMetadata *metadata = [[SPDYMetadata alloc] init];
    metadata.version = @"3.2";
    metadata.streamId = 1;
    metadata.latencyMs = 100;
    metadata.txBytes = 200;
    metadata.rxBytes = 300;
    metadata.cellular = YES;
    metadata.blockedMs = 400;
    metadata.connectedMs = 500;
    metadata.hostAddress = @"1.2.3.4";
    metadata.hostPort = 1;
    metadata.viaProxy = YES;
    metadata.proxyStatus = SPDYProxyStatusManual;

    return metadata;
}

#pragma mark Tests

- (void)testSerializeToDictionaryDefault
{
    SPDYMetadata *metadata = [[SPDYMetadata alloc] init];
    NSDictionary *dict = [metadata dictionary];

    STAssertEqualObjects(dict[SPDYMetadataVersionKey], @"3.1", nil);
    STAssertNil(dict[SPDYMetadataStreamIdKey], nil);
    STAssertNil(dict[SPDYMetadataSessionLatencyKey], nil);
    STAssertEqualObjects(dict[SPDYMetadataStreamTxBytesKey], @"0", nil);
    STAssertEqualObjects(dict[SPDYMetadataStreamRxBytesKey], @"0", nil);
    STAssertEqualObjects(dict[SPDYMetadataStreamBlockedMsKey], @"0", nil);
    STAssertEqualObjects(dict[SPDYMetadataStreamConnectedMsKey], @"0", nil);
    STAssertNil(dict[SPDYMetadataSessionRemoteAddressKey], nil);
    STAssertNil(dict[SPDYMetadataSessionRemotePortKey], nil);
    STAssertEqualObjects(dict[SPDYMetadataSessionViaProxyKey], @"0", nil);
    STAssertEqualObjects(dict[SPDYMetadataSessionProxyStatusKey], @"0", nil);
}

- (void)testSerializeToDictionary
{
    SPDYMetadata *metadata = [self createTestMetadata];
    NSDictionary *dict = [metadata dictionary];

    STAssertEqualObjects(dict[SPDYMetadataVersionKey], @"3.2", nil);
    STAssertEqualObjects(dict[SPDYMetadataStreamIdKey], @"1", nil);
    STAssertEqualObjects(dict[SPDYMetadataSessionLatencyKey], @"100", nil);
    STAssertEqualObjects(dict[SPDYMetadataStreamTxBytesKey], @"200", nil);
    STAssertEqualObjects(dict[SPDYMetadataStreamRxBytesKey], @"300", nil);
    STAssertEqualObjects(dict[SPDYMetadataStreamBlockedMsKey], @"400", nil);
    STAssertEqualObjects(dict[SPDYMetadataStreamConnectedMsKey], @"500", nil);
    STAssertEqualObjects(dict[SPDYMetadataSessionRemoteAddressKey], @"1.2.3.4", nil);
    STAssertEqualObjects(dict[SPDYMetadataSessionRemotePortKey], @"1", nil);
    STAssertEqualObjects(dict[SPDYMetadataSessionViaProxyKey], @"1", nil);
    STAssertEqualObjects(dict[SPDYMetadataSessionProxyStatusKey], @"1", nil);
}

- (void)testMemberRetention
{
    // Test all references. Note we are creating strings with initWithFormat to ensure they
    // are released. Static strings are not dealloc'd.
    SPDYMetadata *metadata = [self createTestMetadata];
    NSString * __weak weakString = nil;  // just an extra check to ensure test works
    @autoreleasepool {
        NSString *testString = [[NSString alloc] initWithFormat:@"foo %d", 1];
        weakString = testString;

        metadata.hostAddress = [[NSString alloc] initWithFormat:@"%d.%d.%d.%d", 10, 11, 12, 13];
        metadata.version = [[NSString alloc] initWithFormat:@"SPDY/%d.%d", 3, 1];
    }

    STAssertNil(weakString, nil);

    NSDictionary *dict = [metadata dictionary];
    STAssertEqualObjects(dict[SPDYMetadataSessionRemoteAddressKey], @"10.11.12.13", nil);
    STAssertEqualObjects(dict[SPDYMetadataVersionKey], @"SPDY/3.1", nil);
}

- (void)testAssociatedDictionary
{
    SPDYMetadata *originalMetadata = [self createTestMetadata];
    NSMutableDictionary *associatedDictionary = [[NSMutableDictionary alloc] init];

    [SPDYMetadata setMetadata:originalMetadata forAssociatedDictionary:associatedDictionary];
    SPDYMetadata *metadata = [SPDYMetadata metadataForAssociatedDictionary:associatedDictionary];

    STAssertNotNil(metadata, nil);
    STAssertEqualObjects(metadata.version, @"3.2", nil);
    STAssertEquals(metadata.streamId, (SPDYStreamId)1, nil);
    STAssertEquals(metadata.latencyMs, (NSInteger)100, nil);
    STAssertEquals(metadata.txBytes, (NSUInteger)200, nil);
    STAssertEquals(metadata.rxBytes, (NSUInteger)300, nil);
}

- (void)testAssociatedDictionaryLastOneWins
{
    SPDYMetadata *originalMetadata1 = [self createTestMetadata];
    SPDYMetadata *originalMetadata2 = [self createTestMetadata];
    originalMetadata2.version = @"3.3";
    NSMutableDictionary *associatedDictionary = [[NSMutableDictionary alloc] init];

    [SPDYMetadata setMetadata:originalMetadata1 forAssociatedDictionary:associatedDictionary];
    [SPDYMetadata setMetadata:originalMetadata2 forAssociatedDictionary:associatedDictionary];
    SPDYMetadata *metadata = [SPDYMetadata metadataForAssociatedDictionary:associatedDictionary];

    // Last one wins
    STAssertNotNil(metadata, nil);
    STAssertEqualObjects(metadata.version, @"3.3", nil);
    STAssertEquals(metadata.streamId, (SPDYStreamId)1, nil);
    STAssertEquals(metadata.latencyMs, (NSInteger)100, nil);
    STAssertEquals(metadata.txBytes, (NSUInteger)200, nil);
    STAssertEquals(metadata.rxBytes, (NSUInteger)300, nil);
}

- (void)testAssociatedDictionaryWhenEmpty
{
    NSMutableDictionary *associatedDictionary = [[NSMutableDictionary alloc] init];
    SPDYMetadata *metadata = [SPDYMetadata metadataForAssociatedDictionary:associatedDictionary];
    STAssertNil(metadata, nil);
}

- (void)testMetadataAfterReleaseShouldNotBeNil
{
    NSMutableDictionary *associatedDictionary = [[NSMutableDictionary alloc] init];
    SPDYMetadata * __weak weakOriginalMetadata = nil;
    @autoreleasepool {
        SPDYMetadata *originalMetadata = [self createTestMetadata];
        weakOriginalMetadata = originalMetadata;
        [SPDYMetadata setMetadata:originalMetadata forAssociatedDictionary:associatedDictionary];
    }

    SPDYMetadata *metadata = [SPDYMetadata metadataForAssociatedDictionary:associatedDictionary];

    // Since the identifier maintains a reference, these will be alive
    STAssertNotNil(weakOriginalMetadata, nil);
    STAssertNotNil(metadata, nil);
}

- (void)testMetadataAfterAssociatedDictionaryDeallocShouldBeNil
{
    SPDYMetadata * __weak weakOriginalMetadata = nil;
    @autoreleasepool {
        SPDYMetadata *originalMetadata = [self createTestMetadata];
        weakOriginalMetadata = originalMetadata;
        NSMutableDictionary *associatedDictionary = [[NSMutableDictionary alloc] init];
        [SPDYMetadata setMetadata:originalMetadata forAssociatedDictionary:associatedDictionary];
    }

    STAssertNil(weakOriginalMetadata, nil);
}

- (void)testAssociatedDictionarySameRef
{
    NSMutableDictionary *associatedDictionary = [[NSMutableDictionary alloc] init];
    SPDYMetadata * __weak weakOriginalMetadata = nil;
    SPDYMetadata *metadata;
    @autoreleasepool {
        SPDYMetadata *originalMetadata = [self createTestMetadata];
        weakOriginalMetadata = originalMetadata;
        [SPDYMetadata setMetadata:originalMetadata forAssociatedDictionary:associatedDictionary];

        // Pull metadata out and keep a strong reference. To ensure this reference is the same
        // as the original one put in.
        metadata = [SPDYMetadata metadataForAssociatedDictionary:associatedDictionary];
    }

    STAssertNotNil(weakOriginalMetadata, nil);
    STAssertNotNil(metadata, nil);
}

@end

