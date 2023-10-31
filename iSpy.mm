/*
	Bishop Fox - iSpy
*/
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#include <pthread.h>
#include <errno.h>
#include <objc/message.h>
#include <sys/stat.h>
#include "3rd-party/fishhook/fishhook.h"
#include "iSpy.class.h"
#include "iSpy.common.h"
#include "iSpy.instance.h"
#include "iSpy.msgSend.h"
#include "3rd-party/Cycript.framework/Headers/Cycript.h"
#import "iSpy.HoverButton.h"
#import "iSpy.FloatingButtonWindow.h"

/*
 * iSpy constructor
 */
__attribute((constructor)) void iSpy_init(int argc, const char **argv, const char **envp, const char **apple, struct ProgramVars *pvars) {
	NSLog(@"[iSpy.dylib] Constructor entry, spawning thread to bootstrap iSpy...");
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

		NSLog(@"[iSpy] Inside iSpy thread. Initializing.");
		

		//setenv("CFNETWORK_DIAGNOSTICS","3",1); // this is awesome

		/*
		 * Do user-specified custom initialization PRIOR to anything iSpy does. 
	     * In iSpy.custom.mm you can modify customInitializaton_preflight() to do bespoke things here.
	     * Useful for code that MUST run before anything else, even iSpy itself.
	     */
	    customInitialization_preflight();


		/*
		 * Initialize and cache the iSpy sharedInstance. 
		 */
		NSLog(@"[iSpy] Activating iSpy");
		iSpy *mySpy = [iSpy sharedInstance];	// Initialize iSpy
		[mySpy initializeAllTheThings];			// run once


	    /* 
	     *	The objc_msgSend tracing feature uses a watchlist to determine which methods/classes
	     *	should be monitored and logged. By default the watchlist contains all of the methods in all 
	     *	of all the classes defined by the target app. 
	     *	You can add/remove individual methods and/or entire classes to/from the watchlist.
	     *	This is good for removing animations, CPU hogs, and other uninteresting crap.
	     */
		// Remove an entire class from the watchlist    
	    //[mySpy msgSend_watchlistRemoveClass:@"ClassWeDoNotCareAbout"];

	    // Remove an individual method from the watchlist
	    //[mySpy msgSend_watchlistRemoveMethod:@"testMethod" fromClass:@"FooClass"];

	    // Add a method to the watchlist
	    //[mySpy msgSend_watchlistAddMethod:@"setHTTPBody:" forClass:@"NSMutableURLRequest"];
		
	    // Clear the watchlist of all entries
	    //[mySpy msgSend_clearWhitelist];
		
		// Add all the methods in a single class, in this example it's UIApplication (super useful).
	    // It doesn't matter if you add a class twice, it won't actually be added a second time.
	    // NOTE: iSpy auto-saves the watchlist for each app on your device, so the watchlist persists between launches.
		//NSLog(@"[iSpy] Initialize watchlist");
	    //[mySpy msgSend_watchlistAddClass:@"UIApplication"];

		
		/*
		 *	Turn on objc_msgSend tracing.
		 *	You can also turn it on/off in Cycript using: 
		 *		[[iSpy sharedInstance] msgSend_enableLogging]
		 *		[[iSpy sharedInstance] msgSend_disableLogging]
		 */
		//NSLog(@"[iSpy] Enabling msgSend logging");
		//[mySpy msgSend_enableLogging];


		/*
		 *	Bypass SSL pinning. Uses a combination of:
		 *		- TrustMe SecTrustEvaluate() bypass
		 *		- BF's custom AFNetworking bypasses
		 *      - NSURLSession pinning
		 *      - Anything that uses custom subclassed variants of the above
		 *	This is ENABLED BY DEFAULT.
		 *
		 *  Cycript command: [[[iSpy sharedInstance] SSLPinningBypass] setEnabled:TRUE]
		 */
		NSLog(@"[iSpy] Enabling SSL Pinning bypasses");
		[[mySpy SSLPinningBypass] setEnabled:FALSE];

		/*
		 * At this point, iSpy is all ready to roll.
	     * In iSpy.custom.mm you can modify customInitializaton_postflight() to do bespoke things here.
	     * Useful for swizzling, etc.
	     */
		//NSLog(@"[iSpy] Running custom initialization stuff from iSpy.custom.mm");
	    //customInitialization_postflight();

	    //NSLog(@"[iSpy] Dumping classes to elasticsearch...");
	    //[[iSpy sharedInstance] classDumpToElasticsearch];
	    //NSLog(@"[iSpy] Done dump.");

		NSLog(@"[iSpy] Waiting for 10 seconds for the dust to settle before showing button...");
		for(int i = 0; i < 3; i++) {
			NSLog(@"[iSpy] Wait %d", i);
			sleep(1);
		}
		NSLog(@"[iSpy] Ready! Showing the button");
		[[iSpyHoverButton alloc] init];

		NSLog(@"[iSpy] Finished loading. /thread");
	});
	NSLog(@"[iSpy.dylib] Constructor finished. iSpy is loading.");
}


