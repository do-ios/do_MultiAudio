//
//  do_MultiAudio_MM.h
//  DoExt_MM
//
//  Created by @zmj on @2017/04/05.
//  Copyright (c) 2015年 DoExt. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol do_MultiAudio_IMM <NSObject>
//实现同步或异步方法，parms中包含了所需用的属性
- (void)pause:(NSArray *)parms;
- (void)play:(NSArray *)parms;
- (void)resume:(NSArray *)parms;
- (void)stop:(NSArray *)parms;

@end
