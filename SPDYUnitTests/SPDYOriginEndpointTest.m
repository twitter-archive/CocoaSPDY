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

#import <XCTest/XCTest.h>
#import "SPDYError.h"
#import "SPDYMockOriginEndpointManager.h"
#import "SPDYOriginEndpoint.h"
#import "SPDYProtocol.h"

@interface SPDYOriginEndpointTest : XCTestCase
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
            (__bridge NSString *)kCFProxyAutoConfigurationURLKey : [NSURL URLWithString:@""],
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
    XCTAssertEqualObjects(endpoint.host, @"1.2.3.4");
    XCTAssertEqual(endpoint.port, (in_port_t)8888);
    XCTAssertEqualObjects(endpoint.user, @"user");
    XCTAssertEqualObjects(endpoint.password, @"pass");
    XCTAssertEqual(endpoint.type, SPDYOriginEndpointTypeHttpsProxy);
    XCTAssertEqualObjects(endpoint.origin, origin);
}

- (void)testOriginManagerInit
{
    NSError *error = nil;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    XCTAssertNil(error);

    SPDYOriginEndpointManager *manager = [[SPDYOriginEndpointManager alloc] initWithOrigin:origin];
    XCTAssertEqualObjects(manager.origin, origin);
    XCTAssertEqual(manager.remaining, (NSUInteger)0);
    XCTAssertNil(manager.endpoint);
    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusNone);
    XCTAssertNil([manager moveToNextEndpoint]);

    XCTAssertEqual(manager.remaining, (NSUInteger)0);
    XCTAssertNil(manager.endpoint);
    XCTAssertNil([manager moveToNextEndpoint]);
}

- (void)testResolveWithNoProxyConfig
{
    // Not a case that should happen
    NSError *error = nil;
    __block BOOL gotCallback = NO;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:@"https://mytesthost.com:443" error:&error];
    SPDYMockOriginEndpointManager *manager = [[SPDYMockOriginEndpointManager alloc] initWithOrigin:origin];

    [manager resolveEndpointsWithCompletionHandler:^{
        gotCallback = YES;
        XCTAssertEqual(manager.remaining, (NSUInteger)1);
    }];

    XCTAssertTrue(gotCallback);
    XCTAssertEqual(manager.remaining, (NSUInteger)1);
    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusManualInvalid);

    SPDYOriginEndpoint *endpoint = [manager moveToNextEndpoint];
    XCTAssertNotNil(endpoint);
    XCTAssertEqual(endpoint.type, SPDYOriginEndpointTypeDirect);
}

- (void)testResolveWithDirectProxyConfig
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithProxyList:@[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeNone,
    }]];

    XCTAssertEqual(manager.remaining, (NSUInteger)1);
    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusNone);

    SPDYOriginEndpoint *endpoint = [manager moveToNextEndpoint];
    XCTAssertNotNil(endpoint);
    XCTAssertEqual(endpoint.type, SPDYOriginEndpointTypeDirect);
    XCTAssertEqualObjects(endpoint.host, @"mytesthost.com");
    XCTAssertEqual(endpoint.port, (in_port_t)443);
    XCTAssertEqualObjects(endpoint.origin.host, @"mytesthost.com");
    XCTAssertNil(endpoint.user);
    XCTAssertNil(endpoint.password);
}

- (void)testResolveWithHttpsProxyConfig
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithProxyList:@[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeHTTPS,
            (__bridge NSString *)kCFProxyHostNameKey : @"1.2.3.4",
            (__bridge NSString *)kCFProxyPortNumberKey : @"8888"
    }]];

    // Also adds direct at end
    XCTAssertEqual(manager.remaining, (NSUInteger)2);
    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusManual);

    SPDYOriginEndpoint *endpoint = [manager moveToNextEndpoint];
    XCTAssertNotNil(endpoint);
    XCTAssertEqual(endpoint.type, SPDYOriginEndpointTypeHttpsProxy);
    XCTAssertEqualObjects(endpoint.host, @"1.2.3.4");
    XCTAssertEqual(endpoint.port, (in_port_t)8888);
    XCTAssertEqualObjects(endpoint.origin.host, @"mytesthost.com");
    XCTAssertNil(endpoint.user);
    XCTAssertNil(endpoint.password);

    endpoint = [manager moveToNextEndpoint];
    XCTAssertEqual(endpoint.type, SPDYOriginEndpointTypeDirect);
    XCTAssertEqualObjects(endpoint.host, @"mytesthost.com");
    XCTAssertEqual(endpoint.port, (in_port_t)443);
}

