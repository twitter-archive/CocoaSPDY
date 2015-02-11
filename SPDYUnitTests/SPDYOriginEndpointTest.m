//
//  SPDYOriginEndpointTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier
//

#import <SenTestingKit/SenTestingKit.h>
#import "SPDYMockOriginEndpointManager.h"
#import "SPDYOriginEndpoint.h"
#import "SPDYProtocol.h"

@interface SPDYOriginEndpointTest : SenTestCase
@end

@implementation SPDYOriginEndpointTest

- (SPDYMockOriginEndpointManager *)_resolveEndpointsWithPacScript:(NSString *)pacScript
{
    NSError *error = nil;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    SPDYMockOriginEndpointManager *manager = [[SPDYMockOriginEndpointManager alloc] initWithOrigin:origin];

    // Trigger execution of the URL, but we'll mock it out with mock_autoConfigScript
    manager.mock_proxyList = @[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeAutoConfigurationURL,
            (__bridge NSString *)kCFProxyAutoConfigurationURLKey : @""
    }];
    manager.mock_autoConfigScript = pacScript;

    [manager resolveEndpointsWithCompletionHandler:^{
    }];

    return manager;
};

- (SPDYMockOriginEndpointManager *)_resolveEndpointsWithProxyList:(NSArray *)proxyList
{
    NSError *error = nil;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    SPDYMockOriginEndpointManager *manager = [[SPDYMockOriginEndpointManager alloc] initWithOrigin:origin];
    manager.mock_proxyList = proxyList;

    [manager resolveEndpointsWithCompletionHandler:^{
    }];

    return manager;
};

#pragma mark Tests

- (void)testOriginEndpointInit
{
    NSError *error = nil;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    SPDYOriginEndpoint *endpoint = [[SPDYOriginEndpoint alloc] initWithHost:@"1.2.3.4"
                                                                       port:8888
                                                                       user:@"user"
                                                                   password:@"pass"
                                                                       type:SPDYOriginEndpointTypeHttpsProxy
                                                                     origin:origin];
    NSLog(@"%@", endpoint); // ensure description doesn't crash
    STAssertEqualObjects(endpoint.host, @"1.2.3.4", nil);
    STAssertEquals(endpoint.port, (in_port_t)8888, nil);
    STAssertEqualObjects(endpoint.user, @"user", nil);
    STAssertEqualObjects(endpoint.password, @"pass", nil);
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeHttpsProxy, nil);
    STAssertEqualObjects(endpoint.origin, origin, nil);
}

- (void)testOriginManagerInit
{
    NSError *error = nil;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    STAssertNil(error, nil);

    SPDYOriginEndpointManager *manager = [[SPDYOriginEndpointManager alloc] initWithOrigin:origin];
    STAssertEqualObjects(manager.origin, origin, nil);
    STAssertEquals(manager.remaining, (NSUInteger)0, nil);
    STAssertNil(manager.endpoint, nil);
    STAssertNil([manager moveToNextEndpoint], nil);

    STAssertEquals(manager.remaining, (NSUInteger)0, nil);
    STAssertNil(manager.endpoint, nil);
    STAssertNil([manager moveToNextEndpoint], nil);
}

- (void)testResolveWithNoProxyConfig
{
    NSError *error = nil;
    __block BOOL gotCallback = NO;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    SPDYMockOriginEndpointManager *manager = [[SPDYMockOriginEndpointManager alloc] initWithOrigin:origin];

    [manager resolveEndpointsWithCompletionHandler:^{
        gotCallback = YES;
        STAssertEquals(manager.remaining, (NSUInteger)1, nil);
    }];

    STAssertTrue(gotCallback, nil);
    STAssertEquals(manager.remaining, (NSUInteger)1, nil);

    SPDYOriginEndpoint *endpoint = [manager moveToNextEndpoint];
    STAssertNotNil(endpoint, nil);
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeDirect, nil);
}

