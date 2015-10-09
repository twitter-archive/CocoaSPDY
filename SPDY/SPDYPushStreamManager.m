//
//  SPDYPushStreamManager.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier.
//

#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import "SPDYCommonLogger.h"
#import "SPDYPushStreamManager.h"
#import "SPDYProtocol.h"
#import "SPDYStream.h"

#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "This file requires ARC support."
#endif

@implementation NSURLRequest (SPDYPushStreamManager)

- (NSString *)keyForMemoryCache
{
    NSString *urlString = self.URL.absoluteString;
    NSString *userAgent = [self valueForHTTPHeaderField:@"user-agent"];
    return [NSString stringWithFormat:@"%@__%@", urlString, userAgent];
}

@end

@interface SPDYPushStreamManager ()
- (void)removeStream:(SPDYStream *)stream;
@end

@interface SPDYPushStreamNode : NSObject <NSURLProtocolClient>
@property (nonatomic, readonly) SPDYStream *stream;
@property (nonatomic, readonly) SPDYStream *associatedStream;
- (id)initWithStream:(SPDYStream *)stream associatedStream:(SPDYStream *)associatedStream;
- (SPDYStream *)attachStreamToProtocol:(SPDYProtocol *)protocol;
@end

@implementation SPDYPushStreamNode
{
    NSURLResponse *_response;
    NSURLCacheStoragePolicy _cacheStoragePolicy;
    NSMutableData *_data;
    NSError *_error;
    BOOL _done;
}

- (id)initWithStream:(SPDYStream *)stream associatedStream:(SPDYStream *)associatedStream;
{
    self = [super init];
    if (self) {
        _stream = stream;
        _associatedStream = associatedStream;
        _data = [[NSMutableData alloc] init];

        // Take ownership of callbacks
        _stream.client = self;
    }
    return self;
}

- (SPDYStream *)attachStreamToProtocol:(SPDYProtocol *)protocol
{
    if (protocol.client == nil) {
        SPDY_ERROR(@"PUSH.%u: can't attach stream to protocol with nil client", _stream.streamId);
        return nil;
    }

    _stream.protocol = protocol;
    _stream.client = protocol.client;

    // @@@ Compare protocol.request with _stream.request?

    // Play "catch up" on missed callbacks

    if (_response) {
        SPDY_DEBUG(@"PUSH.%u: replaying didReceiveResponse: %@", _stream.streamId, _response);
        [protocol.client URLProtocol:protocol didReceiveResponse:_response cacheStoragePolicy:_cacheStoragePolicy];

        if (_data.length > 0) {
            SPDY_DEBUG(@"PUSH.%u: replaying didLoadData: %zd bytes", _stream.streamId, _data.length);
            [protocol.client URLProtocol:protocol didLoadData:_data];
        }
    }

    if (_error) {
        SPDY_DEBUG(@"PUSH.%u: replaying didFailWithError: %@", _stream.streamId, _error);
        [protocol.client URLProtocol:protocol didFailWithError:_error];
    } else if (_done) {
        SPDY_DEBUG(@"PUSH.%u: replaying didFinishLoading", _stream.streamId);
        [protocol.client URLProtocolDidFinishLoading:protocol];
    }

    return _stream;
}

#pragma mark URLProtocolClient overrides

// Note: protocol will be nil for all of these.

- (void)URLProtocol:(NSURLProtocol *)protocol didReceiveResponse:(NSURLResponse *)response cacheStoragePolicy:(NSURLCacheStoragePolicy)policy
{
    SPDY_DEBUG(@"PUSH.%u: internal URLProtocol received response %@, cache policy %zd", _stream.streamId, response, policy);
    _response = response;
    _cacheStoragePolicy = policy;
}

- (void)URLProtocol:(NSURLProtocol *)protocol didLoadData:(NSData *)data
{
    SPDY_DEBUG(@"PUSH.%u: internal URLProtocol loaded %zd data bytes", _stream.streamId, data.length);
    [_data appendData:data];
}

