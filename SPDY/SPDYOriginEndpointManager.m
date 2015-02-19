//
//  SPDYOriginEndpointManager.m
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

#import "SPDYCommonLogger.h"
#import "SPDYError.h"
#import "SPDYOrigin.h"
#import "SPDYOriginEndpoint.h"
#import "SPDYOriginEndpointManager.h"
#import "SPDYProtocol.h"

@interface SPDYOriginEndpointManager ()
@end

@implementation SPDYOriginEndpointManager
{
    NSMutableArray *_endpointList;
    NSInteger _endpointIndex;
    CFRunLoopSourceRef _autoConfigRunLoopSource;
    NSMutableArray *_autoConfigRunLoopModes;
    void (^_resolveCallback)();
}

- (id)initWithOrigin:(SPDYOrigin *)origin
{
    self = [super init];
    if (self) {
        _origin = origin;
        _endpointList = [[NSMutableArray alloc] initWithCapacity:1];
        _endpointIndex = -1;
        _autoConfigRunLoopSource = nil;
        _autoConfigRunLoopModes = [NSMutableArray arrayWithCapacity:2];
        _resolveCallback = nil;
    }
    return self;
}

- (void)dealloc
{
    [self _removeRunLoopSource];
}

- (NSUInteger)remaining
{
    NSInteger count = _endpointList.count;
    return (_endpointIndex >= count) ? 0 : (NSUInteger)(count - _endpointIndex - 1);
}

- (SPDYOriginEndpoint *)endpoint
{
    if (_endpointIndex >= 0 && _endpointIndex < _endpointList.count) {
        return _endpointList[_endpointIndex];
    } else {
        return nil;
    }
}

- (void)setAuthRequired:(bool)authRequired
{
    _authRequired = authRequired;
    switch (_proxyStatus) {
        case SPDYProxyStatusManual:
            _proxyStatus = SPDYProxyStatusManualWithAuth;
            break;
        case SPDYProxyStatusAuto:
            _proxyStatus = SPDYProxyStatusAutoWithAuth;
            break;
        case SPDYProxyStatusConfig:
            _proxyStatus = SPDYProxyStatusConfigWithAuth;
            break;
        default:
            SPDY_WARNING(@"unexpected endpoint state, can't set auth required for SPDYProxyStatus %d", (int)_proxyStatus);
    }
}

- (void)resolveEndpointsWithCompletionHandler:(void (^)())completionHandler
{
    _resolveCallback = [completionHandler copy];

    SPDYConfiguration *configuration = [SPDYProtocol currentConfiguration];
    if (configuration.enableProxy) {
        if (configuration.proxyHost != nil && configuration.proxyPort > 0) {
            // Use app-supplied overrides
            SPDYOriginEndpoint *endpoint;
            endpoint = [[SPDYOriginEndpoint alloc] initWithHost:configuration.proxyHost
                                                           port:configuration.proxyPort
                                                           user:nil  // TODO
                                                       password:nil  // TODO
                                                           type:SPDYOriginEndpointTypeHttpsProxy
                                                         origin:_origin];
            [_endpointList addObject:endpoint];
            _proxyStatus = SPDYProxyStatusConfig;
        } else {
            // Use system configuration
            NSArray *originalProxyList = [self _proxyGetListFromSettings:[self _proxyGetSystemSettings]];
            [self _proxyAddSupportedFrom:originalProxyList executeAutoConfig:YES];
        }
    }

    // No operations pending, go ahead and complete
    if (_autoConfigRunLoopSource == nil) {
        [self _finalizeResolveEndpoints];
    }
}

- (SPDYOriginEndpoint *)moveToNextEndpoint
{
    if (_endpointIndex < (NSInteger)_endpointList.count) {
        _endpointIndex++;
    }

    return self.endpoint;
}

- (void)_addFallback
{
    // We'll never add 2 direct endpoints to the list
    for (SPDYOriginEndpoint *endpoint in _endpointList) {
        if (endpoint.type == SPDYOriginEndpointTypeDirect) {
            return;
        }
    }

    SPDYOriginEndpoint *endpoint;
    endpoint = [[SPDYOriginEndpoint alloc] initWithHost:_origin.host
                                                   port:_origin.port
                                                   user:nil
                                               password:nil
                                                   type:SPDYOriginEndpointTypeDirect
                                                 origin:_origin];
    [_endpointList addObject:endpoint];
}

