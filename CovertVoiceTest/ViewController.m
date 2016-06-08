//
//  ViewController.m
//  CovertVoiceTest
//
//  Created by JustinYang on 6/8/16.
//  Copyright © 2016 JustinYang. All rights reserved.
//

#import "ViewController.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import <AVFoundation/AVFoundation.h>

#include "math.h"
#define handleError(error)  if(error){ NSLog(@"%@",error); exit(1);}

#define kSmaple     44100

#define kOutoutBus 0
#define kInputBus  1

typedef struct {
    
    BOOL                 isStereo;           // set to true if there is data in the audioDataRight member
    UInt32               frameCount;         // the total number of frames in the audio data
    UInt32               sampleNumber;       // the next audio sample to play
    UInt16              *audioDataLeft;     // the complete left (or mono) channel of audio data read from an audio file
    UInt16              *audioDataRight;    // the complete right channel of audio data read from an audio file
    
} SoundStruct, *SoundStructPtr;

//接收区数据为一个循环队列
#define kRawDataLen (512*100)
typedef struct {
    NSInteger font;
    NSInteger rear;
    SInt16   receiveRawData[kRawDataLen];
} RawData;


@interface ViewController ()
{
    AURenderCallbackStruct      _inputProc;
    AURenderCallbackStruct      _outputProc;
    AudioStreamBasicDescription _audioFormat;
    AudioStreamBasicDescription mAudioFormat;
    
    SoundStruct              _sendStructData;
    RawData                  _rawData;
    CGFloat                  _convertCos[1024];
}
@property (nonatomic,weak)   AVAudioSession *session;
@property (nonatomic,assign) AudioComponentInstance toneUnit;


@end

@implementation ViewController


static void CheckError(OSStatus error,const char *operaton){
    if (error==noErr) {
        return;
    }
    char errorString[20]={};
    *(UInt32 *)(errorString+1)=CFSwapInt32HostToBig(error);
    if (isprint(errorString[1])&&isprint(errorString[2])&&isprint(errorString[3])&&isprint(errorString[4])) {
        errorString[0]=errorString[5]='\'';
        errorString[6]='\0';
    }else{
        sprintf(errorString, "%d",(int)error);
    }
    fprintf(stderr, "Error:%s (%s)\n",operaton,errorString);
    exit(1);
}


- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    [self configAudio];
    
    memset(_convertCos, 0, 1024*sizeof(CGFloat));
    for (int i = 0; i < 1024; i++) {
        _convertCos[i] = cos(2*M_PI*200*i/kSmaple);
    }
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


/**
 *  被中断时，开始中断，停止音频输出，结束中断，恢复音频输出
 *
 *  @param noti <#noti description#>
 */
-(void)audioSessionInterruptHandle:(NSNotification *)noti{
    NSDictionary *dic = noti.userInfo;
    if ([dic[ AVAudioSessionInterruptionTypeKey] integerValue] == AVAudioSessionInterruptionTypeBegan) {
        AudioOutputUnitStop(_toneUnit);
    }else if ([dic[ AVAudioSessionInterruptionTypeKey] integerValue] == AVAudioSessionInterruptionTypeEnded) {
        [self.session setActive:YES error:nil];
    }
    
}

-(void)audioSessionRouteChangeHandle:(NSNotification *)noti{
    //为什么要先dispose _toneUnit，在新建一个
    if ([noti.userInfo[AVAudioSessionRouteChangeReasonKey] integerValue] ==
        AVAudioSessionRouteChangeReasonCategoryChange) {
        for (AVAudioSessionPortDescription* desc in [self.session.currentRoute outputs]) {
            if ([[desc portType] isEqualToString:AVAudioSessionPortHeadphones])
                return;
        }
        CheckError(AudioOutputUnitStop(_toneUnit), "couldn't start remote i/o unit");

    }

}

//const CGFloat Bb[] = {0.9635,   -3.8538,    5.7807,   -3.8538,    0.9635};
//const CGFloat Ba[] = { 1.0000,   -3.9255,    5.7794,   -3.7821,    0.9282};
const CGFloat Bb[] = { 0.8300,   -3.3200,    4.9800,   -3.3200,    0.8300};
const CGFloat Ba[] = { 1.0000,   -3.6278,    4.9512,   -3.0119,    0.6889};

OSStatus inputRenderTone(
                         void *inRefCon,
                         AudioUnitRenderActionFlags 	*ioActionFlags,
                         const AudioTimeStamp 		*inTimeStamp,
                         UInt32 						inBusNumber,
                         UInt32 						inNumberFrames,
                         AudioBufferList 			*ioData)