- (void)testResolveWithInvalidHttpsProxyConfigDoesReturnDirect
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithProxyList:@[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeHTTPS,
            (__bridge NSString *)kCFProxyHostNameKey : @"",
            (__bridge NSString *)kCFProxyPortNumberKey : @"8888"
    }]];

    XCTAssertEqual(manager.remaining, (NSUInteger)1);
    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusManualInvalid);

    SPDYOriginEndpoint *endpoint = [manager moveToNextEndpoint];
    XCTAssertEqual(endpoint.type, SPDYOriginEndpointTypeDirect);
    XCTAssertEqualObjects(endpoint.host, @"mytesthost.com");
    XCTAssertEqual(endpoint.port, (in_port_t)443);
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
            (__bridge NSString *)kCFProxyAutoConfigurationURLKey : [NSURL URLWithString:@""],
    }];

    [manager resolveEndpointsWithCompletionHandler:^{
        gotCallback = YES;
        CFRunLoopStop(CFRunLoopGetCurrent());
    }];

    // The callback will happen asynchronously on the current runloop.
    CFRunLoopRun();

    XCTAssertTrue(gotCallback);
    XCTAssertEqual(manager.remaining, (NSUInteger)1);
    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusAutoInvalid);

    SPDYOriginEndpoint *endpoint = [manager moveToNextEndpoint];
    XCTAssertEqual(endpoint.type, SPDYOriginEndpointTypeDirect);
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
    XCTAssertEqual(manager.remaining, (NSUInteger)2);
    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusManual);

    // The first config in the array gets used, so verify that.
    SPDYOriginEndpoint *endpoint = [manager moveToNextEndpoint];
    XCTAssertEqual(endpoint, manager.endpoint);
    XCTAssertEqual(endpoint.type, SPDYOriginEndpointTypeHttpsProxy);

    // Valid once we support multiple proxies
    endpoint = [manager moveToNextEndpoint];
    XCTAssertEqual(manager.remaining, (NSUInteger)0);
    XCTAssertEqual(endpoint, manager.endpoint);
    XCTAssertEqual(endpoint.type, SPDYOriginEndpointTypeDirect);
}

- (void)testResolvePacFileWithProxyAndDirectDoesReturnBoth
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithPacScript:
            @"function FindProxyForURL(url, host) { return \"PROXY 1.2.3.4:8888; DIRECT\"; }"];

    XCTAssertEqual(manager.remaining, (NSUInteger)2);
    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusAuto);

    [manager moveToNextEndpoint];
    XCTAssertEqual(manager.endpoint.type, SPDYOriginEndpointTypeHttpsProxy);
    XCTAssertEqualObjects(manager.endpoint.host, @"1.2.3.4");
    XCTAssertEqual(manager.endpoint.port, (in_port_t)8888);

    // Valid once we support multiple proxies
    [manager moveToNextEndpoint];
    XCTAssertEqual(manager.endpoint.type, SPDYOriginEndpointTypeDirect);
    XCTAssertEqualObjects(manager.endpoint.host, @"mytesthost.com");
    XCTAssertEqual(manager.endpoint.port, (in_port_t)443);
}

- (void)testResolvePacFileWithMultiProxyDoesReturnAll
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithPacScript:
            @"function FindProxyForURL(url, host) { return \"PROXY 1.2.3.4:8888; PROXY 1.2.3.5:8889\"; }"];

    XCTAssertEqual(manager.remaining, (NSUInteger)3);
    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusAuto);

    [manager moveToNextEndpoint];
    XCTAssertEqual(manager.endpoint.type, SPDYOriginEndpointTypeHttpsProxy);
    XCTAssertEqualObjects(manager.endpoint.host, @"1.2.3.4");
    XCTAssertEqual(manager.endpoint.port, (in_port_t)8888);

    [manager moveToNextEndpoint];
    XCTAssertEqual(manager.endpoint.type, SPDYOriginEndpointTypeHttpsProxy);
    XCTAssertEqualObjects(manager.endpoint.host, @"1.2.3.5");
    XCTAssertEqual(manager.endpoint.port, (in_port_t)8889);

    // Valid once we support multiple proxies
    [manager moveToNextEndpoint];
    XCTAssertEqual(manager.endpoint.type, SPDYOriginEndpointTypeDirect);
    XCTAssertEqualObjects(manager.endpoint.host, @"mytesthost.com");
    XCTAssertEqual(manager.endpoint.port, (in_port_t)443);
}

- (void)testResolvePacFileWithTypoDoesReturnDirect
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithPacScript:
            @"function FindProxyForURL(url, host) { return \"PROOXY 1.2.3.4:8888\"; }"];

    XCTAssertEqual(manager.remaining, (NSUInteger)1);
    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusAutoInvalid);
    [manager moveToNextEndpoint];
    XCTAssertEqual(manager.endpoint.type, SPDYOriginEndpointTypeDirect);
}

- (void)testResolvePacFileWithNoHostDoesReturnDirect
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithPacScript:
            @"function FindProxyForURL(url, host) { return \"PROXY :8888\"; }"];

    XCTAssertEqual(manager.remaining, (NSUInteger)1);
    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusAutoInvalid);
    [manager moveToNextEndpoint];
    XCTAssertEqual(manager.endpoint.type, SPDYOriginEndpointTypeDirect);
}

