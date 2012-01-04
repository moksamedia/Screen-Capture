/*

File: FrameReader.m

Abstract: Implements the FrameReader class which allows you to grab frames
from an OpenGL context. The FrameReader is initialized with an OpenGL context 
to read from and the dimensions of the frames to grab. The class contains 
code for asynchronous texture fetching to grab the frames from the OpenGL 
context. Asynchronous texture fetching improves performance significantly. 
Frame grabbing is performed by calling -readScreenAsyncOnSeparateThread
for asynchronous capture.

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
#import "MyController.h"

#pragma mark ---------- Private Methods ----------

@interface FrameReader (PrivateReaderMethods)
- (void)readScreenAsyncSynchronized:(id)param;
- (void)flipBufferContents;
@end

@implementation FrameReader (PrivateReaderMethods)

// Initiate an asynchronous screen read operation.
// This routine makes use of the @synchronized
// directive for locking the block of code which initiates
// the read operation (for the reader object) and then
// places the reader object back into the "filled" queue
// so it's buffer data can be compressed later. 
//
// The @synchronized directive takes a single parameter
// which is the object you want to be used as the key
// for locking the code. The compiler then creates a
//  mutex lock based on that object. Threads attempting
//  to lock the same object block until the current 
// synchronized block finishes executing.
- (void) readScreenAsyncSynchronized:(id)param
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	@synchronized([FrameReader class])
	{
		// save current timestamp for use in compression
		mRecordTime = [NSDate timeIntervalSinceReferenceDate];
		mRecordTime = mRecordTime - mStartTime;	


		CGEventRef ourEvent = CGEventCreate(NULL);
		CGPoint point = CGEventGetLocation(ourEvent);
				
		CFRelease(ourEvent);
		
		mouseX = point.x;
		mouseY = mHeight - point.y;

		// copy screen buffer to texture, and start async texture
		// transfer to system memory
		BOOL success = [self readScreenAsyncBegin];
		if (success)
		{
			// Place this reader object into filled queue so it can be 
			// processed by the exporter thread
			[mQueueController addItemToFilledQ:self];
		}
	}
	
	[pool release];
}

// Flip the contents of the buffer to use the QuickTime
// coordinate system. This is necessary because OpenGL 
// uses coordinates that increase positively from the 
// origin (0,0) as you move up and to the right. QuickTime,
// on the other hand, puts the origin in the top left and
// coordinates increase positively as you move down and to
// the right.
-(void)flipBufferContents
{
	int				i;
	unsigned char*		src;
	unsigned char*		dst;
	unsigned char		temp[(mWidth * 4 + 63) & ~63];

	for(i = 0; i < mHeight/2; ++i) 
	{
		src = mBaseAddress + mBufferRowBytes * i;
		dst = mBaseAddress + mBufferRowBytes * (mHeight - 1 - i);
		bcopy(dst, temp, mWidth * 4);
		bcopy(src, dst, mWidth * 4);
		bcopy(temp, src, mWidth * 4);
	}

}

@end

@implementation FrameReader

 /* This FrameReader class in this sample is a generic readback 
 class which shows the following technique for readback: 
    - asynchronous texture fetching. 

 Although it works well for this sample, it could be optimized 
 by the application managing:

  * It's own state thus removing the need for the glGets....
  * Double-buffering the readback. This sample currently only uses 1 
  texture for readback.    

 For real asynchronous behavior, you need to double buffer as follows:

    glCopyTexSubImage -> texture 0
    glCopyTexSubImage -> texture 1
	    glGetTexImage -> texture 0
    glCopyTexSubImage -> texture 0
	    glGetTexImage -> texture 1
    glCopyTexSubImage -> texture 1

 For additional information, see the following documents:

 OpenGL Performance Optimizations : The Basics
 <http://developer.apple.com/technotes/tn2004/tn2093.html>

 OpenGL Programming Guide For Mac OS X
 <http://developer.apple.com/documentation/GraphicsImaging/Conceptual/OpenGL-MacProgGuide/index.html>
  */

