//
//  SPDYSocket.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Substantially based on the CocoaAsyncSocket library, originally
//  created by Dustin Voss, and currently maintained at
//  https://github.com/robbiehanson/CocoaAsyncSocket
//

#import <Foundation/Foundation.h>
#import "SPDYError.h"

@class SPDYSocket;
@class SPDYSocketReadOp;
@class SPDYSocketWriteOp;

extern NSString *const SPDYSocketException;

#pragma mark SPDYSocketDelegate

@protocol SPDYSocketDelegate <NSObject>
@optional

/**
  Called when a socket encounters an error and will be closing.

  You may call [SPDYSocket unreadData] during this callback to retrieve
  remaining data off the socket. This delegate method may be called before
  socket:didAcceptNewSocket: or onSocket:didConnectToHost:.
*/
- (void)socket:(SPDYSocket *)socket willDisconnectWithError:(NSError *)error;

/**
  Called when a socket disconnects with or without error.

  The SPDYSocket may be safely released during this callback. If you call
  [SPDYSocket disconnect], and the socket wasn't already disconnected, this
  delegate method will be called before the disconnect method returns.
*/
- (void)socketDidDisconnect:(SPDYSocket *)socket;

/**
  Called when a socket accepts a connection.

  Another SPDYSocket is spawned to handle it. The new socket will have
  the same delegate and will call socket:didConnectToHost:port:.
*/
- (void)socket:(SPDYSocket *)socket didAcceptNewSocket:(SPDYSocket *)newSocket;

/**
  Called when a new socket is spawned to handle a connection.

  This method should return the run loop on which the new socket and its
  delegate should operate. If omitted, [NSRunLoop currentRunLoop] is used.
*/
- (NSRunLoop *)socket:(SPDYSocket *)socket wantsRunLoopForNewSocket:(SPDYSocket *)newSocket;

/**
  Called when a socket is about to connect.

  If [SPDYSocket connectToHost:onPort:error:] was called, the delegate will be
  able to access and configure the CFReadStream and CFWriteStream as desired
  prior to connection.

  If [SPDYSocket connectToAddress:error:] was called, the delegate will be able
  to access and configure the CFSocket and CFSocketNativeHandle (BSD socket) as
  desired prior to connection. You will be able to access and configure the
  CFReadStream and CFWriteStream during socket:didConnectToHost:port:.

  @return YES to continue, NO to abort resulting in a SPDYSocketConnectCanceled
*/
- (bool)socketWillConnect:(SPDYSocket *)socket;

/**
  Called when a socket connects and is ready for reading and writing.

  @param host IP address of the connected host
*/
- (void)socket:(SPDYSocket *)socket didConnectToHost:(NSString *)host port:(in_port_t)port;

/**
  Called when a socket has completed reading the requested data into memory.
*/
- (void)socket:(SPDYSocket *)socket didReadData:(NSData *)data withTag:(long)tag;

/**
  Called when a socket has read in data, but has not yet completed the read.

  This would occur if using readToData: or readToLength: methods.
*/
- (void)socket:(SPDYSocket *)socket didReadPartialDataOfLength:(NSUInteger)partialLength tag:(long)tag;

/**
  Called when a socket has completed writing the requested data.
*/
- (void)socket:(SPDYSocket *)socket didWriteDataWithTag:(long)tag;

/**
  Called when a socket has written data, but has not yet completed the write.
*/
- (void)socket:(SPDYSocket *)socket didWritePartialDataOfLength:(NSUInteger)partialLength tag:(long)tag;

/**
  Called if a read operation has reached its timeout without completing.

  @param elapsed total elapsed time since the read began
  @param length  number of bytes that have been read so far
  @return        a positive value to optionally extend the read's timeout
*/
- (NSTimeInterval)socket:(SPDYSocket *)socket
  willTimeoutReadWithTag:(long)tag
                 elapsed:(NSTimeInterval)elapsed
               bytesDone:(NSUInteger)length;

/**
  Called if a write operation has reached its timeout without completing.

  @param elapsed total elapsed time since the write began
  @param length  number of bytes that have been write so far
  @return        a positive value to optionally extend the write's timeout
*/
- (NSTimeInterval)socket:(SPDYSocket *)socket
 willTimeoutWriteWithTag:(long)tag
                 elapsed:(NSTimeInterval)elapsed
               bytesDone:(NSUInteger)length;

/**
  Called when a socket has successfully completed SSL/TLS negotiation.

  If the delegate does not implement this method, use of the newly opened
  TLS channel will always proceed as if this method had returned YES.

  @param trust the X.509 trust object created to evaluate the TLS channel
  @return      YES to continue, NO to close the connection with the error
               SPDYSocketTLSVerificationFailed
*/
- (bool)socket:(SPDYSocket *)socket securedWithTrust:(SecTrustRef)trust;

@end

#pragma mark SPDYSocket

@interface SPDYSocket : NSObject
@property (nonatomic, weak) id<SPDYSocketDelegate> delegate;

- (id)initWithDelegate:(id<SPDYSocketDelegate>)delegate;
- (CFSocketRef)cfSocket;
- (CFReadStreamRef)cfReadStream;
- (CFWriteStreamRef)cfWriteStream;

/**
  Connects to the given host and port.
*/
- (bool)connectToHost:(NSString *)hostname onPort:(in_port_t)port error:(NSError **)pError;

/**
  Connects to the given host and port.

  @param timeout use a negative value for no connection timeout
**/
- (bool)connectToHost:(NSString *)hostname
               onPort:(in_port_t)port
          withTimeout:(NSTimeInterval)timeout
                error:(NSError **)pError;

