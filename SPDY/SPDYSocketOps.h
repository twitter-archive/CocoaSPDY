//
//  SPDYSocketOps.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier.
//

@class SPDYOrigin;

#define PROXY_READ_SIZE      8192  // Max size of proxy response
#define READ_CHUNK_SIZE      65536 // Limit on size of each read pass

/**
  Encompasses the instructions for any given read operation.

  [SPDYSocketDelegate socket:didReadData:withTag:] is called when a read
  operation completes. If _fixedLength is set, the delegate will not be called
  until exactly that number of bytes is read. If _maxLength is set, the
  delegate will be called as soon as 0 < bytes <= maxLength are read. If
  neither is set, the delegate will be called as soon as any bytes are read.
*/
@interface SPDYSocketReadOp : NSObject {
@public
    NSMutableData *_buffer;
    NSUInteger _bytesRead;
    NSUInteger _startOffset;
    NSUInteger _maxLength;
    NSUInteger _fixedLength;
    NSUInteger _originalBufferLength;
    NSTimeInterval _timeout;
    bool _bufferOwner;
    long _tag;
}

- (id)initWithData:(NSMutableData *)data
       startOffset:(NSUInteger)startOffset
         maxLength:(NSUInteger)maxLength
           timeout:(NSTimeInterval)timeout
       fixedLength:(NSUInteger)fixedLength
               tag:(long)tag;

- (NSUInteger)safeReadLength;
@end


/**
  Encompasses the instructions for connecting to a proxy
*/
@interface SPDYSocketProxyReadOp : SPDYSocketReadOp {
@public
    NSString *_version;
    NSInteger _statusCode;
    NSString *_remaining;
    NSUInteger _bytesParsed;
}

- (id)initWithTimeout:(NSTimeInterval)timeout;
- (bool)tryParseResponse;
- (bool)success;
- (bool)needsAuth;

@end


/**
  Encompasses the instructions for any given write operation.
*/
@interface SPDYSocketWriteOp : NSObject {
@public
    NSData *_buffer;
    NSUInteger _bytesWritten;
    NSTimeInterval _timeout;
    long _tag;
}

- (id)initWithData:(NSData *)data timeout:(NSTimeInterval)timeout tag:(long)tag;

@end


/**
  Encompasses the instructions for connecting to a proxy
*/
@interface SPDYSocketProxyWriteOp : SPDYSocketWriteOp

- (id)initWithOrigin:(SPDYOrigin *)origin timeout:(NSTimeInterval)timeout;

@end


/**
  Encompasses instructions for TLS.
*/
@interface SPDYSocketTLSOp : NSObject {
@public
    NSDictionary *_tlsSettings;
}

- (id)initWithTLSSettings:(NSDictionary *)settings;

@end
