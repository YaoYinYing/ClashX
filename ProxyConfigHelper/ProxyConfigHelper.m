//
//  ProxyConfigHelper.m
//  com.west2online.ClashX.ProxyConfigHelper
//
//  Created by yichengchen on 2019/8/17.
//  Copyright © 2019 west2online. All rights reserved.
//

#import "ProxyConfigHelper.h"
#import <AppKit/AppKit.h>
#import <Security/Security.h>
#import "ProxyConfigRemoteProcessProtocol.h"
#import "ProxySettingTool.h"

@interface ProxyConfigHelper()
<
NSXPCListenerDelegate,
ProxyConfigRemoteProcessProtocol
>

@property (nonatomic, strong) NSXPCListener *listener;
@property (nonatomic, strong) NSMutableSet<NSXPCConnection *> *connections;
@property (nonatomic, strong) NSTimer *checkTimer;
@property (nonatomic, assign) BOOL shouldQuit;

@end

@implementation ProxyConfigHelper

static NSUInteger const kMaxIgnoreListEntries = 64;
static NSUInteger const kMaxIgnoreItemLength = 255;

- (instancetype)init {
    
    if (self = [super init]) {
        self.connections = [NSMutableSet new];
        self.shouldQuit = NO;
        self.listener = [[NSXPCListener alloc] initWithMachServiceName:@"com.west2online.ClashX.ProxyConfigHelper"];
        self.listener.delegate = self;
    }
    return self;
}

- (void)run {
    [self.listener resume];
    self.checkTimer =
    [NSTimer timerWithTimeInterval:5.f target:self selector:@selector(connectionCheckOnLaunch) userInfo:nil repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:self.checkTimer forMode:NSDefaultRunLoopMode];
    while (!self.shouldQuit) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.0]];
    }
}

- (void)connectionCheckOnLaunch {
    if (self.connections.count == 0) {
        self.shouldQuit = YES;
    }
}

- (NSString *)allowedClientRequirement {
    NSString *requirement = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"AllowedClientCodeSigningRequirement"];
    if ([requirement isKindOfClass:[NSString class]]) {
        requirement = [requirement stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return requirement ?: @"";
}

- (BOOL)connectionIsVaild: (NSXPCConnection *)connection {
    NSRunningApplication *remoteApp =
    [NSRunningApplication runningApplicationWithProcessIdentifier:connection.processIdentifier];
    if (remoteApp == nil) {
        return NO;
    }

    NSString *requirement = [self allowedClientRequirement];
#if DEBUG
    if (requirement.length == 0) {
        return YES;
    }
#else
    if (requirement.length == 0) {
        return NO;
    }
#endif

    NSDictionary *attributes = @{(__bridge NSString *)kSecGuestAttributePid : @(connection.processIdentifier)};
    SecCodeRef guestCode = NULL;
    OSStatus status = SecCodeCopyGuestWithAttributes(NULL, (__bridge CFDictionaryRef)attributes, kSecCSDefaultFlags, &guestCode);
    if (status != errSecSuccess || guestCode == NULL) {
        return NO;
    }
    SecRequirementRef secRequirement = NULL;
    status = SecRequirementCreateWithString((__bridge CFStringRef)requirement, kSecCSDefaultFlags, &secRequirement);
    if (status != errSecSuccess || secRequirement == NULL) {
        if (guestCode != NULL) { CFRelease(guestCode); }
        return NO;
    }
    status = SecCodeCheckValidity(guestCode, kSecCSDefaultFlags, secRequirement);
    CFRelease(secRequirement);
    CFRelease(guestCode);
    return status == errSecSuccess;
}

- (BOOL)portIsValid:(int)port {
    return port >= 1 && port <= 65535;
}

- (BOOL)isValidPacURL:(NSString *)pac {
    if (pac == nil || pac.length == 0) {
        return YES;
    }
    NSURL *url = [NSURL URLWithString:pac];
    if (url == nil || url.scheme == nil) {
        return NO;
    }
    NSString *host = url.host.lowercaseString ?: @"";
    if ([host isEqualToString:@"localhost"] || [host isEqualToString:@"127.0.0.1"] || [host hasPrefix:@"127."]) {
        return YES;
    }
    return NO;
}

- (BOOL)isValidIgnoreList:(NSArray<NSString *> *)ignoreList {
    if (![ignoreList isKindOfClass:[NSArray class]] || ignoreList.count > kMaxIgnoreListEntries) {
        return NO;
    }
    NSCharacterSet *invalidSet = [NSCharacterSet characterSetWithCharactersInString:@"\n\r\t"];
    for (NSString *item in ignoreList) {
        if (![item isKindOfClass:[NSString class]] || item.length == 0 || item.length > kMaxIgnoreItemLength) {
            return NO;
        }
        if ([item rangeOfCharacterFromSet:invalidSet].location != NSNotFound) {
            return NO;
        }
    }
    return YES;
}

// MARK: - NSXPCListenerDelegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    // Trust boundary: this helper is privileged and must only serve the signed main app.
    // It only manages system proxy preferences and must not be expanded to general operations.
    if (![self connectionIsVaild:newConnection]) {
        return NO;
    }
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(ProxyConfigRemoteProcessProtocol)];
    newConnection.exportedObject = self;
    __weak NSXPCConnection *weakConnection = newConnection;
    __weak ProxyConfigHelper *weakSelf = self;
    newConnection.invalidationHandler = ^{
        [weakSelf.connections removeObject:weakConnection];
        if (weakSelf.connections.count == 0) {
            weakSelf.shouldQuit = YES;
        }
    };
    [self.connections addObject:newConnection];
    [newConnection resume];
    return YES;
}

