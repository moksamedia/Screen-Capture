/*

File: FrameCompressor.m

Abstract: Declares the implementation for the FrameCompressor abstract class
which wraps a QuickTime compression session and allows compression of
CVPixelBuffers using arbitrary codecs. The FrameCompressor is initialized
with the compression codec to use, the dimensions of the CVPixelBuffers
to be passed and compression session options (cannot be nil). Compressing
frames is achieved by calling -compressFrameOnSeparateThread and passing 
the CVPixelBuffer representing the frame along with optional timestamp 
and duration (pass -1.0 if undefined). When the frame is compressed, 
the -doneCompressingFrame method is called with the resulting encoded 
frame (this method is implemented by subclasses). Use the method -flushFrames 
to ensure no frames are pending for compression.

Version: 1.0

Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
Computer, Inc. ("Apple") in consideration of your agreement to the
following terms, and your use, installation, modification or
redistribution of this Apple software constitutes acceptance of these
terms.  If you do not agree with these terms, please do not use,
install, modify or redistribute this Apple software.

In consideration of your agreement to abide by the following terms, and
subject to these terms, Apple grants you a personal, non-exclusive
license, under Apple's copyrights in this original Apple software (the
"Apple Software"), to use, reproduce, modify and redistribute the Apple
Software, with or without modifications, in source and/or binary forms;
provided that if you redistribute the Apple Software in its entirety and
without modifications, you must retain this notice and the following
text and disclaimers in all such redistributions of the Apple Software. 
Neither the name, trademarks, service marks or logos of Apple Computer,
Inc. may be used to endorse or promote products derived from the Apple
Software without specific prior written permission from Apple.  Except
as expressly stated in this notice, no other rights or licenses, express
or implied, are granted by Apple herein, including but not limited to
any patent rights that may be infringed by your derivative works or by
other works in which the Apple Software may be incorporated.

The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.

IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

Copyright (C) 2007 Apple Inc. All Rights Reserved.

*/

#import <OpenGL/CGLMacro.h>

#import "FrameReader.h"
#import "FrameCompressor.h"
#import "MyController.h"

#define MOUSE_SIZE 40.0
#define MOUSE_FILE "Mouse-Pointer3"


static 	ICMCompressionSessionRef	mCompressionSession = NULL;
static 	ICMCompressionSessionRef	mCompressionSessionMouse = NULL;

// Called when image compression for a frame has completed. Compression
// is initiated by the ICMCompressionSessionEncodeFrame function. Once
// compression of the frame has completed, we add it to the track media for
// the movie.
static OSStatus FrameOutputCallback(void* encodedFrameOutputRefCon, ICMCompressionSessionRef session, OSStatus error, ICMEncodedFrameRef frame, void* reserved)
{
	if(error == noErr)
	{
		//Simply forward to the FrameMovieExporter instance
	
		[FrameMovieExporter doneCompressingFrame:frame];
	}
	
	return error;
}

static OSStatus FrameOutputCallbackMouse(void* encodedFrameOutputRefCon, ICMCompressionSessionRef session, OSStatus error, ICMEncodedFrameRef frame, void* reserved)
{
	if(error == noErr)
	{
		//Simply forward to the FrameMovieExporter instance
	
		[FrameMovieExporter doneCompressingFrameMouse:frame];
	}
	
	return error;
}

// During image compression this routine is called to indicate the status of
// the compression operation. We'll use this to determine when the buffer
// is free so we can mark the reader object as free/available.
static void SourceFrameTrackingCallback(void *sourceTrackingRefCon, ICMSourceTrackingFlags sourceTrackingFlags, void *sourceFrameRefCon, void *reserved)
{
    /*
    * Indicates that this is the last call for this sourceFrameRefCon.
    */
    if (sourceTrackingFlags & kICMSourceTracking_LastCall)
    {
    }

    /*
    * Indicates that the session is done with the source pixel buffer
    * and has released any reference to it that it had.
    */
	if (sourceTrackingFlags & kICMSourceTracking_ReleasedPixelBuffer)
	{
		FrameReader *readerObj = (FrameReader *)sourceTrackingRefCon;
		QueueController *frameQController = [readerObj queueController];
		
		// The compressor is finished with the reader object, so let's
		// put it back into the free queue so it can be used again
		[frameQController addItemToFreeQ:readerObj];
	}

}

