//
//  do_MultiAudio_MM.m
//  DoExt_MM
//
//  Created by @zmj on @2017/04/05.
//  Copyright (c) 2015年 DoExt. All rights reserved.
//

#import "do_MultiAudio_MM.h"
#import "doJsonHelper.h"
#import "doScriptEngineHelper.h"
#import "doIScriptEngine.h"
#import "doInvokeResult.h"
#import <AVFoundation/AVFoundation.h>
#import "doServiceContainer.h"
#import "doLogEngine.h"
#import "doIOHelper.h"
#import "doDataFS.h"
#import "doIPage.h"
#ifdef DEBUG
#define ZJLog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#else
#define ZJLog(...)
#endif
typedef NS_ENUM(NSInteger, do_MultiAudio_PlayError){
    musicURLNotFound, // 路径为空
    musicURLNotLegal, // 路径不合法
    musicURLMathcedAssetNotFound, // 路径URL对应的资源不存在
    musicURLAssetLoadFailed, // 音频url对应的资源加载失败
    musicPlayErrorUnknow,
};

@interface do_MultiAudio_MM()

@property (nonatomic, strong) AVAsset *musicAsset;
@property (nonatomic, strong) AVPlayerItem *musicPlayerItem;
@property (nonatomic, strong) AVPlayer *musicPlayer;
@property (nonatomic, assign) NSInteger startPlayPoint; // 开始播放时间点
@property (nonatomic, assign) NSTimer *timerObserver;
@property (nonatomic, assign) BOOL hadRemovePlayerItemStatusObserver;
@property (nonatomic, assign) CMTime suspendTime; // 暂停时间点
@end

@implementation do_MultiAudio_MM

#pragma makr - lazy

- (AVPlayer *)musicPlayer {
    if (_musicPlayer == nil) {
        _musicPlayer = [[AVPlayer alloc] init];
        return _musicPlayer;
    }
    return _musicPlayer;
}


#pragma mark - 注册属性（--属性定义--）
/*
 [self RegistProperty:[[doProperty alloc]init:@"属性名" :属性类型 :@"默认值" : BOOL:是否支持代码修改属性]];
 */
-(void)OnInit
{
    [super OnInit];
    
    // 获取音频绘画
    AVAudioSession *session = [AVAudioSession sharedInstance];
    // 设置音频绘画类别为后台播放
    [session setCategory:AVAudioSessionCategoryPlayback error:nil];
    // 激活绘画
    [session setActive:YES error:nil];
    
    _hadRemovePlayerItemStatusObserver = false;
    
}

//销毁所有的全局对象
-(void)Dispose
{
    //(self)类销毁时会调用递归调用该方法，在该类中主动生成的非原生的扩展对象需要主动调该方法使其销毁
    [self p_currentItemRemoveObserver];
    _musicAsset = nil;
    _musicPlayerItem = nil;
    _musicPlayer = nil;
    self.startPlayPoint = 0;
    self.suspendTime = kCMTimeZero;
    _hadRemovePlayerItemStatusObserver = false;
}

#pragma mark -
#pragma mark - 同步异步方法的实现

#pragma mark - sync method
//同步

