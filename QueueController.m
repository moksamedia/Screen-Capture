/*

File: QueueController.m

Abstract: Implementation file for the QueueController class. This class
acts as a controller/manager for the Queue class. When initialized, it
will create two Queue objects, a "free" queue and a "filled" queue. The
"free" queue contains objects that are available for use by the client. The
"filled" queue contains objects that have been "used" (it is up to the
client to define such usage). Objects may be added to both the "free" and
"filled" queues, and objects may be removed from both queues.

Version: 1.0

 Disclaimer: IMPORTANT:  This Apple software is supplied to you by 
 Apple Inc. ("Apple") in consideration of your agreement to the
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
 Neither the name, trademarks, service marks or logos of Apple Inc. 
 may be used to endorse or promote products derived from the Apple
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

#import "QueueController.h"
#import "Queue.h"
#import "FrameReader.h"


@implementation QueueController

- (id) init
{
	//Make sure client goes through designated initializer
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}

// Initialize a QueueController object with reader objects -- each
// of which has the specified OpenGL context and pixel width/height.
//
// Each QueueController object contains a "free" queue and
// a "filled" queue.
- (id) initWithReaderObjects:(unsigned)objectCount aContext:(NSOpenGLContext*)context pixelsWide:(unsigned)width pixelsHigh:(unsigned)height 
{
	if (self = [super init])
	{
		// initialize the "free" and "filled" queues
		mFreeQ = [[Queue alloc] init];
		mFilledQ = [[Queue alloc] init];

		mFreeQMutex = [[NSString alloc] initWithString:@"freeQMutex"];
		mFilledQMutex = [[NSString alloc] initWithString:@"filledQMutex"];

		// now fill the "free" queue with reader objects
		int i;
		for (i=0; i<objectCount; ++i)
		{
			FrameReader *readerObj;
			readerObj = [[FrameReader alloc] initWithOpenGLContext:context pixelsWide:width pixelsHigh:height queueController:self];
			if (readerObj)
			{
				[self addItemToFreeQ:readerObj];
				[readerObj release];
			}
		}
	}

	return self;
}

// Add the specified item to the "free" queue
-(void)addItemToFreeQ:(id)anItem
{
	@synchronized(mFreeQMutex)
	{
		[mFreeQ addItem:anItem];
	}
}

// Add the specified item to the "filled" queue
-(void)addItemToFilledQ:(id)anItem
{
	@synchronized(mFilledQMutex)
	{
		[mFilledQ addItem:anItem];
	}
}

// Removes the oldest item from the "free" queue
-(id)removeOldestItemFromFreeQ
{
	id anObject = nil;

	@synchronized(mFreeQMutex)
	{
		anObject = [mFreeQ returnAndRemoveOldest];
	}

	return (anObject);
}

// Remove the oldest item from the "filled" queue
-(id)removeOldestItemFromFilledQ
{
	id anObject = nil;

	@synchronized(mFilledQMutex)
	{
		anObject = [mFilledQ returnAndRemoveOldest];
	}

	return (anObject);
}

// Cleanup - free our queue resources
- (void) dealloc
{
	[super dealloc];

	[mFreeQ release];
	[mFilledQ release];
	
	[mFreeQMutex release];
	[mFilledQMutex release];	
}


@end
