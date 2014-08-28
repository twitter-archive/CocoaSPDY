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
                                          _type == SPDYOriginEndpointTypeHttpProxy ? @"http" : @"https",
                                          _user ? @" with credentials" : @"",
                                          _origin];
    }
}
@end

@interface SPDYOriginEndpointManager ()
@end

@implementation SPDYOriginEndpointManager
{
    NSArray *_endpointList;
    NSInteger _endpointIndex;
}

- (id)initWithOrigin:(SPDYOrigin *)origin
{
    self = [super init];
    if (self) {
        _origin = origin;
        _endpointList = [self _getOriginEndpoints];
        _endpointIndex = -1;
    }
    return self;
}

- (SPDYOriginEndpoint *)getCurrentEndpoint
{
    if (_endpointIndex >= 0 && _endpointIndex < _endpointList.count) {
        return _endpointList[_endpointIndex];
    } else {
        return nil;
    }
}

- (bool)moveToNextEndpoint
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

- (NSArray *)_getOriginEndpoints
{
    NSArray *originalProxyList = [self _proxyGetListFromSettings:[self _proxyGetSystemSettings]];
    NSMutableArray *newProxyList = [[NSMutableArray alloc] init];
    NSMutableArray *endpointList = [[NSMutableArray alloc] initWithCapacity:originalProxyList.count];

    // Resolve any auto-config proxies to another list, but only do it one time. Don't want
    // to enter an infinite loop.
    for (NSDictionary *proxyDict in originalProxyList) {
        // @@@ temp
        for (NSString *key in proxyDict) {
            SPDY_DEBUG(@"Proxy: proxy config: %@ = %@", key, proxyDict[key]);
        }

        [self _proxyResolveAutoConfigProxies:proxyDict toProxyList:newProxyList];
    }

    // Add all supported proxy types for each list to our endpoint list
    [self _proxyAddSupportedFrom:originalProxyList toEndpointList:endpointList];
    [self _proxyAddSupportedFrom:newProxyList toEndpointList:endpointList];

    SPDY_DEBUG(@"Proxy: %lu proxies discovered", (unsigned long)endpointList.count);

    // Add the direct, no-proxy option last
    [endpointList addObject:[[SPDYOriginEndpoint alloc] initWithHost:_origin.host
                                                                port:_origin.port
                                                                user:nil
                                                            password:nil
                                                                type:SPDYOriginEndpointTypeDirect
                                                              origin:_origin]];
    return endpointList;
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

    // @@@ temp
    for (NSString *key in systemProxySettings) {
        SPDY_DEBUG(@"Proxy: system config: %@ = %@", key, systemProxySettings[key]);
    }

    NSURL *originUrl = [self _getOriginUrlForProxy];
    return (NSArray *) CFBridgingRelease(CFNetworkCopyProxiesForURL(
            (__bridge CFURLRef)originUrl,
            (__bridge CFDictionaryRef)systemProxySettings));
}

- (NSArray *)_proxyGetListFromScript:(NSString *)pacScript
{
    if (pacScript == nil) {
        return nil;
    }

    SPDY_DEBUG(@"Proxy: parsing script '%@'", pacScript);

    CFErrorRef error = nil;
    NSURL *originUrl = [self _getOriginUrlForProxy];
    CFArrayRef proxyList = CFNetworkCopyProxiesForAutoConfigurationScript(
            (__bridge CFStringRef)pacScript,
            (__bridge CFURLRef)originUrl,
            &error);

    if (error) {
        SPDY_WARNING(@"Proxy: error getting configuration from PAC file '%@': %@", pacScript, (__bridge NSError *)error);
        return nil;
    }

    return (NSArray *) CFBridgingRelease(proxyList);
}