- (void)_addRunLoopSource
{
    [_autoConfigRunLoopModes removeAllObjects];
    [_autoConfigRunLoopModes addObject:(__bridge NSString *)kCFRunLoopDefaultMode];
    CFStringRef currentMode = CFRunLoopCopyCurrentMode(CFRunLoopGetCurrent());
    if (currentMode != NULL) {
        if (CFStringCompare(currentMode, kCFRunLoopDefaultMode, 0) != kCFCompareEqualTo) {
            [_autoConfigRunLoopModes addObject:(__bridge NSString *)currentMode];
        }
        CFRelease(currentMode);
    }
    for (NSString *mode in _autoConfigRunLoopModes) {
        CFRunLoopAddSource(CFRunLoopGetCurrent(), _autoConfigRunLoopSource, (__bridge CFStringRef)mode);
    }
}

- (void)_removeRunLoopSource
{
    if (_autoConfigRunLoopSource != NULL) {
        for (NSString *mode in _autoConfigRunLoopModes) {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), _autoConfigRunLoopSource, (__bridge CFStringRef)mode);
        }
        CFRelease(_autoConfigRunLoopSource);
        _autoConfigRunLoopSource = NULL;
        [_autoConfigRunLoopModes removeAllObjects];
    }
}

- (NSURL *)_getOriginUrlForProxy
{
    NSString *originUrlString = [NSString stringWithFormat:@"%@://%@:%u", _origin.scheme, _origin.host, _origin.port];
    return [NSURL URLWithString:originUrlString];
}

- (void)_finalizeResolveEndpoints
{
    // Nothing added (or not enabled) means we should try a direct connection.
    // We'll also add one as a last resort every time, since currently the socket does
    // not support multiple proxy attempts, except in the case of a 407 response.
    [self _addFallback];

    if (_resolveCallback) {
        dispatch_block_t block = _resolveCallback;
        _resolveCallback = nil;
        block();
    }
}

- (void)_handleExecuteCallback:(NSArray *)proxies error:(NSError *)error
{
    if (error) {
        SPDY_ERROR(@"Error executing auto-config proxy URL: %@", error);
        _proxyStatus = SPDYProxyStatusAutoInvalid;
    } else if (proxies) {
        [self _proxyAddSupportedFrom:proxies executeAutoConfig:NO];
    }

    // Only allow 1 outstanding operation, so go ahead and complete
    [self _removeRunLoopSource];

    [self _finalizeResolveEndpoints];
}

static void ResultCallback(void* client, CFArrayRef proxies, CFErrorRef error)
{
    SPDYOriginEndpointManager *manager = CFBridgingRelease(client);

    // Regarding 'proxies' and presumably 'error' parameters, Apple says;
    //   If you want to keep this list, you must retain it when your callback receives it.
    // We don't need to keep them beyond the life of this call, and even if we did we'll
    // let ARC do its thing inside _handleExecuteCallback.

    NSError *bridgedError = nil;
    NSArray *bridgedProxies = nil;
    if (error != NULL) {
        bridgedError = (__bridge NSError *)error;
    } else {
        bridgedProxies = (__bridge NSArray *)proxies;
    }

    [manager _handleExecuteCallback:bridgedProxies error:bridgedError];
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
    return (NSArray *) CFBridgingRelease(CFNetworkCopyProxiesForURL((__bridge CFURLRef)originUrl,
                                                                    (__bridge CFDictionaryRef)systemProxySettings));
}