// During image compression this routine is called to indicate the status of
// the compression operation. We'll use this to determine when the buffer
// is free so we can mark the reader object as free/available.
static void SourceFrameTrackingCallbackMouse(void *sourceTrackingRefCon, ICMSourceTrackingFlags sourceTrackingFlags, void *sourceFrameRefCon, void *reserved)
{
	if (sourceTrackingFlags & kICMSourceTracking_ReleasedPixelBuffer)
	{
		CVPixelBufferRelease(sourceTrackingRefCon);
	}
}

@interface FrameCompressor (PrivateMethods)

+(void)createSharedCompressionSession:(CodecType)codec pixelsWide:(unsigned)width pixelsHigh:(unsigned)height options:(ICMCompressionSessionOptionsRef)options compressionTimeScale:(TimeScale)timescale;
- (void)compressFrameSynchronized:(id)param;

@end

@implementation FrameCompressor (PrivateMethods)

// Create a single shared compression session for use with all subclasses
// of the FrameCompressor class. This compression session is used to
// compress screen reader frames so that they may be subsequently added
// to our movie.
+(void)createSharedCompressionSession:(CodecType)codec pixelsWide:(unsigned)width pixelsHigh:(unsigned)height options:(ICMCompressionSessionOptionsRef)options compressionTimeScale:(TimeScale)timescale
{
	ICMEncodedFrameOutputRecord		record = {FrameOutputCallback, NULL, NULL};
	ICMEncodedFrameOutputRecord		recordMouse = {FrameOutputCallbackMouse, NULL, NULL};
	OSStatus					theError;

	if (!mCompressionSession)
	{
		//Create compression session
		theError = ICMCompressionSessionCreate(kCFAllocatorDefault, width, height, codec, timescale, options, NULL, &record, &mCompressionSession);
		if(theError) 
		{
			NSLog(@"ICMCompressionSessionCreate() failed with error %i", theError);
		}	
		
	}
	
	if (!mCompressionSessionMouse)
	{
		//Create compression session
		theError = ICMCompressionSessionCreate(kCFAllocatorDefault, width, height, codec, timescale, options, NULL, &recordMouse, &mCompressionSessionMouse);
		if(theError) 
		{
			NSLog(@"ICMCompressionSessionCreate() - Mouse - failed with error %i", theError);
		}	
				
	}
}