- (void)testResolveWithDirectProxyConfig
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithProxyList:@[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeNone,
    }]];

    STAssertEquals(manager.remaining, (NSUInteger)1, nil);

    SPDYOriginEndpoint *endpoint = [manager moveToNextEndpoint];
    STAssertNotNil(endpoint, nil);
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeDirect, nil);
    STAssertEqualObjects(endpoint.host, @"mytesthost.com", nil);
    STAssertEquals(endpoint.port, (in_port_t)443, nil);
    STAssertEqualObjects(endpoint.origin.host, @"mytesthost.com", nil);
    STAssertNil(endpoint.user, nil);
    STAssertNil(endpoint.password, nil);
}

- (void)testResolveWithHttpsProxyConfig
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithProxyList:@[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeHTTPS,
            (__bridge NSString *)kCFProxyHostNameKey : @"1.2.3.4",
            (__bridge NSString *)kCFProxyPortNumberKey : @"8888"
    }]];

    // Also adds direct at end
    STAssertEquals(manager.remaining, (NSUInteger)2, nil);

    SPDYOriginEndpoint *endpoint = [manager moveToNextEndpoint];
    STAssertNotNil(endpoint, nil);
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeHttpsProxy, nil);
    STAssertEqualObjects(endpoint.host, @"1.2.3.4", nil);
    STAssertEquals(endpoint.port, (in_port_t)8888, nil);
    STAssertEqualObjects(endpoint.origin.host, @"mytesthost.com", nil);
    STAssertNil(endpoint.user, @"actual: %@", nil);
    STAssertNil(endpoint.password, @"actual: %@", nil);

    endpoint = [manager moveToNextEndpoint];
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeDirect, nil);
    STAssertEqualObjects(endpoint.host, @"mytesthost.com", nil);
    STAssertEquals(endpoint.port, (in_port_t)443, nil);
}

- (void)testResolveWithInvalidHttpsProxyConfigDoesReturnDirect
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithProxyList:@[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeHTTPS,
            (__bridge NSString *)kCFProxyHostNameKey : @"",
            (__bridge NSString *)kCFProxyPortNumberKey : @"8888"
    }]];

    STAssertEquals(manager.remaining, (NSUInteger)1, nil);

    SPDYOriginEndpoint *endpoint = [manager moveToNextEndpoint];
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeDirect, nil);
    STAssertEqualObjects(endpoint.host, @"mytesthost.com", nil);
    STAssertEquals(endpoint.port, (in_port_t)443, nil);
}

- (void)testResolveWithEmptyAutoConfigURLShouldReturnDirect
{
    NSError *error = nil;
    __block BOOL gotCallback = NO;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    SPDYMockOriginEndpointManager *manager = [[SPDYMockOriginEndpointManager alloc] initWithOrigin:origin];

    // This URL will clearly result in an error, but will go through the Apple API to execute it.
    manager.mock_proxyList = @[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeAutoConfigurationURL,
            (__bridge NSString *)kCFProxyAutoConfigurationURLKey : @""
    }];

    [manager resolveEndpointsWithCompletionHandler:^{
        gotCallback = YES;
        CFRunLoopStop(CFRunLoopGetCurrent());
    }];

    // The callback will happen asynchronously on the current runloop.
    CFRunLoopRun();

    STAssertTrue(gotCallback, nil);
    STAssertEquals(manager.remaining, (NSUInteger)1, nil);

    SPDYOriginEndpoint *endpoint = [manager moveToNextEndpoint];
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeDirect, nil);
}