- (void)_proxyAddSupportedFrom:(NSArray *)proxyList executeAutoConfig:(BOOL)executeAutoConfig
{
    for (NSDictionary *proxyDict in proxyList) {
        NSString *proxyType = proxyDict[(__bridge NSString *)kCFProxyTypeKey];
        NSString *host = proxyDict[(__bridge NSString *)kCFProxyHostNameKey];
        int port = [proxyDict[(__bridge NSString *)kCFProxyPortNumberKey] intValue];

        // Note: these are possibly never populated. Maybe have to look them up in the keychain.
        // See comment at http://src.chromium.org/svn/trunk/src/net/proxy/proxy_resolver_mac.cc.
        // Even if they are present, we don't use them.
        NSString *user = proxyDict[(__bridge NSString *)kCFProxyUsernameKey];
        NSString *pass = proxyDict[(__bridge NSString *)kCFProxyPasswordKey];

        // The difference between an HTTP proxy and a HTTPS proxy, as returned by
        // CFNetworkCopyProxiesForURL, is only the URL's scheme. The UI supports a single "proxy"
        // setting, but the returned type is dependent on "http" or "https" scheme in the URL.
        // So we'll try both, although we have to use a CONNECT message in order to upgrade to
        // a tunnel (for the binary SPDY frames). Some simple HTTP proxies may not support that.
        if (([proxyType isEqualToString:(__bridge NSString *)kCFProxyTypeHTTPS] || [proxyType isEqualToString:(__bridge NSString *)kCFProxyTypeHTTP])
                && host.length > 0) {
            SPDYOriginEndpoint *endpoint;
            endpoint = [[SPDYOriginEndpoint alloc] initWithHost:host
                                                           port:port
                                                           user:user
                                                       password:pass
                                                           type:SPDYOriginEndpointTypeHttpsProxy
                                                         origin:_origin];
            [_endpointList addObject:endpoint];
            SPDY_INFO(@"Proxy: added endpoint %@", endpoint);
            if (_proxyStatus == SPDYProxyStatusNone) {
                _proxyStatus = SPDYProxyStatusManual;
            }
        } else if ([proxyType isEqualToString:(__bridge NSString *)kCFProxyTypeNone]) {
            SPDYOriginEndpoint *endpoint;
            endpoint = [[SPDYOriginEndpoint alloc] initWithHost:_origin.host
                                                           port:_origin.port
                                                           user:nil
                                                       password:nil
                                                           type:SPDYOriginEndpointTypeDirect
                                                         origin:_origin];
            [_endpointList addObject:endpoint];
            SPDY_INFO(@"Proxy: added direct endpoint %@", _endpointList.lastObject);
        } else if ([proxyType isEqualToString:(__bridge NSString *)kCFProxyTypeAutoConfigurationURL] && executeAutoConfig) {
            NSURL *pacScriptUrl = proxyDict[(__bridge NSString *) kCFProxyAutoConfigurationURLKey];
            SPDY_INFO(@"Proxy: executing auto-config url: %@", pacScriptUrl);
            _proxyStatus = SPDYProxyStatusAuto;
            [self _proxyExecuteAutoConfigURL:pacScriptUrl];
        } else {
            SPDY_INFO(@"Proxy: ignoring unsupported endpoint %@:%d (%@)", host, port, proxyType);
        }
    }

    if (_endpointList.count == 0) {
        if (_proxyStatus == SPDYProxyStatusAuto) {
            _proxyStatus = SPDYProxyStatusAutoInvalid;
        } else {
            _proxyStatus = SPDYProxyStatusManualInvalid;
        }
    }
}

- (void)_proxyExecuteAutoConfigURL:(NSURL *)pacScriptUrl
{
    NSURL *originUrl = [self _getOriginUrlForProxy];

    // From http://src.chromium.org/svn/trunk/src/net/proxy/proxy_resolver_mac.cc
    // Work around <rdar://problem/5530166>. This dummy call to
    // CFNetworkCopyProxiesForURL initializes some state within CFNetwork that is
    // required by CFNetworkExecuteProxyAutoConfigurationURL.
    CFArrayRef dummy_result = CFNetworkCopyProxiesForURL(
                                                         (__bridge CFURLRef)originUrl,
                                                         NULL);
    if (dummy_result) {
        CFRelease(dummy_result);
    }

    // CFNetworkExecuteProxyAutoConfigurationURL returns a runloop source we need to release.
    // We'll do that after the callback.
    CFStreamClientContext context = {0, (void *)CFBridgingRetain(self), nil, nil, nil};
    _autoConfigRunLoopSource = CFNetworkExecuteProxyAutoConfigurationURL(
                                                                         (__bridge CFURLRef) pacScriptUrl,
                                                                         (__bridge CFURLRef) originUrl,
                                                                         ResultCallback,
                                                                         &context);

    [self _addRunLoopSource];
}

@end
