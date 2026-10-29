#import "Bridge.h"
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/graphics/IOGraphicsTypes.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <math.h>

// Independently authored compatibility bridge. All private classes/selectors are
// checked at runtime because Apple can change these interfaces between releases.
static id virtualScreen;
static NSMutableArray *previousVirtualScreens;
static NSUInteger preferredPixelWidth,preferredPixelHeight;
static void *sidecarHandle;
static void *coreDisplayHandle;
static NSMutableDictionary<NSString *,id> *knownDevices;
static IONotificationPortRef usbPort;
static io_iterator_t usbAdded,usbRemoved;
static void (^usbChanged)(void);
static void DrainUSB(void *context,io_iterator_t iterator) {
    io_service_t service;
    while((service=IOIteratorNext(iterator)))IOObjectRelease(service);
    if(usbChanged)usbChanged();
}
static NSString *const MPErrorDomain = @"MacPad";

static id Send0(id obj, NSString *sel) {
    SEL s=NSSelectorFromString(sel);
    if (!obj || ![obj respondsToSelector:s]) return nil;
    return ((id(*)(id,SEL))objc_msgSend)(obj,s);
}
static id Manager(void) {
    if (!sidecarHandle) sidecarHandle=dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_LAZY|RTLD_LOCAL);
    return Send0(NSClassFromString(@"SidecarDisplayManager"),@"sharedManager");
}
static NSArray *Devices(void) {
    NSMutableArray *result=[NSMutableArray array];
    NSMutableSet *names=[NSMutableSet set];
    // At login active discovery may be empty while a paired, recent device
    // already exists. Reuse only actual SidecarDevice objects from the system.
    for(NSString *selector in @[@"devices",@"recentDevices"]) {
        id value=Send0(Manager(),selector);
        if(![value isKindOfClass:NSArray.class])continue;
        for(id device in value) {
            if(![device isKindOfClass:NSClassFromString(@"SidecarDevice")])continue;
            id name=Send0(device,@"name");
            if(![name isKindOfClass:NSString.class] || [names containsObject:name])continue;
            [names addObject:name];[result addObject:device];
            if(!knownDevices)knownDevices=[NSMutableDictionary dictionary];
            knownDevices[name]=device;
        }
    }
    return result;
}
static NSString *Name(id device) {
    id n=Send0(device,@"name");
    return [n isKindOfClass:NSString.class] ? n : @"未命名 iPad";
}
static id Find(NSString *name) {
    // Keep system-provided paired objects in memory only. Repeated discovery
    // here can block a hot transport handover for several seconds.
    id cached=knownDevices[name];if(cached)return cached;
    for(id d in Devices()) if([Name(d) isEqualToString:name]) return d;
    return nil;
}
static NSError *Failure(NSString *text) {
    return [NSError errorWithDomain:MPErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:text}];
}
static id MakeVirtual(NSUInteger width,NSUInteger height,NSError **error) {
    if(width<640 || height<640 || width>8192 || height>8192 || width%2 || height%2 || width*height>33554432) {
        if(error)*error=Failure(@"高清画布尺寸超出可用范围。");return nil;
    }
    @try {
        Class dc=NSClassFromString(@"CGVirtualDisplayDescriptor"),sc=NSClassFromString(@"CGVirtualDisplay");
        Class mc=NSClassFromString(@"CGVirtualDisplayMode"),tc=NSClassFromString(@"CGVirtualDisplaySettings");
        if(!dc || !sc || !mc || !tc){if(error)*error=Failure(@"当前系统不支持虚拟屏幕。");return nil;}
        id desc=[[dc alloc] init];
        [desc setValue:@"MacPad Screen" forKey:@"name"];
        [desc setValue:@(width) forKey:@"maxPixelsWide"];[desc setValue:@(height) forKey:@"maxPixelsHigh"];
        [desc setValue:@0x4d50 forKey:@"vendorID"];
        uint32_t product=0x40000000u|(((uint32_t)(width/2)&0xfffu)<<12)|((uint32_t)(height/2)&0xfffu);
        [desc setValue:@(product) forKey:@"productID"];
        [desc setValue:@(arc4random_uniform(UINT32_MAX-1)+1) forKey:@"serialNum"];
        [desc setValue:(id)dispatch_get_main_queue() forKey:@"queue"];
        [desc setValue:[NSValue valueWithSize:NSMakeSize(width*25.4/264.0,height*25.4/264.0)] forKey:@"sizeInMillimeters"];
        SEL init=NSSelectorFromString(@"initWithDescriptor:");id alloc=[sc alloc];
        if(![alloc respondsToSelector:init]){if(error)*error=Failure(@"虚拟屏幕初始化接口不可用。");return nil;}
        id screen=((id(*)(id,SEL,id))objc_msgSend)(alloc,init,desc);
        if(!screen){if(error)*error=Failure(@"系统拒绝创建虚拟屏幕。");return nil;}
        SEL mi=NSSelectorFromString(@"initWithWidth:height:refreshRate:");
        if(![[mc alloc] respondsToSelector:mi]){if(error)*error=Failure(@"高清模式接口不可用。");return nil;}
        // Settings modes use logical dimensions when hiDPI is enabled;
        // descriptor limits retain the physical backing dimensions.
        id mode=((id(*)(id,SEL,NSUInteger,NSUInteger,double))objc_msgSend)([mc alloc],mi,width/2,height/2,60.0);
        NSArray *modes=mode ? @[mode] : @[];
        id settings=[[tc alloc] init];[settings setValue:@1 forKey:@"hiDPI"];[settings setValue:modes forKey:@"modes"];
        SEL apply=NSSelectorFromString(@"applySettings:");
        if(![screen respondsToSelector:apply] || !((BOOL(*)(id,SEL,id))objc_msgSend)(screen,apply,settings)) {
            if(error)*error=Failure(@"系统拒绝应用高清显示模式。");return nil;
        }
        return screen;
    } @catch(NSException *e){if(error)*error=Failure(e.reason?:@"创建高清屏幕失败。");return nil;}
}
@implementation MPBridge
+ (BOOL)startUSBMonitoring:(void (^)(void))handler {
    if(usbPort){usbChanged=[handler copy];return YES;}
    usbPort=IONotificationPortCreate(kIOMainPortDefault);
    if(!usbPort)return NO;
    IONotificationPortSetDispatchQueue(usbPort,dispatch_get_main_queue());
    kern_return_t a=IOServiceAddMatchingNotification(usbPort,kIOFirstMatchNotification,IOServiceMatching("IOUSBHostDevice"),DrainUSB,NULL,&usbAdded);
    kern_return_t b=IOServiceAddMatchingNotification(usbPort,kIOTerminatedNotification,IOServiceMatching("IOUSBHostDevice"),DrainUSB,NULL,&usbRemoved);
    if(a!=KERN_SUCCESS || b!=KERN_SUCCESS){[self stopUSBMonitoring];return NO;}
    DrainUSB(NULL,usbAdded);DrainUSB(NULL,usbRemoved);
    usbChanged=[handler copy];return YES;
}
+ (void)stopUSBMonitoring {
    usbChanged=nil;
    if(usbAdded){IOObjectRelease(usbAdded);usbAdded=0;}
    if(usbRemoved){IOObjectRelease(usbRemoved);usbRemoved=0;}
    if(usbPort){IONotificationPortDestroy(usbPort);usbPort=NULL;}
}
+ (NSDictionary *)displayTraits:(uint32_t)displayID {
    if(!coreDisplayHandle) coreDisplayHandle=dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",RTLD_LAZY|RTLD_LOCAL);
    if(!coreDisplayHandle)return @{};
    CFDictionaryRef (*copyInfo)(uint32_t)=dlsym(coreDisplayHandle,"CoreDisplay_DisplayCreateInfoDictionary");
    if(!copyInfo)return @{};
    CFDictionaryRef ref=copyInfo(displayID);if(!ref)return @{};
    NSDictionary *info=CFBridgingRelease(ref);
    id value=info[@"kCGDisplayIsVirtualDevice"];
    return [value isKindOfClass:NSNumber.class] ? @{@"virtual":value} : @{};
}
+ (NSDictionary *)nativePanelForDisplay:(uint32_t)displayID {
    if(!displayID || CGDisplayVendorNumber(displayID)!=0x6161706c || CGDisplayModelNumber(displayID)!=0x69506164)return @{};
    NSUInteger width=0,height=0;NSString *source=@"";
    CFArrayRef modes=CGDisplayCopyAllDisplayModes(displayID,(__bridge CFDictionaryRef)@{(__bridge NSString*)kCGDisplayShowDuplicateLowResolutionModes:@YES});
    if(modes) {
        for(id object in (__bridge NSArray*)modes) {
            CGDisplayModeRef mode=(__bridge CGDisplayModeRef)object;
            if(!(CGDisplayModeGetIOFlags(mode)&kDisplayModeNativeFlag))continue;
            NSUInteger w=CGDisplayModeGetPixelWidth(mode),h=CGDisplayModeGetPixelHeight(mode);
            if(w>=640 && h>=640 && w<=8192 && h<=8192 && w*h>width*height){width=w;height=h;}
        }
        CFRelease(modes);
        if(width && height)source=@"native-mode";
    }
    // Mirroring may add an oversized transport mode. Only the native flag,
    // or the display's own physical-pixel information, describes its panel.
    if(!width || !height) {
        if(!coreDisplayHandle)coreDisplayHandle=dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",RTLD_LAZY|RTLD_LOCAL);
        CFDictionaryRef(*copyInfo)(uint32_t)=coreDisplayHandle?dlsym(coreDisplayHandle,"CoreDisplay_DisplayCreateInfoDictionary"):NULL;
        CFDictionaryRef ref=copyInfo?copyInfo(displayID):NULL;
        if(ref) {
            NSDictionary *info=CFBridgingRelease(ref);id w=info[@"kCGDisplayPixelWidth"],h=info[@"kCGDisplayPixelHeight"];
            if([w isKindOfClass:NSNumber.class] && [h isKindOfClass:NSNumber.class]) {
                NSUInteger x=[w unsignedIntegerValue],y=[h unsignedIntegerValue];
                if(x>=640 && y>=640 && x<=8192 && y<=8192){width=x;height=y;source=@"display-info";}
            }
        }
    }
    if(!width || !height)return @{};
    NSInteger rotation=((NSInteger)llround(CGDisplayRotation(displayID))%360+360)%360;
    if(rotation==90 || rotation==270){NSUInteger swap=width;width=height;height=swap;}
    return @{@"width":@(width),@"height":@(height),@"source":source};
}
+ (NSDictionary *)capabilities {
    @try {
        id m=Manager();
        return @{@"sidecar":@(m!=nil),
                 @"wiredConnection":@([m respondsToSelector:NSSelectorFromString(@"connectToDevice:withConfig:completion:")]),
                 @"automaticConnection":@([m respondsToSelector:NSSelectorFromString(@"connectToDevice:completion:")]),
                 @"virtualDisplay":@(NSClassFromString(@"CGVirtualDisplay")!=nil),
                 @"virtualDescriptor":@(NSClassFromString(@"CGVirtualDisplayDescriptor")!=nil)};
    } @catch(NSException *e) {return @{@"error":e.reason?:@"系统接口不可用"};}
}
+ (NSArray<NSDictionary *> *)devices {
    @try {
        NSMutableArray *r=[NSMutableArray array];
        for(id d in Devices()) [r addObject:@{@"name":Name(d)}];
        return r;
    } @catch(NSException *e) {return @[];}
}
+ (NSDictionary *)connectionInfoForName:(NSString *)name {
    @try {
        id manager=Manager(),connected=Send0(manager,@"connectedDevices");
        if(![connected isKindOfClass:NSArray.class])return @{};
        for(id device in connected) {
            if(![Name(device) isEqualToString:name])continue;
            SEL selector=NSSelectorFromString(@"configForDevice:");
            if(![manager respondsToSelector:selector])return @{@"connected":@YES};
            id cfg=((id(*)(id,SEL,id))objc_msgSend)(manager,selector,device);
            SEL transport=NSSelectorFromString(@"transport");
            if(![cfg respondsToSelector:transport])return @{@"connected":@YES};
            int64_t value=((int64_t(*)(id,SEL))objc_msgSend)(cfg,transport);
            // This is the system's session configuration, not a USB presence
            // guess or a claim to have measured the video packet route.
            return @{@"connected":@YES,@"configuredTransport":@(value)};
        }
    } @catch(NSException *e) {return @{};}
    return @{};
}
+ (NSUInteger)usbIPadCount {
    io_iterator_t it=0;
    if(IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOUSBHostDevice"),&it)!=KERN_SUCCESS) return 0;
    NSUInteger count=0; io_service_t device;
    while((device=IOIteratorNext(it))) {
        CFTypeRef ref=IORegistryEntryCreateCFProperty(device,CFSTR("USB Product Name"),kCFAllocatorDefault,0);
        if(ref) {NSString *name=(__bridge id)ref;
            if([name isKindOfClass:NSString.class] && [name rangeOfString:@"iPad" options:NSCaseInsensitiveSearch].location!=NSNotFound) count++;
            CFRelease(ref);
        }
        IOObjectRelease(device);
    }
    IOObjectRelease(it);return count;
}
+ (void)connectName:(NSString *)name transport:(NSInteger)transport completion:(void (^)(NSString * _Nullable))completion {
    @try {
        id manager=Manager(), device=Find(name);
        if(!device) {completion(@"未发现所选 iPad。请保持解锁并检查系统随航是否能发现它。");return;}
        void (^done)(NSError *)=^(NSError *err){dispatch_async(dispatch_get_main_queue(),^{completion(err.localizedDescription);});};
        if(transport==1 || transport==2) {
            Class cfgClass=NSClassFromString(@"SidecarDisplayConfig");
            id cfg=[[cfgClass alloc] init];SEL setter=NSSelectorFromString(@"setTransport:");
            SEL connect=NSSelectorFromString(@"connectToDevice:withConfig:completion:");
            if(!cfg || ![cfg respondsToSelector:setter] || ![manager respondsToSelector:connect]) {
                completion(@"当前 macOS 不提供指定连接方式的随航接口。");return;
            }
            // 1 and 2 were both read back from successful sessions on this Mac.
            // Explicit wireless avoids retrying a stale USB path after unplug.
            ((void(*)(id,SEL,int64_t))objc_msgSend)(cfg,setter,(int64_t)transport);
            ((void(*)(id,SEL,id,id,id))objc_msgSend)(manager,connect,device,cfg,done);
        } else {
            SEL connect=NSSelectorFromString(@"connectToDevice:completion:");
            if(![manager respondsToSelector:connect]) {completion(@"当前 macOS 不提供已知的随航接口。");return;}
            ((void(*)(id,SEL,id,id))objc_msgSend)(manager,connect,device,done);
        }
    } @catch(NSException *e) {completion(e.reason?:@"系统连接接口异常");}
}
+ (void)disconnectName:(NSString *)name completion:(void (^)(NSString * _Nullable))completion {
    @try {
        id m=Manager(),d=Find(name);SEL s=NSSelectorFromString(@"disconnectFromDevice:completion:");
        if(!d || ![m respondsToSelector:s]) {completion(@"当前连接无法由 MacPad 断开。");return;}
        void (^done)(NSError *)=^(NSError *e){dispatch_async(dispatch_get_main_queue(),^{completion(e.localizedDescription);});};
        ((void(*)(id,SEL,id,id))objc_msgSend)(m,s,d,done);
    } @catch(NSException *e) {completion(e.reason?:@"断开失败");}
}
 + (BOOL)createVirtual:(NSError **)error {
    if(virtualScreen)return YES;
    NSString *saved=[[NSUserDefaults standardUserDefaults] stringForKey:@"displaySize"]?:@"1344x938";
    NSString *logical=[[saved componentsSeparatedByString:@"@"] firstObject];
    NSArray *parts=[logical componentsSeparatedByString:@"x"];
    NSInteger w=0,h=0;
    if(parts.count==2) {
        NSCharacterSet *nonDigits=[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
        if([parts[0] length] && [parts[1] length] && [parts[0] rangeOfCharacterFromSet:nonDigits].location==NSNotFound && [parts[1] rangeOfCharacterFromSet:nonDigits].location==NSNotFound) {
            w=[parts[0] longLongValue];h=[parts[1] longLongValue];
        }
    }
    if(w<320 || h<320 || w>4096 || h>4096 || w*h*4>33554432){w=1344;h=938;}
    NSUInteger width=w*2,height=h*2;
    id screen=MakeVirtual(width,height,error);if(!screen)return NO;
    virtualScreen=screen;preferredPixelWidth=width;preferredPixelHeight=height;return YES;
}
+ (uint32_t)virtualDisplayID {
    SEL s=NSSelectorFromString(@"displayID");
    if(!virtualScreen || ![virtualScreen respondsToSelector:s])return 0;
    return ((uint32_t(*)(id,SEL))objc_msgSend)(virtualScreen,s);
}
 + (BOOL)setVirtualPixelWidth:(NSUInteger)width height:(NSUInteger)height error:(NSError **)error {
    if(!virtualScreen){if(error)*error=Failure(@"虚拟屏幕尚未创建。");return NO;}
    if(width==preferredPixelWidth && height==preferredPixelHeight)return YES;
    id screen=MakeVirtual(width,height,error);if(!screen)return NO;
    if(!previousVirtualScreens)previousVirtualScreens=[NSMutableArray array];
    [previousVirtualScreens addObject:virtualScreen];
    virtualScreen=screen;preferredPixelWidth=width;preferredPixelHeight=height;return YES;
}
+ (void)restorePreviousVirtual {
    if(previousVirtualScreens.count==0)return;
    virtualScreen=previousVirtualScreens.lastObject;
    [previousVirtualScreens removeLastObject];
    CGDisplayModeRef mode=CGDisplayCopyDisplayMode([self virtualDisplayID]);
    if(mode){preferredPixelWidth=CGDisplayModeGetPixelWidth(mode);preferredPixelHeight=CGDisplayModeGetPixelHeight(mode);CGDisplayModeRelease(mode);}
}
+ (void)releasePreviousVirtuals {[previousVirtualScreens removeAllObjects];}
+ (void)releaseVirtual {virtualScreen=nil;[previousVirtualScreens removeAllObjects];}
@end