{
    
    ViewController *THIS=(__bridge ViewController*)inRefCon;
    
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0].mData = NULL;
    bufferList.mBuffers[0].mDataByteSize = 0;
    
    OSStatus status = AudioUnitRender(THIS->_toneUnit,
                                      ioActionFlags,
                                      inTimeStamp,
                                      kInputBus,
                                      inNumberFrames,
                                      &bufferList);
    
    
    SInt16 *rece = (SInt16 *)bufferList.mBuffers[0].mData;
    SInt16 *tmp = (SInt16 *)malloc(bufferList.mBuffers[0].mDataByteSize);
    memcpy(tmp, rece, bufferList.mBuffers[0].mDataByteSize);
    for (int i = 0; i < inNumberFrames; i++) {
        rece[i] = rece[i]*THIS->_convertCos[i];
//        //            y(i)=(b1*x(i)+b2*x(i-1)+b3*x(i-2)+b4*x(i-3)-a2*y(i-1)-a3*y(i-2)-a4*y(i-3));
//        if (i < 4) {
//            if (i == 1) {
//                rece[1]=Bb[0]*tmp[1]+Bb[1]*tmp[0]-Ba[1]*rece[0];
//            }
//            if (i == 2) {
//                rece[2]=Bb[0]*tmp[2]+Bb[1]*tmp[1]+Bb[2]*tmp[0] - \
//                Ba[1]*rece[1]-Ba[2]*rece[0];
//            }
//            if (i == 3) {
//                rece[3]=Bb[0]*tmp[3]+Bb[1]*tmp[2]+Bb[2]*tmp[1]+Bb[3]*tmp[0] -\
//                Ba[1]*rece[2]-Ba[2]*rece[1]-Ba[3]*rece[0];
//            }
//            
//        }else{
//            rece[i]=Bb[0]*tmp[i]+Bb[1]*tmp[i-1]+Bb[2]*tmp[i-2]+Bb[3]*tmp[i-3]+Bb[4]*tmp[i-4]-\
//            Ba[1]*rece[i-1]-Ba[2]*rece[i-2]-Ba[3]*rece[i-3]-Ba[4]*rece[i-4];
//        }
    }
    
    RawData *rawData = &THIS->_rawData;
    //距离最大位置还有mDataByteSize/2 那就直接memcpy,否则要一个一个字节拷贝
    if((rawData->rear+bufferList.mBuffers[0].mDataByteSize/2) <= kRawDataLen){
        memcpy((uint8_t *)&(rawData->receiveRawData[rawData->rear]), bufferList.mBuffers[0].mData, bufferList.mBuffers[0].mDataByteSize);
        rawData->rear = (rawData->rear+bufferList.mBuffers[0].mDataByteSize/2);
    }else{
        uint8_t *pIOdata = (uint8_t *)bufferList.mBuffers[0].mData;
        for (int i = 0; i < rawData->rear+bufferList.mBuffers[0].mDataByteSize; i+=2) {
            SInt16 data = pIOdata[i]<<8 | pIOdata[i+1];
            rawData->receiveRawData[rawData->rear] = data;
            rawData->rear = (rawData->rear+1)%kRawDataLen;
        }
    }
    
    return status;
}
OSStatus outputRenderTone(
                          void *inRefCon,
                          AudioUnitRenderActionFlags 	*ioActionFlags,
                          const AudioTimeStamp 		*inTimeStamp,
                          UInt32 						inBusNumber,
                          UInt32 						inNumberFrames,
                          AudioBufferList 			*ioData)

