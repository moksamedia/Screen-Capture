/*

File: FrameMovieExporter.m

Abstract: Defines the implementation for the FrameMovieExporter class (a subclass
of FrameCompressor) which allows to save series of CVPixelBuffers as a
QuickTime movie file. The FrameMovieExporter is initialized with the path
to the destination movie file (any pre-existing file at that path will be
overwritten), the compression codec to use, the dimensions of the
CVPixelBuffers to be passed and compression session options (cannot be
nil - see FrameCompressor.h for more information about those options).
Appending frames to the movie file is performed by simply calling
-exportFrame: and passing a CVPixelBuffer along with a timestamp expressed
in seconds.

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

#import "FrameMovieExporter.h"

#define kTimeScale		1000000

static	Movie			mMovie=NULL;
static	DataHandler		mDataHandler=NULL;
static	Track			mTrack=NULL;
static	Media			mMedia=NULL;

static	Movie			mMovieMouse=NULL;
static	DataHandler		mDataHandlerMouse=NULL;
static	Track			mTrackMouse=NULL;
static	Media			mMediaMouse=NULL;


@interface FrameMovieExporter (PrivateMethods)
+(void)createSharedMovie:(NSString*)path pixelsWide:(unsigned)width pixelsHigh:(unsigned)height movieTimeScale:(TimeScale)timescale;
+(void)writeAndCloseMovie;
@end

@implementation FrameMovieExporter (PrivateMethods)

// Write any/all data to the movie and close the movie file
+(void)writeAndCloseMovie
{
	OSErr	theError;

	[FrameMovieExporter flushFrames];

	@synchronized([FrameMovieExporter class])
	{
		if(mMedia) 
		{
			//Make sure all frames have been processed by the compressor

			//End media editing
			theError = EndMediaEdits(mMedia);
			if(theError)
			NSLog(@"EndMediaEdits() failed with error %i", theError);
			
			theError = ExtendMediaDecodeDurationToDisplayEndTime(mMedia, NULL);
			if(theError)
			NSLog(@"ExtendMediaDecodeDurationToDisplayEndTime() failed with error %i", theError);
			
			//Add media to track
			theError = InsertMediaIntoTrack(mTrack, 0, 0, GetMediaDisplayDuration(mMedia), fixed1);
			if(theError)
			NSLog(@"InsertMediaIntoTrack() failed with error %i", theError);
			
			//Write movie
			theError = AddMovieToStorage(mMovie, mDataHandler);
			if(theError)
			NSLog(@"AddMovieToStorage() failed with error %i", theError);
		}
		
		//Close movie file
		if(mDataHandler)
		{
			CloseMovieStorage(mDataHandler);
		}
		if(mMovie)
		{
			DisposeMovie(mMovie);
		}
		
		mMovie=NULL;
		mDataHandler=NULL;
		mTrack=NULL;
		mMedia=NULL;
		
		
		if (createMouseMovie)
		{
		
			if(mMediaMouse) 
			{
				//Make sure all frames have been processed by the compressor

				//End media editing
				theError = EndMediaEdits(mMediaMouse);
				if(theError)
				NSLog(@"EndMediaEdits() failed with error %i", theError);
				
				theError = ExtendMediaDecodeDurationToDisplayEndTime(mMediaMouse, NULL);
				if(theError)
				NSLog(@"ExtendMediaDecodeDurationToDisplayEndTime() failed with error %i", theError);
				
				//Add media to track
				theError = InsertMediaIntoTrack(mTrackMouse, 0, 0, GetMediaDisplayDuration(mMediaMouse), fixed1);
				if(theError)
				NSLog(@"InsertMediaIntoTrack() failed with error %i", theError);
				
				//Write movie
				theError = AddMovieToStorage(mMovieMouse, mDataHandlerMouse);
				if(theError)
				NSLog(@"AddMovieToStorage() failed with error %i", theError);
			}
			
			//Close movie file
			if(mDataHandlerMouse)
			{
				CloseMovieStorage(mDataHandlerMouse);
			}
			if(mMovieMouse)
			{
				DisposeMovie(mMovieMouse);
			}
			
			mMovieMouse=NULL;
			mDataHandlerMouse=NULL;
			mTrackMouse=NULL;
			mMediaMouse=NULL;
		
		}
		
	}

}

// Create a single movie to be shared by all subclasses of
// FrameMovieExporter. A single video track will be added to
// the movie and the movie will be prepared for editing so
// frame data can added thereafter.
+(void)createSharedMovie:(NSString*)path pixelsWide:(unsigned)width pixelsHigh:(unsigned)height movieTimeScale:(TimeScale)timescale
{
	// Share a single movie for all instances of this class
	if (mMovie == NULL)
	{
		OSErr			theError = noErr;
		Handle		dataRef;
		OSType		dataRefType;

		//Create movie file
		theError = QTNewDataReferenceFromFullPathCFString((CFStringRef)path, kQTNativeDefaultPathStyle, 0, &dataRef, &dataRefType);
		if(theError) {
			NSLog(@"QTNewDataReferenceFromFullPathCFString() failed with error %i", theError);
			[self release];
		}
		// Create a movie for this file (data ref)
		theError = CreateMovieStorage(dataRef, dataRefType, 'TVOD', smCurrentScript, createMovieFileDeleteCurFile, &mDataHandler, &mMovie);
		if(theError) {
			NSLog(@"CreateMovieStorage() failed with error %i", theError);
			[self release];
		}

		// dispose of the data reference handle - we no longer need it
		DisposeHandle(dataRef);
		
		//Add track
		mTrack = NewMovieTrack(mMovie, width << 16, height << 16, 0);
		theError = GetMoviesError();
		if(theError) {
			NSLog(@"NewMovieTrack() failed with error %i", theError);
			[self release];
		}
		
		//Create track media
		mMedia = NewTrackMedia(mTrack, VideoMediaType, timescale, 0, 0);
		theError = GetMoviesError();
		if(theError) {
			NSLog(@"NewTrackMedia() failed with error %i", theError);
			[self release];
		}
		
		//Prepare media for editing
		theError = BeginMediaEdits(mMedia);
		if(theError) {
			NSLog(@"BeginMediaEdits() failed with error %i", theError);
			[self release];
		}
	}
	
		// Share a single movie for all instances of this class
	if (mMovieMouse == NULL && createMouseMovie)
	{
		OSErr		theError = noErr;
		Handle		dataRef;
		OSType		dataRefType;

		NSString * pathMouse = [NSString stringWithFormat:@"%@_MOUSE.%@", [path stringByDeletingPathExtension], [path pathExtension]];
		//NSLog(@"mouseMovementFileName = %@", mouseMovementFileName);

		//Create movie file
		theError = QTNewDataReferenceFromFullPathCFString((CFStringRef)pathMouse, kQTNativeDefaultPathStyle, 0, &dataRef, &dataRefType);
		if(theError) {
			NSLog(@"QTNewDataReferenceFromFullPathCFString() failed with error %i", theError);
			[self release];
		}
		// Create a movie for this file (data ref)
		theError = CreateMovieStorage(dataRef, dataRefType, 'TVOD', smCurrentScript, createMovieFileDeleteCurFile, &mDataHandlerMouse, &mMovieMouse);
		if(theError) {
			NSLog(@"CreateMovieStorage() failed with error %i", theError);
			[self release];
		}

		// dispose of the data reference handle - we no longer need it
		DisposeHandle(dataRef);
		
		//Add track
		mTrackMouse = NewMovieTrack(mMovieMouse, width << 16, height << 16, 0);
		theError = GetMoviesError();
		if(theError) {
			NSLog(@"NewMovieTrack() failed with error %i", theError);
			[self release];
		}
		
		//Create track media
		mMediaMouse = NewTrackMedia(mTrackMouse, VideoMediaType, timescale, 0, 0);
		theError = GetMoviesError();
		if(theError) {
			NSLog(@"NewTrackMedia() failed with error %i", theError);
			[self release];
		}
		
		//Prepare media for editing
		theError = BeginMediaEdits(mMediaMouse);
		if(theError) {
			NSLog(@"BeginMediaEdits() failed with error %i", theError);
			[self release];
		}
	}
}

@end


@implementation FrameMovieExporter



#pragma mark ---------- initialization/cleanup ----------

- (id) initWithCodec:(CodecType)codec pixelsWide:(unsigned)width pixelsHigh:(unsigned)height options:(ICMCompressionSessionOptionsRef)options compressionTimeScale:(TimeScale)timescale
{
	//Make sure client goes through designated initializer
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}

// Initialize a codec and exporter
- (id) initWithPath:(NSString*)path codec:(CodecType)codec pixelsWide:(unsigned)width pixelsHigh:(unsigned)height options:(ICMCompressionSessionOptionsRef)options
{
	//Check parameters
	if(![path length]) {
		[self release];
		return nil;
	}
	
	//Initialize super class
	if(self = [super initWithCodec:codec pixelsWide:width pixelsHigh:height options:options compressionTimeScale:kTimeScale]) 
	{
		[FrameMovieExporter createSharedMovie:path pixelsWide:width pixelsHigh:height movieTimeScale:kTimeScale];
	}
	
	return self; 
}

- (void) dealloc
{
	[FrameMovieExporter writeAndCloseMovie];
	
	[super dealloc];
}

#pragma mark ---------- Export ----------

// Compress the frame (on a separate thread)
- (BOOL) exportFrame:(FrameReader *)frameReaderObj 
{
	return [super compressFrameOnSeparateThread:frameReaderObj];
}

// Called by the FrameCompressor object when compression for a given frame
// buffer has completed. The compressed frame is then added to the track
// media.
+(void) doneCompressingFrame:(ICMEncodedFrameRef)frame
{
	@synchronized([FrameMovieExporter class])
	{
		if (mMedia)
		{
			OSErr	theError;
			
			//Add frame to track media - Ignore the last frame which will have a duration of 0
			if(ICMEncodedFrameGetDecodeDuration(frame) > 0) 
			{
                //  Adds sample data and description from an encoded frame to a media.
				theError = AddMediaSampleFromEncodedFrame(mMedia, frame, NULL);
				if(theError)
                    NSLog(@"AddMediaSampleFromEncodedFrame() failed with error %i", theError);
			}
		}
	}
}

+(void) doneCompressingFrameMouse:(ICMEncodedFrameRef)frame
{
	@synchronized([FrameMovieExporter class])
	{
		if (mMediaMouse)
		{
			OSErr	theError;
			
			//Add frame to track media - Ignore the last frame which will have a duration of 0
			if(ICMEncodedFrameGetDecodeDuration(frame) > 0) 
			{
                //  Adds sample data and description from an encoded frame to a media.
				theError = AddMediaSampleFromEncodedFrame(mMediaMouse, frame, NULL);
				if(theError)
                    NSLog(@"AddMediaSampleFromEncodedFrame() failed with error %i", theError);
			}
		}

	}
}


@end