- (void)testResolveWithHttpsAndDirectProxyConfigShouldReturnBoth
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithProxyList:@[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeHTTPS,
            (__bridge NSString *)kCFProxyHostNameKey : @"1.2.3.4",
            (__bridge NSString *)kCFProxyPortNumberKey : @"8888"
    }, @{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeNone,
    }]];

    // Note: currently only support a single proxy.
    STAssertEquals(manager.remaining, (NSUInteger)2, nil);

    // The first config in the array gets used, so verify that.
    SPDYOriginEndpoint *endpoint = [manager moveToNextEndpoint];
    STAssertEquals(endpoint, manager.endpoint, nil);
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeHttpsProxy, nil);

    // Valid once we support multiple proxies
    endpoint = [manager moveToNextEndpoint];
    STAssertEquals(manager.remaining, (NSUInteger)0, nil);
    STAssertEquals(endpoint, manager.endpoint, nil);
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeDirect, nil);
}

- (void)testResolvePacFileWithProxyAndDirectDoesReturnBoth
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithPacScript:
            @"function FindProxyForURL(url, host) { return \"PROXY 1.2.3.4:8888; DIRECT\"; }"];

    STAssertEquals(manager.remaining, (NSUInteger)2, nil);

    [manager moveToNextEndpoint];
    STAssertEquals(manager.endpoint.type, SPDYOriginEndpointTypeHttpsProxy, nil);
    STAssertEqualObjects(manager.endpoint.host, @"1.2.3.4", nil);
    STAssertEquals(manager.endpoint.port, (in_port_t)8888, nil);

    // Valid once we support multiple proxies
    [manager moveToNextEndpoint];
    STAssertEquals(manager.endpoint.type, SPDYOriginEndpointTypeDirect, nil);
    STAssertEqualObjects(manager.endpoint.host, @"mytesthost.com", nil);
    STAssertEquals(manager.endpoint.port, (in_port_t)443, nil);
}

- (void)testResolvePacFileWithMultiProxyDoesReturnAll
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithPacScript:
            @"function FindProxyForURL(url, host) { return \"PROXY 1.2.3.4:8888; PROXY 1.2.3.5:8889\"; }"];

    STAssertEquals(manager.remaining, (NSUInteger)3, nil);

    [manager moveToNextEndpoint];
    STAssertEquals(manager.endpoint.type, SPDYOriginEndpointTypeHttpsProxy, nil);
    STAssertEqualObjects(manager.endpoint.host, @"1.2.3.4", nil);
    STAssertEquals(manager.endpoint.port, (in_port_t)8888, nil);

    [manager moveToNextEndpoint];
    STAssertEquals(manager.endpoint.type, SPDYOriginEndpointTypeHttpsProxy, nil);
    STAssertEqualObjects(manager.endpoint.host, @"1.2.3.5", nil);
    STAssertEquals(manager.endpoint.port, (in_port_t)8889, nil);

    // Valid once we support multiple proxies
    [manager moveToNextEndpoint];
    STAssertEquals(manager.endpoint.type, SPDYOriginEndpointTypeDirect, nil);
    STAssertEqualObjects(manager.endpoint.host, @"mytesthost.com", nil);
    STAssertEquals(manager.endpoint.port, (in_port_t)443, nil);
}

- (void)testResolvePacFileWithTypoDoesReturnDirect
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithPacScript:
            @"function FindProxyForURL(url, host) { return \"PROOXY 1.2.3.4:8888\"; }"];

    STAssertEquals(manager.remaining, (NSUInteger)1, nil);
    [manager moveToNextEndpoint];
    STAssertEquals(manager.endpoint.type, SPDYOriginEndpointTypeDirect, nil);
}

- (void)testResolvePacFileWithNoHostDoesReturnDirect
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithPacScript:
            @"function FindProxyForURL(url, host) { return \"PROXY :8888\"; }"];

    STAssertEquals(manager.remaining, (NSUInteger)1, nil);
    [manager moveToNextEndpoint];
    STAssertEquals(manager.endpoint.type, SPDYOriginEndpointTypeDirect, nil);
}

