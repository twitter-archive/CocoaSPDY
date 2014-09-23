//
//  SPDYOriginEndpoint.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier
//

#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "This file requires ARC support."
#endif

#import "SPDYOrigin.h"
#import "SPDYOriginEndpoint.h"
#import "SPDYCommonLogger.h"

@implementation SPDYOriginEndpoint

- (id)initWithHost:(NSString *)host
              port:(in_port_t)port
              user:(NSString *)user
          password:(NSString *)password
              type:(SPDYOriginEndpointType)type
            origin:(SPDYOrigin *)origin
{
    self = [super init];
    if (self) {
        _host = host;
        _port = port;
        _user = user;
        _password = password;
        _type = type;
        _origin = origin;
    }
    return self;
}

- (NSString *)description
{
    if (_type == SPDYOriginEndpointTypeDirect) {
        return [NSString stringWithFormat:@"<SPDYOriginEndpoint: %@:%d origin:%@>",
                                          _host, _port,
                                          _origin];
    } else {
        return [NSString stringWithFormat:@"<SPDYOriginEndpoint: %@:%d (%@ proxy%@) origin:%@>",
                                          _host, _port,
                                          _type == SPDYOriginEndpointTypeHttpsProxy ? @"https" : @"unknown",
                                          _user ? @" with credentials" : @"",
                                          _origin];
    }
}
@end

@interface SPDYOriginEndpointManager ()
@end

@implementation SPDYOriginEndpointManager
{
    NSMutableArray *_endpointList;
    NSInteger _endpointIndex;
    CFRunLoopSourceRef _autoConfigRunLoopSource;
    __strong void (^_resolveCallback)();
}

- (id)initWithOrigin:(SPDYOrigin *)origin
{
    self = [super init];
    if (self) {
        _origin = origin;
        _endpointList = [[NSMutableArray alloc] initWithCapacity:1];
        _endpointIndex = -1;
        _autoConfigRunLoopSource = nil;
        _resolveCallback = nil;
    }
    return self;
}

- (NSUInteger)getRemaining
{
    return (_endpointIndex >= _endpointList.count) ? 0 : (_endpointList.count - _endpointIndex - 1);
}

- (void)resolveEndpointsAndThen:(void (^)())completionHandler
{
    _resolveCallback = completionHandler;

    NSArray *originalProxyList = [self _proxyGetListFromSettings:[self _proxyGetSystemSettings]];
    [self _proxyAddSupportedFrom:originalProxyList executeAutoConfig:YES];

    // No operations pending, go ahead and complete
    if (_autoConfigRunLoopSource == nil) {
        if (_resolveCallback) {
            _resolveCallback();
            _resolveCallback = nil;
        }
    }
}

- (SPDYOriginEndpoint *)getCurrentEndpoint
{
    if (_endpointIndex >= 0 && _endpointIndex < _endpointList.count) {
        return _endpointList[_endpointIndex];
    } else {
        return nil;
    }
}

- (BOOL)moveToNextEndpoint
{
    if (_endpointIndex < (NSInteger)_endpointList.count) {
        _endpointIndex++;
    }

    return _endpointIndex < _endpointList.count;
}

- (NSURL *)_getOriginUrlForProxy
{
    NSString *originUrlString = [NSString stringWithFormat:@"%@://%@:%u", _origin.scheme, _origin.host, _origin.port];
    return [NSURL URLWithString:originUrlString];
}

- (void)_handleExecuteCallback:(NSArray *)proxies error:(NSError *)error
{
    if (error) {
        SPDY_ERROR(@"Error executing auto-config proxy URL: %@", error);
    } else if (proxies) {
        [self _proxyAddSupportedFrom:proxies executeAutoConfig:NO];
    }

    // Only allow 1 outstanding operation, so go ahead and complete
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), _autoConfigRunLoopSource, kCFRunLoopDefaultMode);
    CFRelease(_autoConfigRunLoopSource);
    _autoConfigRunLoopSource = nil;

    if (_resolveCallback) {
        _resolveCallback();
        _resolveCallback = nil;
    }
}

void ResultCallback(void* client, CFArrayRef proxies, CFErrorRef error)
{
    SPDYOriginEndpointManager *manager = (__bridge SPDYOriginEndpointManager *)client;

    NSError *nserror = nil;
    NSArray *nsproxies = nil;
    if (error != NULL) {
        nserror = (NSError *)CFRetain(error);
    } else {
        nsproxies = (NSArray *)CFRetain(proxies);
    }

    [manager _handleExecuteCallback:nsproxies error:nserror];
}