#pragma mark ---------- Initialization/Cleanup ----------

- (id) init
{
	//Make sure client goes through designated initializer
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}

// Initialize a FrameReader object -- given an OpenGL context, screen 
// width & height values and a QueueController object
- (id) initWithOpenGLContext:(NSOpenGLContext*)context pixelsWide:(unsigned)width pixelsHigh:(unsigned)height queueController:(QueueController *)controller
{
	//IMPORTANT: We use the macros provided by <OpenGL/CGLMacro.h> which provide better performances and allows us not to bother with making sure the current context is valid
	CGLContextObj	cgl_ctx = [context CGLContextObj];
	GLint		save1,
                            save2,
                            save3,
                            save4;
	CVReturn			theError;
	NSMutableDictionary*	attributes;

	//Check parameters
	if((context == nil) || ((width == 0) || (height == 0))) {
		[self release];
		return nil;
	}
	
	if (self = [super init])
	{
		CGLLockContext(cgl_ctx);  // Thread lock OpenGL Context

		//Keep essential parameters around
		mQueueController = [controller retain];

		mGlContext = [context retain];
		mWidth = width;
		mHeight = height;
		
		attributes = [NSMutableDictionary dictionary];
		#if __BIG_ENDIAN__
			[attributes setObject:[NSNumber numberWithUnsignedInt:k32ARGBPixelFormat] forKey:(NSString*)kCVPixelBufferPixelFormatTypeKey];
		#else
			[attributes setObject:[NSNumber numberWithUnsignedInt:k32BGRAPixelFormat] forKey:(NSString*)kCVPixelBufferPixelFormatTypeKey];
		#endif
		[attributes setObject:[NSNumber numberWithUnsignedInt:width] forKey:(NSString*)kCVPixelBufferWidthKey];
		[attributes setObject:[NSNumber numberWithUnsignedInt:height] forKey:(NSString*)kCVPixelBufferHeightKey];
		//Create buffer pool to hold our frames
		theError = CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (CFDictionaryRef)attributes, &mBufferPool);
		if(theError != kCVReturnSuccess) 
		{
			NSLog(@"CVPixelBufferPoolCreate() failed with error %i", theError);
			[self release];
			return nil;
		}

		// Create pixel buffer from pixel buffer pool
		theError = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, mBufferPool, &mPixelBuffer);
		if(theError) {
			NSLog(@"CVPixelBufferPoolCreatePixelBuffer() failed with error %i", theError);
			return NULL;
		}
		
		theError = CVPixelBufferLockBaseAddress(mPixelBuffer, 0);
		if(theError) {
			NSLog(@"CVPixelBufferLockBaseAddress() failed with error %i", theError);
			return NULL;
		}
		mBaseAddress = CVPixelBufferGetBaseAddress(mPixelBuffer);
		mBufferRowBytes = CVPixelBufferGetBytesPerRow(mPixelBuffer);

		// Do setup for asynchronous texture reading
		
		// Create and configure the texture
		glGenTextures(1, &mTextureName);

		// For extra safety, save & restore OpenGL states that are changed
        
		glGetIntegerv(GL_TEXTURE_BINDING_RECTANGLE_EXT, &save1);
		/* Some hardware requires texture dimensions to be a power-of-two 
		before the hardware can upload the data using DMA. The rectangle 
		texture extension (ARB_texture_rectangle) was introduced to allow 
		texture targets for textures of any dimensions—that is, rectangle 
		textures (GL_TEXTURE_RECTANGLE_ARB). You need to use the rectangle 
		texture extension together with the Apple texture range extension 
		to ensure OpenGL uses DMA to access your texture data. These extensions
		allow you to bypass the OpenGL driver.
		*/
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, mTextureName);
		
		//Set the GL_TEXTURE_STORAGE_HINT_APPLE to GL_STORAGE_CACHED_APPLE or 
		//GL_STORAGE_SHARED_APPLE for requesting VRAM or AGP texturing respectively.
		glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_STORAGE_HINT_APPLE, GL_STORAGE_SHARED_APPLE);
		
		glGetIntegerv(GL_UNPACK_ALIGNMENT, &save2);
		glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
		glGetIntegerv(GL_UNPACK_ROW_LENGTH, &save3);
		glPixelStorei(GL_UNPACK_ROW_LENGTH, mBufferRowBytes / 4);
        
		// specify that our application retains storage for textures:
		glGetIntegerv(GL_UNPACK_CLIENT_STORAGE_APPLE, &save4);
		glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE);
        
		// define our texture
		glTexImage2D(GL_TEXTURE_RECTANGLE_ARB,0,GL_RGBA, mWidth,mHeight,0,GL_BGRA, 
					GL_UNSIGNED_INT_8_8_8_8_REV,
					mBaseAddress);
		// now restore settings
		glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, save4);
		glPixelStorei(GL_UNPACK_ROW_LENGTH, save3);
		glPixelStorei(GL_UNPACK_ALIGNMENT, save2);
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, save1);

		//Check for OpenGL errors
		theError = glGetError();
		if(theError) {
			NSLog(@"OpenGL texture creation failed (error 0x%04X)", theError);
			[self release];
			CGLUnlockContext(cgl_ctx); // Thread unlock
			return nil;
		}
		CGLUnlockContext(cgl_ctx); // Thread unlock
	}
	
	return self;
}