// Compress a frame.
// This routine makes use of the @synchronized
// directive for locking the block of code which performs
// the compression operation.
// The @synchronized directive takes a single parameter
// which is the object you want to be used as the key
// for locking the code. The compiler then creates a
// mutex lock based on that object. Threads attempting
// to lock the same object block until the current 
// synchronized block finishes executing.
- (void)compressFrameSynchronized:(id)param
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	@synchronized([FrameCompressor class])
	{
		FrameReader	*frameReaderObj = (FrameReader *)param;
		
		// This blocks until the async texture transfer from
		// the GPU to system memory is complete.
		CVPixelBufferRef pixelBuffer = [frameReaderObj readScreenAsyncFinish];
		
		size_t pixBufferHeight = CVPixelBufferGetHeight(pixelBuffer);
		size_t pixBufferWidth = CVPixelBufferGetWidth(pixelBuffer);

		if (pixelBuffer)
		{

			OSStatus theError = -1;
			
			NSTimeInterval timestamp = [(FrameReader *)param bufferReadTime];
			NSTimeInterval duration = NAN;

			TimeScale compressionTimeScale = ICMCompressionSessionGetTimeScale (mCompressionSession);


			// compress the frame using our compression session
			ICMSourceTrackingCallbackRecord callBackRec = 
			{
				/*
				* The callback function pointer.
				*/
				SourceFrameTrackingCallback,

				/*
				* The callback's reference value.
				*/
				param // sourceTrackingRefCon
			};
			
			
			// DRAW MOUSE ON PRIMARY CAPTURE VIDEO
				
			/*
			CVPixelBufferLockBaseAddress(pixelBuffer, 0); // have to lock the base address before messing with the CVPixelBuffer
			
			void * baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer); // get the address of the data
			
			CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB); // create a colorspace
						
			CGContextRef bitmapContextRef = CGBitmapContextCreate(		// create the bitmap context for drawing mouse location
				baseAddress,
				pixBufferWidth,
				pixBufferHeight,
				8,	// bits per component
				CVPixelBufferGetBytesPerRow(pixelBuffer),
				colorSpace,
				kCGImageAlphaPremultipliedLast // alpha layer info
				);
				
			//CGContextSetRGBFillColor(bitmapContextRef, 1, 1, 1, 1); // set the color
			//CGContextFillRect(bitmapContextRef, CGRectMake ([frameReaderObj mouseX] - 4.0, [frameReaderObj mouseY] - 4.0, 8.0, 8.0)); // draw rectangle
			
			
			float mousePointerHeight = (float)CGImageGetHeight(mousePointerImageRef);
			float mousePointerWidth = (float)CGImageGetWidth(mousePointerImageRef);
			float ratio =  mousePointerWidth / mousePointerHeight;
			float pointerSize = MOUSE_SIZE;

			CGContextDrawImage(bitmapContextRef, CGRectMake([frameReaderObj mouseX], [frameReaderObj mouseY] - pointerSize, pointerSize * ratio, pointerSize), mousePointerImageRef);
			
			CGColorSpaceRelease(colorSpace); // release the colorspace
			CGContextRelease(bitmapContextRef); // release the bitmap context
			
			CVPixelBufferUnlockBaseAddress(pixelBuffer, 0); // unlock the base address
			*/

			

			// CREATE THE SECONDARY MOVIE WITH THE MOUSE MOVEMENTS

			if (createMouseMovie)
			{

				// Create the pixel buffer to hold the frame 
				CVPixelBufferRef mousePixBuffer;

				CVPixelBufferCreate(
							kCFAllocatorDefault, // use the default allocator
							pixBufferWidth, // frame width is same as the primary movie frame
							pixBufferHeight, // frame height ditto
							CVPixelBufferGetPixelFormatType(pixelBuffer), // just get the pixel format from the primary screen capture frame
							NULL,
							&mousePixBuffer // the pointer to our pixel buffer
							);

				// mouse movie callback for frame compression
				ICMSourceTrackingCallbackRecord callBackRecMouse = 
				{
					/*
					* The callback function pointer.
					*/
					SourceFrameTrackingCallbackMouse,

					/*
					* The callback's reference value.
					*/
					mousePixBuffer // sourceTrackingRefCon
				};
				 
				 
				// DRAW MOUSE FRAME FOR SECONDARY, MOUSE-ONLY VIDEO
				 
				CVPixelBufferLockBaseAddress(mousePixBuffer, 0); // have to lock the base address before messing with the CVPixelBuffer
				
				void * baseAddress = CVPixelBufferGetBaseAddress(mousePixBuffer); // get the address of the data
				
				CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB); // create a colorspace
							
				CGContextRef bitmapContextRef = CGBitmapContextCreate(		// create the bitmap context for drawing mouse location
					baseAddress,
					pixBufferWidth,
					pixBufferHeight,
					8,	// bits per component
					CVPixelBufferGetBytesPerRow(mousePixBuffer),
					colorSpace,
					kCGImageAlphaPremultipliedLast // alpha layer info
					);
					
				
				CGContextSetRGBFillColor(bitmapContextRef, 0, 0, 0, 0); // set the color
				CGContextFillRect(bitmapContextRef, CGRectMake(0,0,pixBufferWidth, pixBufferHeight)); // draw rectangle
			
				//CGContextSetRGBFillColor(bitmapContextRef, 1, 1, 1, 1); // set the color
				//CGContextFillRect(bitmapContextRef, CGRectMake ([frameReaderObj mouseX] - 4.0, [frameReaderObj mouseY] - 4.0, 8.0, 8.0)); // draw rectangle

				
				float mousePointerHeight = (float)CGImageGetHeight(mousePointerImageRef);
				float mousePointerWidth = (float)CGImageGetWidth(mousePointerImageRef);
				float ratio =  mousePointerWidth / mousePointerHeight;
				float pointerSize = MOUSE_SIZE;

				CGContextDrawImage(bitmapContextRef, CGRectMake([frameReaderObj mouseX], [frameReaderObj mouseY] - pointerSize, pointerSize * ratio, pointerSize), mousePointerImageRef);
				
			
				CGColorSpaceRelease(colorSpace); // release the colorspace
				CGContextRelease(bitmapContextRef); // release the bitmap context
				
				CVPixelBufferUnlockBaseAddress(mousePixBuffer, 0); // unlock the base address
		
				// FINISH DRAW MOUSE LOCATION
				
				// Present frames to the compression session. Encoded frames may or
				// may not be output before the function returns.
				theError = ICMCompressionSessionEncodeFrame(mCompressionSessionMouse, mousePixBuffer, 
							(timestamp >= 0.0 ? (SInt64)(timestamp * compressionTimeScale) : 0), 
							(duration >= 0.0 ? (SInt64)(duration * compressionTimeScale) : 0), 
							((timestamp >= 0.0 ? kICMValidTime_DisplayTimeStampIsValid : 0) | (duration >= 0.0 ? kICMValidTime_DisplayDurationIsValid : 0)), 
							NULL, &callBackRecMouse, (void *)NULL);

				if(theError)
				{
					NSLog(@"ICMCompressionSessionEncodeFrame() - Mouse - failed with error %i", theError);
				}

			
			}
			
						// Present frames to the compression session. Encoded frames may or
			// may not be output before the function returns.
			theError = ICMCompressionSessionEncodeFrame(mCompressionSession, pixelBuffer, 
						(timestamp >= 0.0 ? (SInt64)(timestamp * compressionTimeScale) : 0), 
						(duration >= 0.0 ? (SInt64)(duration * compressionTimeScale) : 0), 
						((timestamp >= 0.0 ? kICMValidTime_DisplayTimeStampIsValid : 0) | (duration >= 0.0 ? kICMValidTime_DisplayDurationIsValid : 0)), 
						NULL, &callBackRec, (void *)NULL);

			if(theError)
			{
				NSLog(@"ICMCompressionSessionEncodeFrame() failed with error %i", theError);
			}

			

		}
		else	// an error occurred
		{
			// we got an error, so put this reader object back into the free queue
			QueueController *frameQController = [frameReaderObj queueController];
			[frameQController addItemToFreeQ:frameReaderObj];
		}
	}

	[pool release];
}