// MARK: - ProxyConfigRemoteProcessProtocol
- (void)getVersion:(stringReplyBlock)reply {
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (version == nil) {
        version = @"unknown";
    }
    reply(version);
}

- (void)enableProxyWithPort:(int)port
          socksPort:(int)socksPort
            pac:(NSString *)pac
            filterInterface:(BOOL)filterInterface
                 ignoreList:(NSArray<NSString *>*)ignoreList
            error:(stringReplyBlock)reply {
    if (![self portIsValid:port] || ![self portIsValid:socksPort]) {
        reply(@"Invalid proxy port");
        return;
    }
    if (![self isValidPacURL:pac]) {
        reply(@"Invalid PAC URL");
        return;
    }
    if (![self isValidIgnoreList:ignoreList]) {
        reply(@"Invalid ignore list");
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        ProxySettingTool *tool = [ProxySettingTool new];
        [tool enableProxyWithport:port socksPort:socksPort pacUrl:pac filterInterface:filterInterface ignoreList:ignoreList];
        reply(nil);
    });
}

- (void)disableProxyWithFilterInterface:(BOOL)filterInterface reply:(stringReplyBlock)reply {
    dispatch_async(dispatch_get_main_queue(), ^{
        ProxySettingTool *tool = [ProxySettingTool new];
        [tool disableProxyWithfilterInterface:filterInterface];
        reply(nil);
    });
}


- (void)restoreProxyWithCurrentPort:(int)port
                          socksPort:(int)socksPort
                               info:(NSDictionary *)dict
                    filterInterface:(BOOL)filterInterface
                              error:(stringReplyBlock)reply {
    if (![self portIsValid:port] || ![self portIsValid:socksPort]) {
        reply(@"Invalid proxy port");
        return;
    }
    if (![dict isKindOfClass:[NSDictionary class]]) {
        reply(@"Invalid restore payload");
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        ProxySettingTool *tool = [ProxySettingTool new];
        [tool restoreProxySetting:dict currentPort:port currentSocksPort:socksPort filterInterface:filterInterface];
        reply(nil);
    });
}

- (void)getCurrentProxySetting:(dictReplyBlock)reply {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *info = [ProxySettingTool currentProxySettings];
        reply(info);
    });
}


@end