// Perform cleanup
- (void) dealloc
{
	//IMPORTANT: We use the macros provided by <OpenGL/CGLMacro.h> which provide better performances and allows us not to bother with making sure the current context is valid
	CGLContextObj	cgl_ctx = [mGlContext CGLContextObj];
	
	//Destroy resources
	if(mBufferPool)
		CVPixelBufferPoolRelease(mBufferPool);

	if (mPixelBuffer)
		CVPixelBufferRelease(mPixelBuffer);
	
	if(mTextureName)
		glDeleteTextures(1, &mTextureName);

	//Release context
	[mGlContext release];
	
	[super dealloc];
}


#pragma mark ---------- Reader methods ----------


// Perform asynchronous screen read operation on
// a separate thread (this is initiated by a call
// to the readScreenAsyncBegin method). 
// You will then need to call the readScreenAsyncFinish
// method to complete the asynchronous read.
- (void) readScreenAsyncOnSeparateThread
{
	[NSThread detachNewThreadSelector:@selector(readScreenAsyncSynchronized:) toTarget:self withObject:(id)nil];
}

// Start the asynchronous screen read operation. This is 
// accomplished by calls to glCopyTexSubImage2D followed
// by glFlush to initiate an asynchronous DMA transfer to
// system memory.
- (BOOL) readScreenAsyncBegin
{
	//IMPORTANT: We use the macros provided by <OpenGL/CGLMacro.h> which provide better performances and allows us not to bother with making sure the current context is valid
	CGLContextObj	cgl_ctx = [mGlContext CGLContextObj];
	CGLLockContext(cgl_ctx);
	GLenum		theError = GL_NO_ERROR;
	BOOL			success = YES;
	GLint			save1;

	//Copy OpenGL context pixels to our texture
	
	//Get the currently bound rectangle texture object 
	glGetIntegerv(GL_TEXTURE_BINDING_RECTANGLE_EXT, &save1);
	//Use our rectangle texture target
	glBindTexture(GL_TEXTURE_RECTANGLE_ARB, mTextureName);
	
	// glCopyTexSubImage2D replaces a rectangular portion of a 
	// two-dimensional texture image with pixels from the current
	// GL_READ_BUFFER (rather than from main memory, as
	// is the case for glTexSubImage2D). This call initiates an 
	// asynchronous DMA transfer to system memory the next time
	// a flush call is made. The CPU doesn't wait for this 
	// call to complete.
	glCopyTexSubImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, 0, 0, 0, 0, mWidth, mHeight);

	//Check for OpenGL errors
	theError = glGetError();
	if(theError != GL_NO_ERROR) {
		NSLog(@"OpenGL glCopyTexSubImage2D failed (error 0x%04X)", theError);
		success = NO;
	}
	
	// Initiate the async. DMA transfer.
    // Call glGetTexImage to complete the transfer to system memory.
	glFlush();	

	//Check for OpenGL errors
	theError = glGetError();
	if(theError != GL_NO_ERROR) {
		NSLog(@"OpenGL glFlush failed (error 0x%04X)", theError);
		success = NO;
	}

	//Restore saved rectangle texture object
	glBindTexture(GL_TEXTURE_RECTANGLE_ARB, save1);
	CGLUnlockContext(cgl_ctx);

	return (success);
}