@end

@implementation FrameCompressor


#pragma mark ---------- Initialization/Cleanup ----------

+ (void) initialize
{
	//Make sure QuickTime is initialized
	EnterMovies();
}

- (id) init
{
	//Make sure client goes through designated initializer
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}

// Initialize a FrameCompressor object with the specified codec,
// width/height, compressor options and timescale
- (id) initWithCodec:(CodecType)codec pixelsWide:(unsigned)width pixelsHigh:(unsigned)height options:(ICMCompressionSessionOptionsRef)options compressionTimeScale:(TimeScale)timescale
{	
	//Check parameters
	if((codec == 0) || (width == 0) || (height == 0) || (options == NULL) || timescale == 0) {
		[self release];
		return nil;
	}
	
	self = [super init];
	{
		createMouseMovie = [[NSUserDefaults standardUserDefaults] boolForKey:@"CreateMouseMovie"];
		
		CFURLRef url = CFBundleCopyResourceURL(CFBundleGetMainBundle(), CFSTR(MOUSE_FILE), CFSTR("png"), nil);
		CGDataProviderRef provider = CGDataProviderCreateWithURL (url); CFRelease(url);
		
		mousePointerImageRef = CGImageCreateWithPNGDataProvider(provider, NULL, true, kCGRenderingIntentDefault);
		CGDataProviderRelease(provider);

		
		[FrameCompressor createSharedCompressionSession:codec pixelsWide:width pixelsHigh:height options:options compressionTimeScale:timescale];
	}
	
	return self;
}