/**
  Disconnects immediately; any pending reads or writes are dropped.
*/
- (void)disconnect;

/**
  Disconnects after all pending reads have completed.
*/
- (void)disconnectAfterReads;

/**
  Disconnects after all pending writes have completed.
*/
- (void)disconnectAfterWrites;

/**
  Disconnects after all pending reads and writes have completed.
*/
- (void)disconnectAfterReadsAndWrites;

/**
  @return YES when the socket streams are open and connected
*/
- (bool)connected;

/**
  @return the IP address of the host to which the socket is connected
*/
- (NSString *)connectedHost;

/**
  @return the port to which the socket is connected
*/
- (in_port_t)connectedPort;

/**
  @return YES if the socket is IPv4
*/
- (bool)isIPv4;

/**
  @return YES if the socket is IPv6
*/
- (bool)isIPv6;

/**
  Asynchronously read the first available bytes on the socket.

  When the read is complete the socket:didReadData:withTag: delegate method
  will be called.

  @param timeout use a negative value for no timeout
  @param tag     an arbitrary tag to associate with the delegate callback
*/
- (void)readDataWithTimeout:(NSTimeInterval)timeout tag:(long)tag;

/**
  Asynchronously read the first available bytes on the socket.

  When the read is complete the socket:didReadData:withTag: delegate method
  will be called, referencing new bytes written to the specified buffer.

  @param timeout use a negative value for no timeout
  @param buffer  the buffer to use for reading
  @param offset  the index to write to in the buffer
  @param tag     an arbitrary tag to associate with the delegate callback
*/

- (void)readDataWithTimeout:(NSTimeInterval)timeout
                     buffer:(NSMutableData *)buffer
               bufferOffset:(NSUInteger)offset
                        tag:(long)tag;

/**
  Asynchronously read the first available bytes on the socket.

  When the read is complete the socket:didReadData:withTag: delegate method
  will be called, referencing new bytes written to the specified buffer.

  @param timeout   use a negative value for no timeout
  @param buffer    the buffer to use for reading
  @param offset    the index to write to in the buffer
  @param maxLength the maximum number of bytes to read with this operation
  @param tag       an arbitrary tag to associate with the delegate callback
*/
- (void)readDataWithTimeout:(NSTimeInterval)timeout
                     buffer:(NSMutableData *)buffer
               bufferOffset:(NSUInteger)offset
                  maxLength:(NSUInteger)length
                        tag:(long)tag;

/**
  Asynchronously read the specified number of bytes off the socket.

  When the read is complete the socket:didReadData:withTag: delegate method
  will be called.

  @param length  the number of bytes to read before calling the delegate
  @param timeout use a negative value for no timeout
  @param tag     an arbitrary tag to associate with the delegate callback
*/
- (void)readDataToLength:(NSUInteger)length withTimeout:(NSTimeInterval)timeout tag:(long)tag;

/**
  Asynchronously read the specified number of bytes off the socket.

  When the read is complete the socket:didReadData:withTag: delegate method
  will be called, referencing new bytes written to the specified buffer.

  @param length  the number of bytes to read before calling the delegate
  @param timeout use a negative value for no timeout
  @param buffer  the buffer to use for reading
  @param offset  the index to write to in the buffer
  @param tag     an arbitrary tag to associate with the delegate callback
**/
- (void)readDataToLength:(NSUInteger)length
             withTimeout:(NSTimeInterval)timeout
                  buffer:(NSMutableData *)buffer
            bufferOffset:(NSUInteger)offset
                     tag:(long)tag;

/**
  Asynchronously writes data to the socket.

  When the write is complete the socket:didWriteDataWithTag: delegate method
  will be called.

  @param timeout use a negative value for no timeout
  @param tag     an arbitrary tag to associate with the delegate callback
*/
- (void)writeData:(NSData *)data withTimeout:(NSTimeInterval)timeout tag:(long)tag;

/**
  Secures the connection using TLS.

  This method may be called at any time, and the TLS handshake will occur after
  all pending reads and writes are finished.

  @param tlsSettings a dictionary of TLS settings to use for the connection

  Possible keys and values for TLS settings can be found in CFSocketStream.h
  Some possible keys are:
  - kCFStreamSSLLevel
  - kCFStreamSSLAllowsExpiredCertificates
  - kCFStreamSSLAllowsExpiredRoots
  - kCFStreamSSLAllowsAnyRoot
  - kCFStreamSSLValidatesCertificateChain
  - kCFStreamSSLPeerName
  - kCFStreamSSLCertificates
  - kCFStreamSSLIsServer

  If you pass nil or an empty dictionary, Apple default settings will be used.
*/
- (void)secureWithTLS:(NSDictionary *)tlsSettings;

/**
  Reschedule the SPDYSocket on a different runloop.
*/
- (bool)setRunLoop:(NSRunLoop *)runLoop;

/**
  Configures the runloop modes the SPDYSocket will operate on.

  The default set is limited to NSDefaultRunLoopMode.

  If you'd like your socket to continue operation during other modes, you may want to add modes such as
  NSModalPanelRunLoopMode or NSEventTrackingRunLoopMode. Or you may simply want to use NSRunLoopCommonModes.
*/
- (bool)setRunLoopModes:(NSArray *)runLoopModes;
- (bool)addRunLoopMode:(NSString *)runLoopMode;
- (bool)removeRunLoopMode:(NSString *)runLoopMode;

/**
  @return the current runloop modes the SPDYSocket is scheduled on
*/
- (NSArray *)runLoopModes;

/**
  Call during socket:willDisconnectWithError: to read any leftover data on the socket.

  @return any remaining data off the socket buffer
*/
- (NSData *)unreadData;

@end