- (void)testResolvePacFileReturnsNothingDoesReturnDirect
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithPacScript:
            @"function FindProxyForURL(url, host) { }"];

    STAssertEquals(manager.remaining, (NSUInteger)1, nil);
    [manager moveToNextEndpoint];
    STAssertEquals(manager.endpoint.type, SPDYOriginEndpointTypeDirect, nil);
}

- (void)testResolvePacFileEmptyDoesReturnDirect
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithPacScript:
            @""];

    STAssertEquals(manager.remaining, (NSUInteger)1, nil);
    [manager moveToNextEndpoint];
    STAssertEquals(manager.endpoint.type, SPDYOriginEndpointTypeDirect, nil);
}

- (void)testResolvePacFileWithSOCKSDoesReturnDirect
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithPacScript:
            @"function FindProxyForURL(url, host) { return \"SOCKS 1.2.3.4:8888\"; }"];

    STAssertEquals(manager.remaining, (NSUInteger)1, nil);
    [manager moveToNextEndpoint];
    STAssertEquals(manager.endpoint.type, SPDYOriginEndpointTypeDirect, nil);
}

- (void)testResolveWithPacScriptIsNotSupported
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithProxyList:@[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeAutoConfigurationJavaScript
    }]];

    STAssertEquals(manager.remaining, (NSUInteger)1, nil);

    SPDYOriginEndpoint *endpoint = [manager moveToNextEndpoint];
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeDirect, nil);
}

- (void)testResolveWithSOCKSIsNotSupported
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithProxyList:@[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeSOCKS
    }]];

    STAssertEquals(manager.remaining, (NSUInteger)1, nil);

    SPDYOriginEndpoint *endpoint = [manager moveToNextEndpoint];
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeDirect, nil);
}

- (void)testResolveWithHttpsProxyConfigWhenDisabledReturnsDirect
{
    SPDYConfiguration *configuration = [SPDYConfiguration defaultConfiguration];
    configuration.enableProxy = NO;
    [SPDYProtocol setConfiguration:configuration];

    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithProxyList:@[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeHTTPS,
            (__bridge NSString *)kCFProxyHostNameKey : @"1.2.3.4",
            (__bridge NSString *)kCFProxyPortNumberKey : @"8888"
    }]];
    STAssertEquals(manager.remaining, (NSUInteger)1, nil);

    SPDYOriginEndpoint *endpoint = [manager moveToNextEndpoint];
    STAssertNotNil(endpoint, nil);
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeDirect, nil);
    STAssertEqualObjects(endpoint.host, @"mytesthost.com", nil);
    STAssertEquals(endpoint.port, (in_port_t)443, nil);
    STAssertEqualObjects(endpoint.origin.host, @"mytesthost.com", nil);

    // Remember to reset global config!
    [SPDYProtocol setConfiguration:[SPDYConfiguration defaultConfiguration]];
}

- (void)testResolveWithConfigOverrides
{
    SPDYConfiguration *configuration = [SPDYConfiguration defaultConfiguration];
    configuration.proxyHost = @"proxyproxyproxy.com";
    configuration.proxyPort = 9999;
    [SPDYProtocol setConfiguration:configuration];

    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithProxyList:@[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeHTTPS,
            (__bridge NSString *)kCFProxyHostNameKey : @"1.2.3.4",
            (__bridge NSString *)kCFProxyPortNumberKey : @"8888"
    }]];

    SPDYOriginEndpoint *endpoint = [manager moveToNextEndpoint];
    STAssertNotNil(endpoint, nil);
    STAssertEquals(endpoint.type, SPDYOriginEndpointTypeHttpsProxy, nil);
    STAssertEqualObjects(endpoint.host, @"proxyproxyproxy.com", nil);
    STAssertEquals(endpoint.port, (in_port_t)9999, nil);
    STAssertEqualObjects(endpoint.origin.host, @"mytesthost.com", nil);

    // Remember to reset global config!
    [SPDYProtocol setConfiguration:[SPDYConfiguration defaultConfiguration]];
}

@end