- (void)URLProtocolDidFinishLoading:(NSURLProtocol *)protocol
{
    SPDY_DEBUG(@"PUSH.%u: internal URLProtocol finished", _stream.streamId);
    _done = YES;
    // @@@ TODO: cache it in NSURLCache per _cacheStoragePolicy?
    [_stream.pushStreamManager stopLoadingStream:_stream];
}

- (void)URLProtocol:(NSURLProtocol *)protocol didFailWithError:(NSError *)error
{
    SPDY_DEBUG(@"PUSH.%u: internal URLProtocol failed with error: %@", _stream.streamId, error);
    _error = error;
    [_stream.pushStreamManager removeStream:_stream];
}

- (void)URLProtocol:(NSURLProtocol *)protocol wasRedirectedToRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse
{
    NSAssert(false, @"not supported for push requests");
}

- (void)URLProtocol:(NSURLProtocol *)protocol cachedResponseIsValid:(NSCachedURLResponse *)cachedResponse
{
    NSAssert(false, @"not supported for push requests");
}

- (void)URLProtocol:(NSURLProtocol *)protocol didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSAssert(false, @"not supported for push requests");
}

- (void)URLProtocol:(NSURLProtocol *)protocol didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSAssert(false, @"not supported for push requests");
}

@end


@implementation SPDYPushStreamManager
{
    NSMapTable *_streamToNodeMap;
    NSMapTable *_requestToNodeMap;
    NSMapTable *_associatedStreamToNodeArrayMap;
}

- (id)init
{
    self = [super init];
    if (self) {
        _streamToNodeMap = [NSMapTable strongToStrongObjectsMapTable];
        _requestToNodeMap = [NSMapTable strongToStrongObjectsMapTable];
        _associatedStreamToNodeArrayMap = [NSMapTable strongToStrongObjectsMapTable];
    }
    return self;
}

- (NSUInteger)pushStreamCount
{
    return _streamToNodeMap.count;
}

- (NSUInteger)associatedStreamCount
{
    return _associatedStreamToNodeArrayMap.count;
}

- (SPDYStream *)streamForProtocol:(SPDYProtocol *)protocol
{
    // This lookup in our "cache" is only based on the URL and user agent. It is not quite the
    // same as a standard HTTP cache lookup. protocol.request has already been canonicalized.
    SPDYPushStreamNode *node = [_requestToNodeMap objectForKey:[protocol.request keyForMemoryCache]];

    if (node == nil) {
        return nil;
    }

    [self removeStream:node.stream];

    SPDY_DEBUG(@"PUSH.%u: attaching push stream to protocol for request %@", node.stream.streamId, protocol.request.URL);
    return [node attachStreamToProtocol:protocol];
}

- (void)addStream:(SPDYStream *)stream associatedWithStream:(SPDYStream *)associatedStream
{
    SPDY_INFO(@"PUSH.%u: adding stream (%@) associated with stream %u (%@)", stream.streamId, stream.request.URL, associatedStream.streamId, associatedStream.request.URL);

    // We're taking ownership of this stream
    NSAssert(!stream.local, @"must be a push stream");
    NSAssert(stream.client == nil, @"push streams must have no owner");

    SPDYPushStreamNode *node = [[SPDYPushStreamNode alloc] initWithStream:stream associatedStream:associatedStream];

    // In the event a stream with matching request already exists, the new one wins.
    [_streamToNodeMap setObject:node forKey:stream];

    // Add mapping from original request to push requests. Allows us to cancel all push
    // requests if the original request is cancelled.
    if (associatedStream) {
        NSAssert(associatedStream.local, @"associated stream must be local");
        if ([_associatedStreamToNodeArrayMap objectForKey:associatedStream] == nil) {
            [_associatedStreamToNodeArrayMap setObject:[[NSMutableArray alloc] initWithObjects:node, nil] forKey:associatedStream];
        } else {
            [[_associatedStreamToNodeArrayMap objectForKey:associatedStream] addObject:node];
        }
    }

    // Add mapping from URL to node to provide cache lookups
    NSAssert(stream.request, @"push stream must have a request object");
    [_requestToNodeMap setObject:node forKey:[stream.request keyForMemoryCache]];
}

