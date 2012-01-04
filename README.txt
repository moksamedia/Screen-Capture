
-----------------------------

This is a modified version of the Apple OpenGL screen capture example code. Changes include adding a user friendly GUI,
extending the capture time, allowing the user to choose the export codec, allowing the simultaneous capturing of mouse position
and exporting a separate mouse movie. Audio is not captured.

I wrote it because there seemed to be a number of people asking money for a utility that did this, and the sample code
got me 80% of the way there (and I also had a project at work that required a lot of video capturing of web pages).

The original Apple example README is below.



-----------------------------



READ ME - OpenGLCaptureToMovie

v1.0
-----------------------------

OpenGLCaptureToMovie is an application which demonstrates how to capture the screen on Mac OS X using OpenGL. The sample shows how to grab frames using asynchronous texture fetching, a technique which is more complicated but offers much better performance than synchronous capture with glReadPixels().

When performing asynchronous texture fetching, the resulting capture is saved to a movie file. Compression of the actual frames for the destination movie file is performed simultaneously with the capture but on a separate thread for better performance.

Building the Sample
-------------------
The sample was built using Xcode 2.4.1 on Mac OS X 10.4. You can just open the project and choose Build from the Build menu.  This will build the OpenGLCaptureToMovie application in the "Build" directory.


Using the Sample
----------------
To try out the OpenGLCaptureToMovie application, select the "Capture" menu, and choose the "Movie" menu item. This will capture the screen for a period of 10 seconds, and save the resulting frames to a QuickTime movie. A dialog will appear when the capture has completed.

How It Works
------------

As stated above, the sample shows how to capture the screen using asynchronous texture fetching, a technique which is more complicated but offers much better performance than synchronous capture with glReadPixels().

Essentially, asynchronous texture fetching uses the same pipeline as a texture upload with GL_APPLE_CLIENT_STORAGE and GL_APPLE_TEXTURE_RANGE, but reverses the order in which it is performed so as to perform a download instead of an upload. What this will do is DMA texture data from VRAM into an AGP texture which can then be accessed directly by the application. Using the storage hint GL_APPLE_CLIENT_STORAGE_HINT_SHARED will eliminate the driver copy of the texture, making it resident only in VRAM and thereby increasing throughput. 
To initiate the data transfer, a call is made to glCopyTexSubImage2d() followed immediately with a glFlush(). This puts texture data into the AGP texture and with a call to glGetTexImage(), this texture is transferred into system memory. It should be noted that it's best to wait until the last possible moment to execute the transfer from AGP to system memory, as that will allow the most time in between for additional processing.
When performing asynchronous texture fetching this sample makes use of multiple "reader" objects, each of which is used to perform a single readback operation. These readbacks are done on a background thread for optimal performance. 
The sample also performs compression of the captured frames simultaneously with the capture, but on a separate thread. Once the capture has completed, the compressed frames are then saved to a movie file.

Additional Notes
----------------
The FrameReader class in this sample (see FrameReader.m) is a generic readback class which shows asynchronous texture fetching. 

Although it works well for this particular sample, it could be better optimized by making use of the following techniques:

- Pixel Buffer Object (PBO) extension

Another way of asynchronously reading back data requires mapping different frames to different PBOs. For example, using two PBOs, the application calls
glReadPixels() into PBO1 at frame n. At frame n+1, the application calls
glReadPixels() into PBO2 and then processes the data in PBO1. Ideally,
enough time should pass between the readback calls to allow the first to complete to before the CPU begins processing it.

By alternating between PBO1 and PBO2 on every frame, asynchronous readback
can be achieved. Moreover, applications can wait two or more frames.

For more information, see any of the available public documentation for the PBO extension, such as the following document from the NVIDIA website:

http://http.download.nvidia.com/developer/Papers/2005/Fast_Texture_Transfers/Fast_Texture_Transfers.pdf

- The application managing it's own state, thus removing the need for the glGets....

- Double-buffering the readback. This sample only uses 1 texture for readback.    

For real asynchrounous behavior, you need to double buffer as in:

	glCopyTexSubImage -> texture 0
	glCopyTexSubImage -> texture 1
	    glGetTexImage -> texture 0
	glCopyTexSubImage -> texture 0
	    glGetTexImage -> texture 1
	glCopyTexSubImage -> texture 1

For additional information see the following documents:

OpenGL Performance Optimizations : The Basics
<http://developer.apple.com/technotes/tn2004/tn2093.html>

OpenGL Programming Guide For Mac OS X
<http://developer.apple.com/documentation/GraphicsImaging/Conceptual/OpenGL-MacProgGuide/index.html>

Finally, note that only minimal error checking is provided in this sample. In production code, a robust error handling strategy must be devised at the architectural level. This is left as an exercise for the reader.

