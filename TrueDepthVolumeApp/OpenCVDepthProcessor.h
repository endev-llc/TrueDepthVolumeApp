//
//  OpenCVDepthProcessor.h
//  TrueDepthVolumeApp
//
//  Created by Jake Adams on 9/6/25.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OpenCVDepthProcessor : NSObject

+ (nullable NSDictionary *)processDepthMap:(NSArray<NSArray<NSNumber *> *> *)depthMap
                                     width:(int)width
                                    height:(int)height;

@end

NS_ASSUME_NONNULL_END
