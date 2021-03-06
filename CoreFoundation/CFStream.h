/* Copyright (c) 2008-2009 Christopher J. W. Lloyd

Permission is hereby granted,free of charge,to any person obtaining a copy of this software and associated documentation files (the "Software"),to deal in the Software without restriction,including without limitation the rights to use,copy,modify,merge,publish,distribute,sublicense,and/or sell copies of the Software,and to permit persons to whom the Software is furnished to do so,subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS",WITHOUT WARRANTY OF ANY KIND,EXPRESS OR IMPLIED,INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,DAMAGES OR OTHER LIABILITY,WHETHER IN AN ACTION OF CONTRACT,TORT OR OTHERWISE,ARISING FROM,OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */


typedef struct __NSStream       *CFStreamRef;
typedef struct __NSInputStream  *CFReadStreamRef;
typedef struct __NSOutputStream *CFWriteStreamRef;

#import <CoreFoundation/CFBase.h>
#import <CoreFoundation/CFRunLoop.h>
#import <CoreFoundation/CFSocket.h>
#import <CoreFoundation/CFURL.h>
#import <CoreFoundation/CFError.h>

typedef enum {
   kCFStreamEventNone             =0,
   kCFStreamEventOpenCompleted    =(1<<0),
   kCFStreamEventHasBytesAvailable=(1<<1),
   kCFStreamEventCanAcceptBytes   =(1<<2),
   kCFStreamEventErrorOccurred    =(1<<3),
   kCFStreamEventEndEncountered   =(1<<4),
} CFStreamEventType;

typedef enum {
   kCFStreamErrorDomainCustom     =-1,
   kCFStreamErrorDomainPOSIX      = 1,
   kCFStreamErrorDomainMacOSStatus= 2,
} CFStreamErrorDomain;

typedef void (*CFReadStreamClientCallBack)(CFReadStreamRef self,CFStreamEventType event,void *info);
typedef void (*CFWriteStreamClientCallBack)(CFWriteStreamRef self,CFStreamEventType event,void *info);

typedef struct {
   CFStreamErrorDomain domain;
   CFInteger           error;
} CFStreamError;

typedef struct {
   CFIndex                            version;
   void                              *info;
   CFAllocatorRetainCallBack          retain;
   CFAllocatorReleaseCallBack         release;
   CFAllocatorCopyDescriptionCallBack copyDescription;
} CFStreamClientContext;

typedef enum {
   kCFStreamStatusNotOpen=0,
   kCFStreamStatusOpening=1,
   kCFStreamStatusOpen   =2,
   kCFStreamStatusReading=3,
   kCFStreamStatusWriting=4,
   kCFStreamStatusAtEnd  =5,
   kCFStreamStatusClosed =6,
   kCFStreamStatusError  =7,
} CFStreamStatus;

COREFOUNDATION_EXPORT const CFInteger kCFStreamErrorDomainNetDB;
COREFOUNDATION_EXPORT const CFInteger kCFStreamErrorDomainNetServices;
COREFOUNDATION_EXPORT const CFInteger kCFstreamErrorDomainMach;
COREFOUNDATION_EXPORT const CFInteger kCFStreamErrorDomainFTP;
COREFOUNDATION_EXPORT const CFInteger kCFStreamErrorDomainHTTP;
COREFOUNDATION_EXPORT const CFInteger kCFStreamErrorDomainSOCKS;
COREFOUNDATION_EXPORT const CFInteger kCFStreamErrorDomainSystemConfiguration;
COREFOUNDATION_EXPORT const CFInteger kCFStreamErrorDomainSSL;

COREFOUNDATION_EXPORT const CFStringRef kCFStreamPropertyFileCurrentOffset;
COREFOUNDATION_EXPORT const CFStringRef kCFStreamPropertyAppendToFile;
COREFOUNDATION_EXPORT const CFStringRef kCFStreamPropertyDataWritten;
COREFOUNDATION_EXPORT const CFStringRef kCFStreamPropertySocketNativeHandle;
COREFOUNDATION_EXPORT const CFStringRef kCFStreamPropertySocketRemoteHostName;
COREFOUNDATION_EXPORT const CFStringRef kCFStreamPropertySocketRemotePortNumber;