- (void)play:(NSArray *)parms
{
    [self p_currentItemRemoveObserver];
    [self clearResource];
    
    NSDictionary *_dictParas = [parms objectAtIndex:0];
    //参数字典_dictParas
    id<doIScriptEngine> _scritEngine = [parms objectAtIndex:1];
    //自己的代码实现
    //_invokeResult设置返回值
    NSString *musicPathStr = [doJsonHelper GetOneText:_dictParas :@"path" :nil];
    self.startPlayPoint = [doJsonHelper GetOneInteger:_dictParas :@"point" :0];
    if (musicPathStr == nil || [musicPathStr  isEqual: @""]) {
        ZJLog(@"音频路径为空");
        
        [self logErrorWithErrorType:musicURLNotFound];
    }else {
        NSURL *musicURL;
        if ([self isLocalFilePath:musicPathStr]) { // 本地音频
            musicPathStr = [doIOHelper GetLocalFileFullPath:_scritEngine.CurrentPage.CurrentApp :musicPathStr];
            musicURL = [NSURL fileURLWithPath:musicPathStr];
        }else {
            musicURL = [NSURL URLWithString:musicPathStr];
        }
        
        if (musicURL != nil) {
            self.musicAsset = [self getAVAssetWithURL:musicURL];
            if (self.musicAsset != nil) {
                // 创建播放资源
                self.musicPlayerItem = [AVPlayerItem playerItemWithAsset:self.musicAsset];
                // 播放当前资源
                [self.musicPlayer replaceCurrentItemWithPlayerItem:self.musicPlayerItem];
                // 添加观察者
                [self p_currentItemAddObserver];
            }
            
        }else { // url 不合法
            [self logErrorWithErrorType:musicURLNotLegal];
        }

    }
}

- (void)pause:(NSArray *)parms
{
    doInvokeResult *_invokeResult = [parms objectAtIndex:2];
    //_invokeResult设置返回值
    
    int currentPoint = 0;
    if (self.musicPlayer) {
        if (self.musicPlayer.error == nil) {
            if (self.musicPlayer.rate > 0) { // 0.0暂停，-1:播放失败, 1.0 正在播放
                currentPoint = self.musicPlayer.currentItem.currentTime.value / self.musicPlayer.currentItem.currentTime.timescale * 1000.0;
                self.suspendTime = self.musicPlayer.currentTime;
                [self.musicPlayer pause];
            }
        }
    }
    [_invokeResult SetResultInteger:currentPoint];
    
}

- (void)resume:(NSArray *)parms
{
    if (self.musicPlayer) {
        if (self.musicPlayer.error == nil) {
            if (self.musicPlayer.rate < 1 && self.musicPlayer.rate > -1) { // 0.0暂停，-1:播放失败, 1.0 正在播放
                @try {
                    // 精确继续上次时间点播放
                    [self.musicPlayer seekToTime:self.suspendTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
                        if (finished) {
                            [self.musicPlayer play];
                        }
                    }];
                } @catch (NSException *exception) {
                    [self.musicPlayer play];
                }
           
            }
        }
    }
    
}

- (void)stop:(NSArray *)parms
{
    if (self.musicPlayer) {
        if (self.musicPlayer.currentItem) {
            [self p_currentItemRemoveObserver];
            [self clearResource];
        }
    }
}

#pragma mark - async method
//异步

#pragma mark - customize method
/**
 whether is local resource
 */
- (BOOL)isLocalFilePath:(NSString*)path {
    if ([path hasPrefix:@"data://"] || [path hasPrefix:@"source://"]) {
        return true;
    }
    return false;
}

/**
 get asset with url
 
 @param assetURL url
 @return url matched AVAsset
 */
- (AVAsset*)getAVAssetWithURL: (NSURL*)assetURL {
    AVAsset *asset = [AVAsset assetWithURL:assetURL];
    if (assetURL != nil) {
//        NSArray *keys=@[@"availableMetadataFormats"];
//        [asset loadValuesAsynchronouslyForKeys:keys completionHandler:^{
//            NSError *error = nil;
//            AVKeyValueStatus state = [asset statusOfValueForKey:@"availableMetadataFormats" error:&error];
//            switch (state) {
//                case AVKeyValueStatusLoaded:
//                    ZJLog(@"%@",[NSString stringWithFormat:@"asset: %@ 加载成功",assetURL.absoluteString]);
//                    break;
//                case AVKeyValueStatusFailed:
//                    ZJLog(@"%@",[NSString stringWithFormat:@"asset: %@ 加载失败",assetURL.absoluteString]);
//                    [self logErrorWithErrorType: musicURLAssetLoadFailed];
//                    [self clearResource];
//                    break;
//                default:
//                    break;
//            }
//            
//        }];
        
    }else {
        ZJLog(@"初始化音频路径URL失败");
        [self logErrorWithErrorType: musicURLMathcedAssetNotFound];
        
        
    }
    return asset;
}


