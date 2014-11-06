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

#import "SPDYCommonLogger.h"
#import "SPDYMetadata.h"
#import "SPDYProtocol.h"

@implementation SPDYMetadata
{
    NSString *_identifier;
}

/**
  Note about the SPDYMetadata identifier:

  This provides a mechanism for the metadata to be retrieved by the application at any point
  during processing of a request (well, after receiving the response or error). The application
  can request the metadata multiple times if it wants to track progress, or else wait until the
  connectionDidFinishLoading callback to get the final metadata.

  This is achieved by storing an opaque weak identifier in the headers/userInfo. This is used to
  look up the metadata in a dictionary with weak objects. The deallocation of the SPDYMetadata will
  remove the dictionary entry, though the object references will also be zeroed upon release.

  Lifetime of the SPDYMetadata is guaranteed by SPDYStream holding a strong reference to the
  SPDYMetadata, and an instance of SPDYProtocol (created by the URL loading system) holding
  a strong reference to the SPDYStream. As long as the URL loading system is being used for
  the NSURLProtocolClient delegate calls, the SPDYMetadata will be alive. It's after the
  last delegate call returns and everything is shutting down that the metadata will be released.

  We prevent such bad behavior by using the dictionary with weak object references, and extra
  insurance is provided by concatenating the SPDYMetadata's init timestamp with its pointer, in
  order to guarantee uniqueness in the case of memory address re-use and cached responses surviving
  across process invocations.
*/

static NSString * const SPDYMetadataIdentifierKey = @"x-spdy-metadata-identifier";

static dispatch_once_t __initIdentifiers;
static dispatch_queue_t __queueIdentifiers;
static NSMapTable *__identifiers;

+ (void)initialize
{
    dispatch_once(&__initIdentifiers, ^{
        __queueIdentifiers = dispatch_queue_create("com.twitter.SPDYMetadataQueue", DISPATCH_QUEUE_CONCURRENT);
        __identifiers = [NSMapTable strongToWeakObjectsMapTable];
    });
}

- (id)init
{
    self = [super init];
    if (self) {
        _version = @"3.1";
        _streamId = 0;
        _latencyMs = -1;
        _txBytes = 0;
        _rxBytes = 0;
        _connectedMs = 0;
        _blockedMs = 0;
        _hostAddress = nil;
        _hostPort = 0;

        NSUInteger ptr = (NSUInteger)self;
        CFAbsoluteTime timestamp = CFAbsoluteTimeGetCurrent();
        _identifier = [NSString stringWithFormat:@"%f/%tx", timestamp, ptr];

        dispatch_barrier_sync(__queueIdentifiers, ^{
            [__identifiers setObject:self forKey:_identifier];
        });
    }
    return self;
}

- (void)dealloc
{
    dispatch_barrier_sync(__queueIdentifiers, ^{
        [__identifiers removeObjectForKey:_identifier];
    });
}

- (NSString *)identifier
{
    return _identifier;
}

- (NSDictionary *)dictionary
{
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithDictionary:@{
        SPDYMetadataVersionKey : _version,
        SPDYMetadataStreamTxBytesKey : [@(_txBytes) stringValue],
        SPDYMetadataStreamRxBytesKey : [@(_rxBytes) stringValue],
        SPDYMetadataStreamConnectedMsKey : [@(_connectedMs) stringValue],
        SPDYMetadataStreamBlockedMsKey : [@(_blockedMs) stringValue],
    }];

    if (_streamId > 0) {
        dict[SPDYMetadataStreamIdKey] = [@(_streamId) stringValue];
    }

    if (_latencyMs > -1) {
        dict[SPDYMetadataSessionLatencyKey] = [@(_latencyMs) stringValue];
    }

    if ([_hostAddress length] > 0) {
        dict[SPDYMetadataSessionHostAddressKey] = _hostAddress;
        dict[SPDYMetadataSessionHostPortKey] = [@(_hostPort) stringValue];
    }

    return dict;
}

+ (void)setMetadata:(SPDYMetadata *)metadata forAssociatedDictionary:(NSMutableDictionary *)dictionary
{
    // This is a weak reference
    dictionary[SPDYMetadataIdentifierKey] = [metadata identifier];
}

+ (SPDYMetadata *)metadataForAssociatedDictionary:(NSDictionary *)dictionary;
{
    NSString *identifier = dictionary[SPDYMetadataIdentifierKey];
    SPDYMetadata __block *metadata = nil;

    if (identifier.length > 0) {
        dispatch_sync(__queueIdentifiers, ^{
            metadata = [__identifiers objectForKey:identifier];
        });
    }

    return metadata;
}

@end