- (NSString *)_getPacScriptFromUrl:(NSURL *)pacScriptUrl
{
    if (pacScriptUrl == nil) {
        return nil;
    }

    SPDY_DEBUG(@"Proxy: retrieving PAC file from %@", pacScriptUrl);

    NSError *error = nil;
    NSString *pacScript = [NSString stringWithContentsOfURL:pacScriptUrl
                                               usedEncoding:nil
                                                      error:&error];
    if (error) {
        SPDY_WARNING(@"Error retrieving proxy auto configuration from %@: %@", pacScriptUrl, error);
        return nil;
    }

    return pacScript;
}

- (void)_proxyResolveAutoConfigProxies:(NSDictionary *)proxyDict toProxyList:(NSMutableArray *)proxyList
{
    NSString *proxyType = [proxyDict valueForKey:(__bridge NSString *)kCFProxyTypeKey];
    if ([proxyType isEqualToString:(__bridge NSString *)kCFProxyTypeAutoConfigurationURL]) {
        // Proxy auto-configuration URL. Retrieve and process PAC file.

        NSURL *pacScriptUrl = [NSURL URLWithString:[proxyDict valueForKey:(__bridge NSString *)kCFProxyAutoConfigurationURLKey]];
        NSString *pacScript = [self _getPacScriptFromUrl:pacScriptUrl];
        NSArray *autoProxyList = [self _proxyGetListFromScript:pacScript];
        [proxyList addObjectsFromArray:autoProxyList];
    } else if ([proxyType isEqualToString:(__bridge NSString *)kCFProxyTypeAutoConfigurationJavaScript]) {
        // PAC file provided directly (really?). Process.
        NSString *pacScript = [proxyDict valueForKey:(__bridge NSString *)kCFProxyAutoConfigurationJavaScriptKey];
        NSArray *autoProxyList = [self _proxyGetListFromScript:pacScript];
        [proxyList addObjectsFromArray:autoProxyList];
    }
}

- (void)_proxyAddSupportedFrom:(NSArray *)proxyList toEndpointList:(NSMutableArray *)endpointList
{
    for (NSDictionary *proxyDict in proxyList) {
        NSString *proxyType = [proxyDict valueForKey:(__bridge NSString *)kCFProxyTypeKey];
        NSString *host = [proxyDict valueForKey:(__bridge NSString *)kCFProxyHostNameKey];
        int port = [[proxyDict valueForKey:(__bridge NSString *)kCFProxyPortNumberKey] intValue];

        // Note: these are possibly never populated. Maybe have to look them up in the keychain.
        // See comment at http://src.chromium.org/svn/trunk/src/net/proxy/proxy_resolver_mac.cc.
        NSString *user = [proxyDict valueForKey:(__bridge NSString *)kCFProxyUsernameKey];
        NSString *pass = [proxyDict valueForKey:(__bridge NSString *)kCFProxyPasswordKey];

        SPDY_DEBUG(@"Proxy: discovered endpoint %@:%d (%@)", host, port, proxyType);

        bool isHttpProxy = [proxyType isEqualToString:(__bridge NSString *)kCFProxyTypeHTTP];
        bool isHttpsProxy = [proxyType isEqualToString:(__bridge NSString *)kCFProxyTypeHTTPS];
        if (isHttpProxy || isHttpsProxy) {
            SPDYOriginEndpoint *endpoint;
            SPDYOriginEndpointType type = (isHttpProxy) ? SPDYOriginEndpointTypeHttpProxy : SPDYOriginEndpointTypeHttpsProxy;
            endpoint = [[SPDYOriginEndpoint alloc] initWithHost:host
                                                           port:port
                                                           user:user
                                                       password:pass
                                                           type:type
                                                         origin:_origin];
            [endpointList addObject:endpoint];
            SPDY_DEBUG(@"Proxy: added endpoint %@", endpoint);
        }
        else if ([proxyType isEqualToString:(__bridge NSString *)kCFProxyTypeNone]) {
            // This case will be handled later
        }
        else {
            SPDY_WARNING(@"Proxy: ignoring unsupported endpoint %@:%d (%@)", host, port, proxyType);
        }
    }
}

@end