void CFStreamCreateBoundPair(CFAllocatorRef allocator,CFReadStreamRef *readStream,CFWriteStreamRef *writeStream,CFIndex bufferSize);
void CFStreamCreatePairWithPeerSocketSignature(CFAllocatorRef allocator,const CFSocketSignature *signature,CFReadStreamRef *readStream,CFWriteStreamRef *writeStream);
void CFStreamCreatePairWithSocket(CFAllocatorRef allocator,CFSocketNativeHandle sock,CFReadStreamRef *readStream,CFWriteStreamRef *writeStream);
void CFStreamCreatePairWithSocketToHost(CFAllocatorRef allocator,CFStringRef host,CFUInteger port,CFReadStreamRef *readStream,CFWriteStreamRef *writeStream);
// ReadStream

CFTypeID        CFReadStreamGetTypeID(void);

CFReadStreamRef CFReadStreamCreateWithBytesNoCopy(CFAllocatorRef allocator,const uint8_t *bytes,CFIndex length,CFAllocatorRef bytesDeallocator);
CFReadStreamRef CFReadStreamCreateWithFile(CFAllocatorRef allocator,CFURLRef url);

Boolean         CFReadStreamSetClient(CFReadStreamRef self,CFOptionFlags events,CFReadStreamClientCallBack callback,CFStreamClientContext *context);

CFTypeRef       CFReadStreamCopyProperty(CFReadStreamRef self,CFStringRef key);
Boolean         CFReadStreamSetProperty(CFReadStreamRef self,CFStringRef key,CFTypeRef value);

const uint8_t * CFReadStreamGetBuffer(CFReadStreamRef self,CFIndex limit,CFIndex *available);
Boolean         CFReadStreamOpen(CFReadStreamRef self);
void            CFReadStreamClose(CFReadStreamRef self);
Boolean         CFReadStreamHasBytesAvailable(CFReadStreamRef self);
CFIndex         CFReadStreamRead(CFReadStreamRef self,uint8_t *bytes,CFIndex length);

CFErrorRef      CFReadStreamCopyError(CFReadStreamRef self);
CFStreamError   CFReadStreamGetError(CFReadStreamRef self);
CFStreamStatus  CFReadStreamGetStatus(CFReadStreamRef self);

void            CFReadStreamScheduleWithRunLoop(CFReadStreamRef self,CFRunLoopRef runLoop,CFStringRef mode);
void            CFReadStreamUnscheduleFromRunLoop(CFReadStreamRef self,CFRunLoopRef runLoop,CFStringRef mode);

// Write Stream

CFTypeID         CFWriteStreamGetTypeID(void);

CFWriteStreamRef CFWriteStreamCreateWithAllocatedBuffers(CFAllocatorRef allocator,CFAllocatorRef bufferAllocator);
CFWriteStreamRef CFWriteStreamCreateWithBuffer(CFAllocatorRef allocator,uint8_t *bytes,CFIndex capacity);
CFWriteStreamRef CFWriteStreamCreateWithFile(CFAllocatorRef allocator,CFURLRef url);

Boolean          CFWriteStreamSetClient(CFWriteStreamRef self,CFOptionFlags events,CFWriteStreamClientCallBack callback,CFStreamClientContext *context);

CFTypeRef        CFWriteStreamCopyProperty(CFWriteStreamRef self,CFStringRef key);
Boolean          CFWriteStreamSetProperty(CFWriteStreamRef self,CFStringRef key,CFTypeRef value);

Boolean          CFWriteStreamOpen(CFWriteStreamRef self);
void             CFWriteStreamClose(CFWriteStreamRef self);
Boolean          CFWriteStreamCanAcceptBytes(CFWriteStreamRef self);
CFIndex          CFWriteStreamWrite(CFWriteStreamRef self,const uint8_t *bytes,CFIndex length);

CFErrorRef       CFWriteStreamCopyError(CFReadStreamRef self);
CFStreamError    CFWriteStreamGetError(CFWriteStreamRef self);
CFStreamStatus   CFWriteStreamGetStatus(CFWriteStreamRef self);

void             CFWriteStreamScheduleWithRunLoop(CFWriteStreamRef self,CFRunLoopRef runLoop,CFStringRef mode);
void             CFWriteStreamUnscheduleFromRunLoop(CFWriteStreamRef self,CFRunLoopRef runLoop,CFStringRef mode);