- (void)stopLoadingStream:(SPDYStream *)stream
{
    // Various conditions considered here for 'stream':
    // [local, open] Remove stream (it's being cancelled). All related remote streams will also be cancelled and removed.
    // [local, closed] Remove stream. All related closed remote streams will be removed.
    // [remote, open] Remove stream (it's being cancelled).
    // [remote, closed] Remove stream only if its associated local stream has been removed, or if it failed.
    if (stream.local) {
        // Make copy because removeStream will mutate the underlying array
        NSArray *pushNodes = [[_associatedStreamToNodeArrayMap objectForKey:stream] copy];
        if (pushNodes.count > 0) {
            for (SPDYPushStreamNode *pushNode in pushNodes) {
                if (!stream.closed) {
                    SPDY_DEBUG(@"PUSH.%u: stopping local stream, cancelling pushed stream %u", stream.streamId, pushNode.stream.streamId);
                    [pushNode.stream cancel];
                    [self removeStream:pushNode.stream];
                } else if (pushNode.stream.closed) {
                    SPDY_DEBUG(@"PUSH.%u: stopping local stream, removing pushed stream %u", stream.streamId, pushNode.stream.streamId);
                    [self removeStream:pushNode.stream];
                } else {
                    // else open push streams are left alone until they finish
                    SPDY_DEBUG(@"PUSH.%u: stopping local stream, leaving pushed stream %u", stream.streamId, pushNode.stream.streamId);
                }
            }
        }
        [self removeStream:stream];
    } else {
        // We only remove a pushed stream that is stopping when it has no associated stream.
        // If it does have one, then we leave it here in the in-memory cache until either
        // a new request attaches to it (see streamForProtocol), or the associated stream stops
        // (see stopLoadingStream for the local stream case when the pushed stream is closed).
        //
        // TODO: this is where we should insert the response into a NSURLCache and remove it
        // from the in-memory cache here, for both cases. In particular, leaving the push stream
        // around while the associated stream is open could lead to leaks if the app never
        // issues requests that hook up to the pushed streams.
        SPDYStream *associatedStream = stream.associatedStream;  // get strong reference
        BOOL hasAssociatedStream = (associatedStream && [_associatedStreamToNodeArrayMap objectForKey:associatedStream]);
        if (!hasAssociatedStream) {
            SPDY_DEBUG(@"PUSH.%u: removing pushed stream", stream.streamId);
            [self removeStream:stream];
        } else {
            SPDY_DEBUG(@"PUSH.%u: leaving pushed stream with associated stream %u", stream.streamId, stream.associatedStream.streamId);
        }
    }
}

- (void)removeStream:(SPDYStream *)stream
{
    if (stream == nil) {
        return;
    }

    if (stream.local) {
        [_associatedStreamToNodeArrayMap removeObjectForKey:stream];
    } else {
        SPDYPushStreamNode *pushNode = [_streamToNodeMap objectForKey:stream];
        [_streamToNodeMap removeObjectForKey:stream];
        if (stream.request != nil) {
            [_requestToNodeMap removeObjectForKey:[stream.request keyForMemoryCache]];
        }

        // Remove the stream from the list of streams related to associated (original) stream.
        NSAssert(pushNode.associatedStream, @"push stream must have associated stream");
        NSMutableArray *associatedNodes = [_associatedStreamToNodeArrayMap objectForKey:pushNode.associatedStream];
        for (NSUInteger i = 0; i < associatedNodes.count; i++) {
            SPDYPushStreamNode *node = associatedNodes[i];
            if (node.stream == stream) {
                [associatedNodes removeObjectAtIndex:i];
                break;
            }
        }
    }
}

@end