+ (id) alloc
{
	//Prevent direct allocation of this abstract class
	if(self == [FrameCompressor class])
	{
		[self doesNotRecognizeSelector:_cmd];
	}
	
	return [super alloc];
}


- (void) dealloc
{
	//Release resources
	if(mCompressionSession)
	{
		ICMCompressionSessionRelease(mCompressionSession);
		mCompressionSession = NULL;
	}
	
	//Release resources
	if(mCompressionSessionMouse)
	{
		ICMCompressionSessionRelease(mCompressionSessionMouse);
		mCompressionSessionMouse = NULL;
	}

	[super dealloc];
}

#pragma mark ---------- Compression Options ----------

// Display the compression dialog for the user, but first restore the settings
// from the previous user defaults
+ (ICMCompressionSessionOptionsRef) userOptions:(CodecType*)outCodecType frameRate:(double*)outFrameRate autosaveName:(NSString*)name showDialog:(BOOL)showDialog
{
	long						flags = scAllowEncodingWithCompressionSession;
	ICMMultiPassStorageRef			nullStorage = NULL;
	SCTemporalSettings			temporalSettings;
	SCSpatialSettings				spatialSettings;
	ComponentResult				theError;
	ICMCompressionSessionOptionsRef	options;
	ComponentInstance			component;
	QTAtomContainer				container;
	NSData*					data;
	Boolean					enable = true;
	
	
	//Open default compression dialog component
	component = OpenDefaultComponent(StandardCompressionType, StandardCompressionSubType);
	if(component == NULL) {
		NSLog(@"Compression component opening failed");
		return NULL;
	}
	
	SCSetInfo(component, scPreferenceFlagsType, &flags);
	
	//Restore compression settings from user defaults
	if([name length]) {
		data = [[NSUserDefaults standardUserDefaults] objectForKey:name];
		if(data) {
			container = NewHandle([data length]);
			if(container) {
				[data getBytes:*container];
				theError = SCSetSettingsFromAtomContainer(component, container);
				if(theError)
				{
					NSLog(@"SCSetSettingsFromAtomContainer() failed with error %i", theError);
					QTDisposeAtomContainer(container);
				}
			}
		}
	}
	
	if (showDialog)
	{
	
		//Display compression dialog to user
		theError = SCRequestSequenceSettings(component);
		if(theError) {
			if(theError != 1)
			NSLog(@"SCRequestSequenceSettings() failed with error %i", theError);
			CloseComponent(component);
			return NULL;
		}
		
		//Save compression settings in user defaults
		if([name length]) {
			theError = SCGetSettingsAsAtomContainer(component, &container);
			if(theError)
				NSLog(@"SCSetSettingsFromAtomContainer() failed with error %i", theError);
			else {
				data = [NSData dataWithBytes:*container length:GetHandleSize(container)];
				[[NSUserDefaults standardUserDefaults] setObject:data forKey:name];
				QTDisposeAtomContainer(container);
			}
		}
	
	}
	
	//Copy settings from compression dialog
	theError = SCCopyCompressionSessionOptions(component, &options);
	if(theError) {
		NSLog(@"SCCopyCompressionSessionOptions() failed with error %i", theError);
		CloseComponent(component);
		return NULL;
	}
	if(outCodecType) {
		SCGetInfo(component, scSpatialSettingsType, &spatialSettings);
		*outCodecType = spatialSettings.codecType;
	}
	if(outFrameRate) {
		SCGetInfo(component, scTemporalSettingsType, &temporalSettings);
		*outFrameRate = Fix2X(temporalSettings.frameRate);
	}
	CloseComponent(component);
	
	//Explicitely turn off multipass compression in case it was enabled by the user as we do not support it
	theError = ICMCompressionSessionOptionsSetProperty(options, kQTPropertyClass_ICMCompressionSessionOptions, kICMCompressionSessionOptionsPropertyID_MultiPassStorage, sizeof(ICMMultiPassStorageRef), &nullStorage);
	if( theError ) {
		NSLog(@"ICMCompressionSessionOptionsSetProperty() failed with error %i", theError);
	}

	// We must set this flag to enable P or B frames.
	theError = ICMCompressionSessionOptionsSetAllowTemporalCompression( options, true );
	if( theError ) {
		NSLog(@"ICMCompressionSessionOptionsSetAllowTemporalCompression() failed with error %i", theError);
	}
	
	// We must set this flag to enable B frames.
	theError = ICMCompressionSessionOptionsSetAllowFrameReordering( options, true );
	if( theError ) {
		NSLog(@"ICMCompressionSessionOptionsSetAllowFrameReordering() failed with error %i", theError);
	}
	
	// Set the maximum key frame interval, also known as the key frame rate.
	theError = ICMCompressionSessionOptionsSetMaxKeyFrameInterval( options, 30 );
	if( theError ) {
		NSLog(@"ICMCompressionSessionOptionsSetMaxKeyFrameInterval() failed with error %i", theError);
	}

	// This allows the compressor more flexibility (ie, dropping and coalescing frames).
	theError = ICMCompressionSessionOptionsSetAllowFrameTimeChanges( options, true );
	if( theError ) {
		NSLog(@"ICMCompressionSessionOptionsSetAllowFrameTimeChanges() failed with error %i", theError);
	}
	
	// We need durations when we store frames.
	theError = ICMCompressionSessionOptionsSetDurationsNeeded( options, true );
	if( theError ) {
		NSLog(@"ICMCompressionSessionOptionsSetDurationsNeeded() failed with error %i", theError);
	}

	// Enable the compressor to call the encoded-frame callback from a different thread. 
	theError = ICMCompressionSessionOptionsSetProperty(options, kQTPropertyClass_ICMCompressionSessionOptions, kICMCompressionSessionOptionsPropertyID_AllowAsyncCompletion, sizeof(Boolean), &enable);
	if( theError ) {
		NSLog(@"SCCopyCompressionSessionOptions() failed with error %i", theError);
	}

	return (ICMCompressionSessionOptionsRef)[(id)options autorelease];
}