- (void)testResolvePacFileReturnsNothingDoesReturnDirect
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithPacScript:
            @"function FindProxyForURL(url, host) { }"];

    XCTAssertEqual(manager.remaining, (NSUInteger)1);
    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusAutoInvalid);
    [manager moveToNextEndpoint];
    XCTAssertEqual(manager.endpoint.type, SPDYOriginEndpointTypeDirect);
}

- (void)testResolvePacFileEmptyDoesReturnDirect
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithPacScript:
            @""];

    XCTAssertEqual(manager.remaining, (NSUInteger)1);
    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusAutoInvalid);
    [manager moveToNextEndpoint];
    XCTAssertEqual(manager.endpoint.type, SPDYOriginEndpointTypeDirect);
}

- (void)testResolvePacFileWithSOCKSDoesReturnDirect
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithPacScript:
            @"function FindProxyForURL(url, host) { return \"SOCKS 1.2.3.4:8888\"; }"];

    XCTAssertEqual(manager.remaining, (NSUInteger)1);
    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusAutoInvalid);
    [manager moveToNextEndpoint];
    XCTAssertEqual(manager.endpoint.type, SPDYOriginEndpointTypeDirect);
}

- (void)testResolveWithPacScriptIsNotSupported
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithProxyList:@[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeAutoConfigurationJavaScript
    }]];

    XCTAssertEqual(manager.remaining, (NSUInteger)1);
    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusManualInvalid);

    SPDYOriginEndpoint *endpoint = [manager moveToNextEndpoint];
    XCTAssertEqual(endpoint.type, SPDYOriginEndpointTypeDirect);
}

- (void)testResolveWithSOCKSIsNotSupported
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithProxyList:@[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeSOCKS
    }]];

    XCTAssertEqual(manager.remaining, (NSUInteger)1);
    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusManualInvalid);

    SPDYOriginEndpoint *endpoint = [manager moveToNextEndpoint];
    XCTAssertEqual(endpoint.type, SPDYOriginEndpointTypeDirect);
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
    XCTAssertEqual(manager.remaining, (NSUInteger)1);
    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusNone);

    SPDYOriginEndpoint *endpoint = [manager moveToNextEndpoint];
    XCTAssertNotNil(endpoint);
    XCTAssertEqual(endpoint.type, SPDYOriginEndpointTypeDirect);
    XCTAssertEqualObjects(endpoint.host, @"mytesthost.com");
    XCTAssertEqual(endpoint.port, (in_port_t)443);
    XCTAssertEqualObjects(endpoint.origin.host, @"mytesthost.com");

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

    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusConfig);

    SPDYOriginEndpoint *endpoint = [manager moveToNextEndpoint];
    XCTAssertNotNil(endpoint);
    XCTAssertEqual(endpoint.type, SPDYOriginEndpointTypeHttpsProxy);
    XCTAssertEqualObjects(endpoint.host, @"proxyproxyproxy.com");
    XCTAssertEqual(endpoint.port, (in_port_t)9999);
    XCTAssertEqualObjects(endpoint.origin.host, @"mytesthost.com");

    // Remember to reset global config!
    [SPDYProtocol setConfiguration:[SPDYConfiguration defaultConfiguration]];
}

- (void)testSetAuthRequiredForDirectDoesNothing
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithProxyList:@[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeNone,
    }]];

    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusNone);
    manager.authRequired = YES;
    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusNone);
}

- (void)testSetAuthRequiredForManual
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithProxyList:@[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeHTTPS,
            (__bridge NSString *)kCFProxyHostNameKey : @"1.2.3.4",
            (__bridge NSString *)kCFProxyPortNumberKey : @"8888"
    }]];

    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusManual);
    manager.authRequired = YES;
    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusManualWithAuth);
}

- (void)testSetAuthRequiredForAuto
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithPacScript:
            @"function FindProxyForURL(url, host) { return \"PROXY 1.2.3.4:8888; DIRECT\"; }"];

    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusAuto);
    manager.authRequired = YES;
    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusAutoWithAuth);
}

- (void)testSetAuthRequiredForConfigOverride
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

    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusConfig);
    manager.authRequired = YES;
    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusConfigWithAuth);

    // Remember to reset global config!
    [SPDYProtocol setConfiguration:[SPDYConfiguration defaultConfiguration]];
}

- (void)testSetAuthRequiredWhenManualInvalidDoesNothing
{
    SPDYMockOriginEndpointManager *manager = [self _resolveEndpointsWithProxyList:@[@{
            (__bridge NSString *)kCFProxyTypeKey : (__bridge NSString *)kCFProxyTypeSOCKS
    }]];

    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusManualInvalid);
    manager.authRequired = YES;
    XCTAssertEqual(manager.proxyStatus, SPDYProxyStatusManualInvalid);
}

@end