/**
 log error info with errType

 @param errType the error: do_MultiAudio_PlayError
 */
- (void)logErrorWithErrorType: (do_MultiAudio_PlayError) errType {
    NSString *logErrorStr = @"";
    switch (errType) {
        case musicURLNotFound:
            logErrorStr = [NSString stringWithFormat:@"do_MultiAudio Initilaze Asset Error: musicURLNotFound-> 调用\"play\"方法时，第一个参数为音频路径，参数必填且不能为空字符串"];
            break;
            
        case musicURLNotLegal:
            logErrorStr = [NSString stringWithFormat:@"do_MultiAudio Initilaze Asset Error: musicURLNotLegal-> \"play\"方法传递的音频路径URL不是一个合法路径"];
            
            break;
        case musicURLMathcedAssetNotFound:
            logErrorStr = [NSString stringWithFormat:@"do_MultiAudio Initilaze Asset Error: musicURLMathcedAssetNotFound-> \"play\"方法传递的音频路径URL对应的资源不存在"];
            
            break;
        case musicURLAssetLoadFailed:
            logErrorStr = [NSString stringWithFormat:@"do_MultiAudio Initilaze Asset Error: musicURLAssetLoadFailed-> \"play\"方法传递的音频路径URL对应的资源加载失败或不存在"];
            break;
        case musicPlayErrorUnknow:
            logErrorStr = [NSString stringWithFormat:@"do_MultiAudio Initilaze Asset Error: musicPlayErrorUnknow-> \"play\"方法传递的音频路径URL对应的资源加载出现未知错误"];
            break;
        default:
            break;
    }
    
    [[doServiceContainer Instance].LogEngine WriteError:nil : logErrorStr];
    
}


/**
 add observers
 */
- (void)p_currentItemAddObserver {
    
    //监控状态属性，注意AVPlayer也有一个status属性，通过监控它的status也可以获得播放状态
    if (self.musicPlayer) {
        if (self.musicPlayer.currentItem) {
            [self.musicPlayer.currentItem addObserver:self forKeyPath:@"status" options:(NSKeyValueObservingOptionOld|NSKeyValueObservingOptionNew) context:nil];
            //监控播放完成通知
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(musicFinishedPlay) name:AVPlayerItemDidPlayToEndTimeNotification object:self.musicPlayer.currentItem];
        }
    }
}

/**
 remove observers
 */
