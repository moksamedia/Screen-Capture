
#import "MyController.h"
#import "FrameMovieExporter.h"

// Number of reader objects used by the program at once.
// Each reader object is designed to read and hold a 
// single screen frame buffer.
#define kNumReaderObjects		20


// This is the CoreVideo display link callback. The display link invokes
// this callback whenever it wants you to output a frame. In our case, 
// we call our displayLinkCallback to perform readback of the screen using
// OpenGL
static CVReturn MyRenderCallback(CVDisplayLinkRef displayLink, 
					 const CVTimeStamp *inNow, 
					 const CVTimeStamp *inOutputTime, 
					 CVOptionFlags flagsIn, 
					 CVOptionFlags *flagsOut, 
					void *displayLinkContext)
{
	return [(MyController *)displayLinkContext displayLinkCallback:inOutputTime flagsOut:flagsOut];
}


@implementation MyController

#pragma mark ---------- Initialization/Termination ----------

// Setup notifications to let us know when application is finished
// launching so we can use this time to create the OpenGL context
// used to render, and to let us know when the app. is terminating
// so  we can perform cleanup
-(id)init
{
	if (self = [super init])
	{
		mGLContext = nil;
		mExporterObj = nil;
		
		isRecordingNow = FALSE;
		
		startTime = nil;
		
		[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(applicationDidFinishLaunching:)
			name:@"NSApplicationDidFinishLaunchingNotification" object:NSApp];

		[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(applicationWillTerminate:)
			name:@"NSApplicationWillTerminateNotification" object:NSApp];
	}
	
	return self;
}

// Perform cleanup when the application terminates
- (void) applicationWillTerminate:(NSNotification*)notification
{
	// Cancel render timer
	if (mRenderDurationTimer)
	{
		[mRenderDurationTimer invalidate];
		[mRenderDurationTimer release];
	}

	// Cancel any current renderings
	[self stopRecording:nil];
}

// Create OpenGL context used to render
- (void) applicationDidFinishLaunching:(NSNotification*)notification
{
	NSOpenGLPixelFormatAttribute attributes[] = {
			NSOpenGLPFAFullScreen,
			NSOpenGLPFAScreenMask,
				CGDisplayIDToOpenGLDisplayMask(kCGDirectMainDisplay),
			(NSOpenGLPixelFormatAttribute) 0
	};

	mGLPixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];
	NSAssert( mGLPixelFormat != nil, @"No Full-Screen Renderer");
	if (!mGLPixelFormat) return;

	//Create OpenGL context used to render
	mGLContext = [[NSOpenGLContext alloc] initWithFormat:mGLPixelFormat shareContext:nil];
	NSAssert( mGLContext != nil, @"NSOpenGLContext initialization failure");	
	[mGLContext makeCurrentContext];
	[mGLContext setFullScreen];

	CGDirectDisplayID displayID = CGMainDisplayID();
	NSAssert( displayID != nil, @"CGMainDisplayID failure");
	if (displayID)
	{
		mDisplayRect = CGDisplayBounds(displayID);
	}


	if ([self createMouseMovie])
	{
		[createMouseMovieMenuItem setState:NSOnState];
	}
	else
	{
		[createMouseMovieMenuItem setState:NSOffState];	
	}
	
	CodecType					codec;
	double					framerate;
	[FrameCompressor userOptions:&codec frameRate:&framerate autosaveName:@"CompressionDialogSettings" showDialog:FALSE];
	
	NSString * codecName = [FrameCompressor codecNameForType:codec];

	[codecAndFrameRateMenuItem setTitle:[NSString stringWithFormat:@"( %@ - %0.2f )", codecName, framerate]];

	[codecAndFrameRateMenuItem setEnabled:FALSE];

}

- (IBAction)startStopRecording:(id)sender
{
	if (isRecordingNow)
	{
		[recordingMenuItem setTitle:@"Start Capture!"];
		isRecordingNow = FALSE;
		[self stopRecording:nil];
	}
	else
	{
		[recordingMenuItem setTitle:@"Stop Capture!"];	
		isRecordingNow = TRUE;
		[self captureScreenAsMovie:nil];
	}
}

- (IBAction)stopRecording:(id)sender
{

	endTime = [NSDate date];
	
	[durationLabel setStringValue:[NSString stringWithFormat:@"seconds"]];
	
	if (startTime) {[startTime release];startTime=nil;}

	// Stop CVDisplayLink to prevent
	// more frames from being read
	if (mDisplayLink)
	{
		CVDisplayLinkStop(mDisplayLink);
		CVDisplayLinkRelease(mDisplayLink);
		mDisplayLink = NULL;
	}

	// Stop current export
	
	// Free our reader and exporter 
	// objects
	if (mExporterObj)
	{
		[mExporterObj release];
		mExporterObj = nil;
	}

	// Free our queue controller
	if (mFrameQueueController)
	{
		[mFrameQueueController release];
		mFrameQueueController = nil;
	}

}

#pragma mark -------- Reader --------