- (NSDictionary *)_proxyGetSystemSettings
{
    return (NSDictionary *)CFBridgingRelease(CFNetworkCopySystemProxySettings());
}

- (NSArray *)_proxyGetListFromSettings:(NSDictionary *)systemProxySettings
{
    if (systemProxySettings == nil) {
        return nil;
    }

    NSURL *originUrl = [self _getOriginUrlForProxy];
    return (NSArray *) CFBridgingRelease(CFNetworkCopyProxiesForURL(
            (__bridge CFURLRef)originUrl,
            (__bridge CFDictionaryRef)systemProxySettings));
}

- (void)_proxyAddSupportedFrom:(NSArray *)proxyList executeAutoConfig:(BOOL)executeAutoConfig
{
    for (NSDictionary *proxyDict in proxyList) {
        NSString *proxyType = [proxyDict valueForKey:(__bridge NSString *)kCFProxyTypeKey];
        NSString *host = [proxyDict valueForKey:(__bridge NSString *)kCFProxyHostNameKey];
        int port = [[proxyDict valueForKey:(__bridge NSString *)kCFProxyPortNumberKey] intValue];

        // Note: these are possibly never populated. Maybe have to look them up in the keychain.
        // See comment at http://src.chromium.org/svn/trunk/src/net/proxy/proxy_resolver_mac.cc.
        NSString *user = [proxyDict valueForKey:(__bridge NSString *)kCFProxyUsernameKey];
        NSString *pass = [proxyDict valueForKey:(__bridge NSString *)kCFProxyPasswordKey];

        // We only support HTTPS proxies, since SPDY requires the use of TLS. An HTTP proxy
        // does not use the CONNECT message, so is unable to speak anything but plaintext HTTP.
        if ([proxyType isEqualToString:(__bridge NSString *)kCFProxyTypeHTTPS]) {
            SPDYOriginEndpoint *endpoint;
            SPDYOriginEndpointType type = SPDYOriginEndpointTypeHttpsProxy;
            endpoint = [[SPDYOriginEndpoint alloc] initWithHost:host
                                                           port:port
                                                           user:user
                                                       password:pass
                                                           type:type
                                                         origin:_origin];
            [_endpointList addObject:endpoint];
            SPDY_INFO(@"Proxy: added endpoint %@", endpoint);
        } else if ([proxyType isEqualToString:(__bridge NSString *)kCFProxyTypeNone]) {
            [_endpointList addObject:[[SPDYOriginEndpoint alloc] initWithHost:_origin.host
                                                                        port:_origin.port
                                                                        user:nil
                                                                    password:nil
                                                                        type:SPDYOriginEndpointTypeDirect
                                                                      origin:_origin]];
            SPDY_INFO(@"Proxy: added direct endpoint %@", _endpointList.lastObject);
        } else if ([proxyType isEqualToString:(__bridge NSString *)kCFProxyTypeAutoConfigurationURL]) {
            NSURL *pacScriptUrl = [proxyDict valueForKey:(__bridge NSString *) kCFProxyAutoConfigurationURLKey];
            NSURL *originUrl = [self _getOriginUrlForProxy];

            // Work around <rdar://problem/5530166>. This dummy call to
            // CFNetworkCopyProxiesForURL initializes some state within CFNetwork that is
            // required by CFNetworkExecuteProxyAutoConfigurationURL.
            CFArrayRef dummy_result = CFNetworkCopyProxiesForURL(
                    (__bridge CFURLRef)originUrl,
                    NULL);
            if (dummy_result)
                CFRelease(dummy_result);

            // CFNetworkExecuteProxyAutoConfigurationURL returns a runloop source we need to release.
            // We'll do that after the callback.
            CFStreamClientContext context = {0, (__bridge void *) self, nil, nil, nil};
            _autoConfigRunLoopSource = CFNetworkExecuteProxyAutoConfigurationURL(
                    (__bridge CFURLRef) pacScriptUrl,
                    (__bridge CFURLRef) originUrl,
                    ResultCallback,
                    &context);
            CFRunLoopAddSource(CFRunLoopGetCurrent(), _autoConfigRunLoopSource, kCFRunLoopDefaultMode);
            SPDY_INFO(@"Proxy: executing auto-config url: %@", pacScriptUrl);
        } else {
            SPDY_INFO(@"Proxy: ignoring unsupported endpoint %@:%d (%@)", host, port, proxyType);
            continue;
        }

        // Currently only support 1 endpoint, so we're done here. This simplifies keeping
        // things in order.
        break;
    }
}

@end