{
    ViewController *THIS=(__bridge ViewController*)inRefCon;
    
    SInt16 *outSamplesChannelLeft   = (SInt16 *)ioData->mBuffers[0].mData;
    RawData *rawData = &THIS->_rawData;
    for (UInt32 frameNumber = 0; frameNumber < inNumberFrames; ++frameNumber) {
        if (rawData->font != rawData->rear) {
            outSamplesChannelLeft[frameNumber] = (rawData->receiveRawData[rawData->font]);
            rawData->font = (rawData->font+1)%kRawDataLen;
            
        }
    }
    return 0;
}
- (void)configAudio
{
    
    UInt32 size;
    _inputProc.inputProc = inputRenderTone;
    _inputProc.inputProcRefCon = (__bridge void *)(self);
    _outputProc.inputProc = outputRenderTone;
    _outputProc.inputProcRefCon = (__bridge void *)(self);
    
    //对AudioSession的一些设置
    self.session = [AVAudioSession sharedInstance];
    //音频中断发生(被别的app中断等)
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionInterruptHandle:) name:AVAudioSessionInterruptionNotification object:self.session];
    
    NSError *error;
    [self.session setActive:YES error:&error];
    handleError(error);
    
    [self.session setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    handleError(error);
    //route变化监听
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionRouteChangeHandle:) name:AVAudioSessionRouteChangeNotification object:self.session];
    
    [self.session setPreferredIOBufferDuration:0.005 error:&error];
    handleError(error);
    [self.session setPreferredSampleRate:kSmaple error:&error];
    handleError(error);
    
    
    
    //    Obtain a RemoteIO unit instance
    AudioComponentDescription acd;
    acd.componentType = kAudioUnitType_Output;
    acd.componentSubType = kAudioUnitSubType_RemoteIO;
    acd.componentFlags = 0;
    acd.componentFlagsMask = 0;
    acd.componentManufacturer = kAudioUnitManufacturer_Apple;
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &acd);
    AudioComponentInstanceNew(inputComponent, &_toneUnit);
    
    //The Remote I/O unit, by default, has output enabled and input disabled
    //Enable input scope of input bus for recording.
    UInt32 enable = 1;
    //mic连接上scope_input的 element1
    AudioUnitSetProperty(_toneUnit,
                         kAudioOutputUnitProperty_EnableIO,
                         kAudioUnitScope_Input,
                         kInputBus,
                         &enable,
                         sizeof(enable));
    AudioUnitSetProperty(_toneUnit,
                         kAudioOutputUnitProperty_EnableIO,
                         kAudioUnitScope_Output,
                         kOutoutBus, &enable, sizeof(enable));
    
    
    CheckError(AudioUnitSetProperty(_toneUnit, kAudioOutputUnitProperty_SetInputCallback,
                                    kAudioUnitScope_Global, kInputBus,
                                    &_inputProc, sizeof(_inputProc)),
               "couldnt set remote i/o render callback for input");
    
    CheckError(AudioUnitSetProperty(_toneUnit, kAudioUnitProperty_SetRenderCallback,
                                    kAudioUnitScope_Global, kOutoutBus,
                                    &_outputProc, sizeof(_outputProc)),
               "couldnt set remote i/o render callback for output");
    
    mAudioFormat.mSampleRate=kSmaple;//采样率（立体声＝8000）
    mAudioFormat.mFormatID=kAudioFormatLinearPCM;//PCM格式
    mAudioFormat.mFormatFlags        = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    mAudioFormat.mFramesPerPacket    = 1;//每个数据包多少帧
    mAudioFormat.mChannelsPerFrame   = 2/2;//1单声道，2立体声
    mAudioFormat.mBitsPerChannel     = 16;//语音每采样点占用位数
    mAudioFormat.mBytesPerFrame      = mAudioFormat.mBitsPerChannel*mAudioFormat.mChannelsPerFrame/8;//每帧的bytes数
    mAudioFormat.mBytesPerPacket     = mAudioFormat.mBytesPerFrame*mAudioFormat.mFramesPerPacket;//每个数据包的bytes总数，每帧的bytes数＊每个数据包的帧数
    mAudioFormat.mReserved           = 0;
    
    CheckError(AudioUnitSetProperty(_toneUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, kOutoutBus, &mAudioFormat, sizeof(mAudioFormat)), "couldn't set the remote I/O unit's output client format");
    CheckError(AudioUnitSetProperty(_toneUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, kInputBus, &mAudioFormat, sizeof(mAudioFormat)), "couldn't set the remote I/O unit's input client format");
    
    CheckError(AudioUnitInitialize(_toneUnit), "couldn't initialize the remote I/O unit");
    //Obtain a RemoteIO unit instance
    UInt32 maxFPSt;
    size = sizeof(maxFPSt);
    CheckError(AudioUnitGetProperty(_toneUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFPSt, &size), "couldn't get the remote I/O unit's max frames per slice");
    //Create an audio file for recording
    
    
    CheckError(AudioOutputUnitStart(_toneUnit), "couldn't start remote i/o unit");
    size = sizeof(mAudioFormat);
    CheckError(AudioUnitGetProperty(_toneUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output,1, &mAudioFormat,&size), "couldn't get the remote I/O unit's output client format");
}
- (IBAction)covertHandle:(id)sender {
    
}

@end