// Called from our display link callback.
// This routine will attempt to get an available reader object
// to initiate a screen grab operation (to fill the object's buffer).
// It then checks to see if any reader objects have indeed been 
// filled (a screen grab operation has completed and the object's 
// buffer is filled) and if so it passes the reader object to the 
// exporter/compressor object so it can be compressed and the frame
// added to the movie.
- (void) readAndCompressFrames
{
	//Compute the local time
	if(mStartTime == 0.0)
	{
		NSTimeInterval	time = [NSDate timeIntervalSinceReferenceDate];
		mStartTime = time;
	}

	// Get an available reader object from the reader "free" queue
	FrameReader *freeReaderObj = [mFrameQueueController removeOldestItemFromFreeQ];
	
	if (freeReaderObj)
	{
		[freeReaderObj setBufferReadTime:mStartTime];
		// pass object to FrameReader and do a read operation
		// this call spawns a new thread to do the read
		[freeReaderObj readScreenAsyncOnSeparateThread];
	}

	// Compress any available frames
	
	// see if there are available frames in the "filled" queue
	FrameReader *filledReaderObj = [mFrameQueueController removeOldestItemFromFilledQ];
	if (filledReaderObj)
	{
		// compress the frame and add it to our movie
		[mExporterObj exportFrame:filledReaderObj];
	}
	}

#pragma mark -------- Display Link --------

// This is called from the Display Link callback.
// We'll use this callback to read/compress our frames.
- (CVReturn)displayLinkCallback:(const CVTimeStamp*)timeStamp flagsOut:(CVOptionFlags*)flagsOut
{
	// there is no autorelease pool when this method is called because it will be called from another thread
	// it's important to create one or you will leak objects
	NSAutoreleasePool *pool = [NSAutoreleasePool new];

        // Each iteration we will attemp to read the screen into a buffer (if
        // one is available), compress the buffer contents, then add the 
        // compressed frame to a movie
	[self readAndCompressFrames];

	[pool release];

	return kCVReturnSuccess;
}

#pragma mark ---------- Action Methods ----------


// Called to initiate capture of the screen for a timed interval
-(IBAction)captureScreenAsMovie:(id)sender
{
	NSSavePanel*				savePanel = [NSSavePanel savePanel];
	CodecType					codec;
	double					framerate;
	ICMCompressionSessionOptionsRef	options;

	// first ask user where to save movie file
	[savePanel setRequiredFileType:@"mov"];
	[savePanel setCanCreateDirectories:YES];
	[savePanel setCanSelectHiddenExtension:YES];
	if(([savePanel runModalForDirectory:[@"~/Desktop" stringByExpandingTildeInPath] file:@"Screen Capture.mov"] == NSOKButton) && (options = [FrameCompressor userOptions:&codec frameRate:&framerate autosaveName:@"CompressionDialogSettings" showDialog:FALSE])) 
	{
	
		NSNumber *widthNum,*heightNum;
		widthNum = [NSNumber numberWithFloat:mDisplayRect.size.width];
		heightNum = [NSNumber numberWithFloat:mDisplayRect.size.height];
		
		// image size, used to make image for mouse movements
		imageSize = NSMakeSize (mDisplayRect.size.width, mDisplayRect.size.height);
		
		// make an exporter object
		mExporterObj = [[FrameMovieExporter alloc] initWithPath:[savePanel filename] codec:codec pixelsWide:[widthNum unsignedIntValue] pixelsHigh:[heightNum unsignedIntValue] options:options];

		// make a frame queue controller, which will create and manage the
		// underlying set of (multiple) frame reader objects
		mFrameQueueController = [[QueueController alloc] initWithReaderObjects:
										kNumReaderObjects	// create this many frame reader objects
										aContext:mGLContext 
										pixelsWide:[widthNum unsignedIntValue] 
										pixelsHigh:[heightNum unsignedIntValue] ];

		// create display link for the main display
		CVDisplayLinkCreateWithCGDisplay(kCGDirectMainDisplay, &mDisplayLink);
		if (NULL != mDisplayLink) 
		{
			// set the current display of a display link.
			CVDisplayLinkSetCurrentCGDisplay(mDisplayLink, kCGDirectMainDisplay);
			
			// set the renderer output callback function
			CVDisplayLinkSetOutputCallback(mDisplayLink, &MyRenderCallback, self);
			
			// activates a display link.
			CVDisplayLinkStart(mDisplayLink);
		}
	}
}

// Called if the user presses the "Cancel" button in
// the capture movie window
- (IBAction)captureScreenToMovieCancelButton:(id)sender
{
	// pressing cancel button in movie capture window
	// simply closes the window
	[mMovieCaptureWindow close];
}

// Called if the user presses the "OK" button in
// the capture movie window
- (IBAction)captureScreenToMovieOKButton:(id)sender
{
	// pressing ok button in movie capture window
	// closes the window and starts the actual capture
	[mMovieCaptureWindow close];
	[self captureScreenAsMovie:nil];
}

- (IBAction)createMouseMovieMenuItemAction:(id)sender
{
	if ([sender state] == NSOnState)
	{
		[sender setState:NSOffState];
		[[NSUserDefaults standardUserDefaults] setBool:FALSE forKey:@"CreateMouseMovie"];
	}
	else
	{
		[sender setState:NSOnState];
		[[NSUserDefaults standardUserDefaults] setBool:TRUE forKey:@"CreateMouseMovie"];
	}
}

- (BOOL)createMouseMovie
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:@"CreateMouseMovie"];
}


- (IBAction)openCodecOptionsMenuItemAction:(id)sender
{
	CodecType					codec;
	double					framerate;
	[FrameCompressor userOptions:&codec frameRate:&framerate autosaveName:@"CompressionDialogSettings" showDialog:TRUE];
	
	NSString * codecName = [FrameCompressor codecNameForType:codec];

	[codecAndFrameRateMenuItem setTitle:[NSString stringWithFormat:@"( %@ - %0.2f )", codecName, framerate]];

	[codecAndFrameRateMenuItem setEnabled:FALSE];

	
}


@end