- (void)p_currentItemRemoveObserver {
    if (self.musicPlayer) {
        if (self.musicPlayer.currentItem) {
            if (!_hadRemovePlayerItemStatusObserver) {
                [self.musicPlayer.currentItem removeObserver:self  forKeyPath:@"status"];
                _hadRemovePlayerItemStatusObserver = true;
            }
            [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
            
        }
        if (_timerObserver != nil) {
            [self.musicPlayer removeTimeObserver:_timerObserver];
            [_timerObserver invalidate];
        }
    }
    
}

/**
 asset load ready,start to play
 */
- (void)play {
    if (self.startPlayPoint == 0) {
        [self.musicPlayer play];
    }else {
        CGFloat totalMillisecond = self.musicPlayer.currentItem.duration.value / self.musicPlayer.currentItem.duration.timescale * 1000.0;
        CGFloat pointToSeek = self.startPlayPoint <= totalMillisecond ? self.startPlayPoint / 1000 : 0;
        [self.musicPlayer.currentItem seekToTime:CMTimeMake(pointToSeek, 1)];
        [self.musicPlayer play];
    }
}


/**
 release resource, remain self.musicPlayer to reuse
 */
- (void)clearResource {
    [self.musicPlayer replaceCurrentItemWithPlayerItem:nil];
    self.startPlayPoint = 0;
    self.suspendTime = kCMTimeZero;
    self.musicAsset = nil;
    self.musicPlayerItem = nil;
    self.timerObserver = nil;
    _hadRemovePlayerItemStatusObserver = false;
}

#pragma mark - KVO
/// 正常初始化资源流程 只会调用一次，也只让其调用一次，调用后移除status监听(原因: 前台暂停播放，进入后台再进入前台唤醒app，此方法又会被系统调用，导致自动播放)
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"status"]) {
        switch (self.musicPlayer.status) {
            case AVPlayerItemStatusReadyToPlay:
            {
                ZJLog(@"AVPlayerStatusReadyToPlay: 准备播放");
                [[doServiceContainer Instance].LogEngine WriteDebug:@"do_MultiAudio Initilaze Asset success: ready to play"];
                [self monitoringPlayback:self.musicPlayerItem];// 监听播放状态
                // 开始播放
                [self play];
                
            }
                break;
            case AVPlayerItemStatusFailed:
            {

                ZJLog(@"AVPlayerItemStatusFailed 加载失败");
                [self logErrorWithErrorType: musicURLAssetLoadFailed];
                [self musicPlayOccurError];
                [self p_currentItemRemoveObserver];
                [self clearResource];

            }
                break;
            case AVPlayerItemStatusUnknown:
            {
                [self logErrorWithErrorType: musicPlayErrorUnknow];
                ZJLog(@"AVPlayerItemStatusUnknown:未知状态");
                [self musicPlayOccurError];
                [self p_currentItemRemoveObserver];
                [self clearResource];

            }
                break;
            default:
                break;
        }
    }
    if (!_hadRemovePlayerItemStatusObserver) {
        [self.musicPlayer.currentItem removeObserver:self  forKeyPath:@"status"];
        _hadRemovePlayerItemStatusObserver = true;
    }
}

/**
 monitor play status

 @param playItem current playerItem
 */
- (void)monitoringPlayback: (AVPlayerItem*)playerItem {
    __weak typeof(self) weakSelf = self;
   self.timerObserver = [self.musicPlayer addPeriodicTimeObserverForInterval:CMTimeMake(1, 1) queue:NULL usingBlock:^(CMTime time) {
        CGFloat totalMillisecond = playerItem.duration.value / playerItem.duration.timescale * 1000.0;// 视频总长,毫秒
        CGFloat currentMilliSecond = playerItem.currentTime.value / playerItem.currentTime.timescale * 1000.0;// 计算当前在第几毫秒
        [weakSelf musicPlayProgress:currentMilliSecond totalTime:totalMillisecond];
    }];
}

#pragma  mark - event

/**
 finish play music: invoke when music finished play
 */
- (void)musicFinishedPlay {
    [self p_currentItemRemoveObserver];
    [self clearResource];
    doInvokeResult* _invokeResult = [[doInvokeResult alloc]init];
    [self.EventCenter FireEvent:@"playFinished":_invokeResult];
}

/**
  occur error when play music
 */
- (void)musicPlayOccurError {
    doInvokeResult* _invokeResult = [[doInvokeResult alloc]init];
    [self.EventCenter FireEvent:@"error" :_invokeResult];
}

/**
 call when music is playing(async), set currentTime and totalTime value

 @param currentTime the time music current play(eg: @"1000", unit: millisecond)
 @param totalTime the time music current play(eg: @"10000", unit: millisecond)
 */
- (void)musicPlayProgress:(CGFloat)currentTime totalTime:(CGFloat)totalTime {
    doInvokeResult* _invokeResult = [[doInvokeResult alloc]init];
    NSMutableDictionary *progerssDict = [NSMutableDictionary dictionaryWithCapacity:2];
    [progerssDict setObject:[NSString stringWithFormat:@"%.0f",currentTime] forKey:@"currentTime"];
    [progerssDict setObject:[NSString stringWithFormat:@"%.0f",totalTime] forKey:@"totalTime"];
    [_invokeResult SetResultNode:progerssDict];
    [self.EventCenter FireEvent:@"playProgress" :_invokeResult];
}

@end