#pragma mark ---------- Compression Methods ----------

// Call another routine to perform the compression on a separate thread
- (BOOL) compressFrameOnSeparateThread:(FrameReader *)frameReaderObj
{
	[NSThread detachNewThreadSelector:@selector(compressFrameSynchronized:) toTarget:self withObject:frameReaderObj];

	return YES;
}


// Force the compression session to complete encoding frames. 
+ (BOOL) flushFrames
{
	OSStatus	theError;

    // we must make sure only one thread at a time is accessing
    // the compression session
	@synchronized([FrameCompressor class])
	{
		//Flush pending frames in compression session
		theError = ICMCompressionSessionCompleteFrames(mCompressionSession, true, 0, 0);
		if(theError)
            NSLog(@"ICMCompressionSessionCompleteFrames() failed with error %i", theError);

		//Flush pending frames in compression session
		theError = ICMCompressionSessionCompleteFrames(mCompressionSessionMouse, true, 0, 0);
		if(theError)
            NSLog(@"ICMCompressionSessionCompleteFrames() failed with error %i", theError);
	}
	
	return (theError == noErr ? YES : NO);
}

// Placeholder for additional processing you may want to do
+ (void) doneCompressingFrame:(ICMEncodedFrameRef)frame
{
	//Do any additional processing here
}

+ (NSString*) codecNameForType:(CodecType)type
{
	CodecNameSpecListPtr listPtr;
	
	GetCodecNameList(&listPtr, 1);
	
	int count = listPtr->count;
	
	int i;
	
	for(i=0;i<count;i++)
	{
		if (listPtr->list[i].cType == type)
		{
			return (NSString*)CFStringCreateWithPascalString(NULL, listPtr->list[i].typeName, kCFStringEncodingMacRoman);
		}
	}
	
	return @"";
}

@end
