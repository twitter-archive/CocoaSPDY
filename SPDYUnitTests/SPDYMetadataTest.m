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

#import <XCTest/XCTest.h>
#import "SPDYMetadata+Utils.h"
#import "SPDYProtocol.h"

@interface SPDYMetadataTest : XCTestCase
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
    metadata.txBodyBytes = 150;
    metadata.rxBytes = 300;
    metadata.rxBodyBytes = 250;
    metadata.cellular = YES;
    metadata.blockedMs = 400;
    metadata.connectedMs = 500;
    metadata.hostAddress = @"1.2.3.4";
    metadata.hostPort = 1;
    metadata.viaProxy = YES;
    metadata.proxyStatus = SPDYProxyStatusManual;

    return metadata;
}

- (void)verifyTestMetadata:(SPDYMetadata *)metadata
{
    XCTAssertNotNil(metadata);
    XCTAssertEqualObjects(metadata.version, @"3.2");
    XCTAssertEqual(metadata.streamId, (NSUInteger)1);
    XCTAssertEqual(metadata.latencyMs, (NSInteger)100);
    XCTAssertEqual(metadata.txBytes, (NSUInteger)200);
    XCTAssertEqual(metadata.txBodyBytes, (NSUInteger)150);
    XCTAssertEqual(metadata.rxBytes, (NSUInteger)300);
    XCTAssertEqual(metadata.rxBodyBytes, (NSUInteger)250);
    XCTAssertEqual(metadata.cellular, YES);
    XCTAssertEqual(metadata.blockedMs, (NSUInteger)400);
    XCTAssertEqual(metadata.connectedMs, (NSUInteger)500);
    XCTAssertEqualObjects(metadata.hostAddress, @"1.2.3.4");
    XCTAssertEqual(metadata.hostPort, (NSUInteger)1);
    XCTAssertEqual(metadata.viaProxy, YES);
    XCTAssertEqual(metadata.proxyStatus, SPDYProxyStatusManual);
}

#pragma mark Tests

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

    XCTAssertNil(weakString);

    XCTAssertEqualObjects(metadata.hostAddress, @"10.11.12.13");
    XCTAssertEqualObjects(metadata.version, @"SPDY/3.1");
}

- (void)testAssociatedDictionary
{
    SPDYMetadata *originalMetadata = [self createTestMetadata];
    NSMutableDictionary *associatedDictionary = [[NSMutableDictionary alloc] init];

    [SPDYMetadata setMetadata:originalMetadata forAssociatedDictionary:associatedDictionary];
    SPDYMetadata *metadata = [SPDYMetadata metadataForAssociatedDictionary:associatedDictionary];

    [self verifyTestMetadata:metadata];
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
    XCTAssertNotNil(metadata);
    XCTAssertEqualObjects(metadata.version, @"3.3");
    XCTAssertEqual(metadata.streamId, (NSUInteger)1);
    XCTAssertEqual(metadata.latencyMs, (NSInteger)100);
    XCTAssertEqual(metadata.txBytes, (NSUInteger)200);
    XCTAssertEqual(metadata.rxBytes, (NSUInteger)300);
}

- (void)testAssociatedDictionaryWhenEmpty
{
    NSMutableDictionary *associatedDictionary = [[NSMutableDictionary alloc] init];
    SPDYMetadata *metadata = [SPDYMetadata metadataForAssociatedDictionary:associatedDictionary];
    XCTAssertNil(metadata);
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
    XCTAssertNotNil(weakOriginalMetadata);
    XCTAssertNotNil(metadata);
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

    XCTAssertNil(weakOriginalMetadata);
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

    XCTAssertNotNil(weakOriginalMetadata);
    XCTAssertNotNil(metadata);
}

- (void)testAssociatedDictionaryDoesMutateOriginal
{
    // We don't necessarily want to allow mutating the original, but this documents the behavior.
    // The public SPDYMetadata interface exposes all properties as readonly.
    NSMutableDictionary *associatedDictionary = [[NSMutableDictionary alloc] init];
    SPDYMetadata *metadata;

    SPDYMetadata *originalMetadata = [self createTestMetadata];
    [SPDYMetadata setMetadata:originalMetadata forAssociatedDictionary:associatedDictionary];

    metadata = [SPDYMetadata metadataForAssociatedDictionary:associatedDictionary];
    metadata.version = @"3.3";
    metadata.streamId = 2;
    metadata.cellular = NO;
    metadata.proxyStatus = SPDYProxyStatusAuto;

    // If not mutating
    //[self verifyTestMetadata:originalMetadata];

    // If mutating
    XCTAssertEqualObjects(metadata.version, @"3.3");
    XCTAssertEqual(metadata.streamId, (NSUInteger)2);
    XCTAssertEqual(metadata.cellular, NO);
    XCTAssertEqual(metadata.proxyStatus, SPDYProxyStatusAuto);
}

@end