// Completes the asynchronous screen read operation.
// This is accomplished by calling glGetTexImage which
// will copy the texture from AGP memory to system
// memory --  Note this call will wait (block) until 
// the transfer has completed.
-(CVPixelBufferRef)readScreenAsyncFinish
{
	//IMPORTANT: We use the macros provided by <OpenGL/CGLMacro.h> which provide better performances and allows us not to bother with making sure the current context is valid
	CGLContextObj	cgl_ctx = [mGlContext CGLContextObj];
	CGLLockContext(cgl_ctx);
	GLint			save1, save2, save3;
	GLenum			theError = GL_NO_ERROR;

	//Read pixels from current texture
	glGetIntegerv(GL_TEXTURE_BINDING_RECTANGLE_EXT, &save1);

	glBindTexture(GL_TEXTURE_RECTANGLE_ARB, mTextureName);
	glGetIntegerv(GL_PACK_ALIGNMENT, &save2);
	glPixelStorei(GL_PACK_ALIGNMENT, 4);
	glGetIntegerv(GL_PACK_ROW_LENGTH, &save3);

	glPixelStorei(GL_PACK_ROW_LENGTH, mBufferRowBytes / 4);

	// You should have previously called glCopyTexSubImage2D/glFlush to initiate
	// an asynchronous DMA transfer to system memory.
	
	// glGetTexImage actually copies the texture from AGP memory to system memory.
	// This is the synchronization point; it waits until the transfer is finished.
	glGetTexImage(GL_TEXTURE_RECTANGLE_ARB, 0, GL_BGRA, 
					GL_UNSIGNED_INT_8_8_8_8_REV,
					mBaseAddress);
                    
	//Check for OpenGL errors
	theError = glGetError();
	if(theError != GL_NO_ERROR) {
		NSLog(@"OpenGL glGetTexImage failed (error 0x%04X)", theError);
	}

	glPixelStorei(GL_PACK_ROW_LENGTH, save3);
	glPixelStorei(GL_PACK_ALIGNMENT, save2);
	glBindTexture(GL_TEXTURE_RECTANGLE_ARB, save1);
	 
	CGLUnlockContext(cgl_ctx);

	// flip buffer contents to use a coordinate system that QuickTime expects
	[self flipBufferContents];
		
	if (theError == GL_NO_ERROR)
	{
		return (mPixelBuffer);
	}
	else
	{
		return (NULL);
	}
}

- (unsigned)mHeight
{
	return mHeight;
}

- (float)mouseX
{
	return mouseX;
}

- (float)mouseY
{
	return mouseY;
}


#pragma mark ---------- Getters/Setters ----------

// Returns a time value indicating the length of the
// record operation
-(NSTimeInterval)bufferReadTime
{
	return mRecordTime;
}

// Set the start time for the screen read operation
-(void)setBufferReadTime:(NSTimeInterval)aStartTime
{
	mStartTime = aStartTime;
}

// Returns the QueueController object associated with
// this (FrameReader) object
-(QueueController *)queueController
{
	return mQueueController;
}

@end




