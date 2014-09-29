//
//  SPDYMetadata.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore
//

#import "SPDYMetadata.h"
#import "SPDYProtocol.h"

@implementation SPDYMetadata

- (id)init
{
    self = [super init];
    if (self) {
        _version = @"3.1";
        _streamId = 0;
        _latencyMs = -1;
        _txBytes = 0;
        _rxBytes = 0;
    }
    return self;
}

- (NSDictionary *)dictionary
{
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithDictionary:@{
        SPDYMetadataVersionKey : _version,
        SPDYMetadataStreamTxBytesKey : [@(_txBytes) stringValue],
        SPDYMetadataStreamRxBytesKey : [@(_rxBytes) stringValue],
    }];

    if (_streamId > 0) {
        dict[SPDYMetadataStreamIdKey] = [@(_streamId) stringValue];
    }

    if (_latencyMs > -1) {
        dict[SPDYMetadataSessionLatencyKey] = [@(_latencyMs) stringValue];
    }

    return dict;
}

@end
