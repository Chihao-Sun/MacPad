#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface MPBridge : NSObject
+ (NSDictionary *)capabilities;
+ (NSArray<NSDictionary *> *)devices;
+ (NSDictionary *)connectionInfoForName:(NSString *)name;
+ (NSUInteger)usbIPadCount;
+ (BOOL)startUSBMonitoring:(void (^)(void))handler;
+ (void)stopUSBMonitoring;
+ (NSDictionary *)displayTraits:(uint32_t)displayID;
+ (NSDictionary *)nativePanelForDisplay:(uint32_t)displayID NS_SWIFT_NAME(nativePanel(forDisplay:));
+ (void)connectName:(NSString *)name transport:(NSInteger)transport completion:(void (^)(NSString * _Nullable))completion;
+ (void)disconnectName:(NSString *)name completion:(void (^)(NSString * _Nullable))completion;
+ (BOOL)createVirtual:(NSError * _Nullable * _Nullable)error;
+ (BOOL)setVirtualPixelWidth:(NSUInteger)width height:(NSUInteger)height error:(NSError * _Nullable * _Nullable)error;
+ (uint32_t)virtualDisplayID;
+ (void)restorePreviousVirtual;
+ (void)releasePreviousVirtuals;
+ (void)releaseVirtual;
@end
NS_ASSUME_NONNULL_END
