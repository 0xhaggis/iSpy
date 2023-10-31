#include <stack>
#include <fcntl.h>
#include <stdio.h>
#include <dlfcn.h>
#include <stdarg.h>
#include <unistd.h>
#include <string.h>
#include <dirent.h>
#include <stdbool.h>
#include <pthread.h>
#include <sys/stat.h>
#include <sys/param.h>
#include <sys/mount.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <sys/mman.h>
#include <sys/uio.h>
#include <objc/objc.h>
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <mach-o/dyld.h>
#include <netinet/in.h>
#import  <Security/Security.h>
#import  <Security/SecCertificate.h>
#include <CFNetwork/CFNetwork.h>
#include <CFNetwork/CFProxySupport.h>
#include <CoreFoundation/CFString.h>
#include <CoreFoundation/CFStream.h>
#import  <Foundation/NSJSONSerialization.h>
#include <CommonCrypto/CommonDigest.h>
#include <CommonCrypto/CommonHMAC.h>
#import <UIKit/UIKit.h>
#include "../iSpy.common.h"
#include "../iSpy.instance.h"
#include "../iSpy.class.h"
#include <dlfcn.h>
#include <mach-o/nlist.h>
#include <semaphore.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <QuartzCore/QuartzCore.h>
#import "../3rd-party/typestring.h"
#import "RPCHandler.h"

#define DEBUG(...) NSLog(__VA_ARGS__)
//#define DEBUG(...) {}

/*
 *
 * RPC handlers take exactly one argument: an NSDictionary of parameter/value pairs.
 *
 * RPC handlers return an NSDictionary that will be sent to the RPC caller as JSON,
 * either via a websocket (if initiated by websocket) or as a response to an HTTP POST.
 *
 * You can also return nil, that's fine too. For websockets nothing will happen; for POST
 * requests it'll cause a blank response to be sent back to the RPC caller.
 *
 */
@implementation RPCHandler

-(NSDictionary *) setMsgSendLoggingState:(NSDictionary *) args {
    DEBUG(@"[RPC] setMsgSendLoggingState");
	NSString *state = [args objectForKey:@"state"];

	if( ! state || ( ! [state isEqualToString:@"true"] && ! [state isEqualToString:@"false"] )) {
		ispy_log("setMsgSendLoggingState: Invalid state");
		return @{
			@"status":@"error",
			@"errorMessage":@"Invalid status"
		};
	}

	if([state isEqualToString:@"true"]) {
		[[iSpy sharedInstance] msgSend_enableLogging];
	}
	else if([state isEqualToString:@"false"]) {
		[[iSpy sharedInstance] msgSend_disableLogging];
	}

	return @{
		@"status":@"OK",
		@"JSON": @{
            @"state": state,
        },
	};
}


-(NSDictionary *) testJSONRPC:(NSDictionary *)args {
    DEBUG(@"[RPC] testJSONRPC");
	return @{
		@"status":@"OK",
		@"JSON": @{
            @"args": args,
        },
	};
}

-(NSDictionary *) ASLR:(NSDictionary *)args {
    DEBUG(@"[RPC] ASLR");
	return @{
		@"status":@"OK",
		@"JSON": @{
            @"ASLROffset": [NSString stringWithFormat:@"%d", [[iSpy sharedInstance] ASLR]]
        },
	};
}

-(NSDictionary *) getWhitelist:(NSDictionary *)args {
    DEBUG(@"[RPC] getWhitelist");
    return @{
        @"status":@"OK",
        @"JSON": @{
            @"watchlist": watchlist_copy_watchlist()
        },
    };
}

/*
args = NSDictionary containing an object ("classes"), which is is an NSArray of NSDictionaries, like so:
{
	"classes": [
		{
			"class": "ClassName1",
			"methods": [ @"Method1", @"Method2", ... ]
		},
		{
			"class": "ClassName2",
			"methods": [ @"MethodX", @"MethodY", ... ]
		},
		...
	]
}

If "methods" is nil, assume all methods in class.
*/
-(NSDictionary *) addMethodsToWhitelist:(NSDictionary *)args {
    DEBUG(@"[RPC] addMethodsToWhitelist");
    int i, numClasses, m, numMethods;
    static std::unordered_map<std::string, std::unordered_map<std::string, int> > WhitelistClassMap;

    ispy_log("[Whitelist RPC] addMethodsToWhitelist args: %s", [[args description] UTF8String]);

    NSArray *classes = [args objectForKey:@"classes"];

    if(classes == nil) {
    	return @{
    		@"status": @"error",
    		@"errorMessage": @"Empty class list"
    	};
    }

	numClasses = [classes count];

    // Iterate through all the class names, adding each one to our lookup table
    for(i = 0; i < numClasses; i++) {
    	NSDictionary *itemToAdd = [classes objectAtIndex:i];
		if(!itemToAdd)
		{
            ispy_log("[Whitelist] Error, itemToAdd was null.");
			continue;
		}

    	NSString *name = [itemToAdd objectForKey:@"class"];
    	if(!name || [name isKindOfClass:[NSNull class]]) {
            ispy_log("[Whitelist] Error, name was null.");
    		continue;
    	}

    	NSArray *methods = [itemToAdd objectForKey:@"methods"];
    	if(!methods) {
            //ispy_log("[Whitelist] Methods was null, populating with all methods");
            methods = [[iSpy sharedInstance] methodListForClass:name];
            numMethods = [methods count];
    	} else {
            numMethods = [methods count];
            if(!numMethods) {
                //ispy_log("[Whitelist] numMethods = 0, using all methods.");
                methods = [[iSpy sharedInstance] methodListForClass:name];
                numMethods = [methods count];
            }
        }

        ispy_log("[Whitelist] Processing methods for '%s' (%d)", [name UTF8String], numMethods);
        BOOL shouldSendUpdate = false;
    	for(m = 0; m < numMethods; m++) {
    		NSString *methodName = [methods objectAtIndex:m];
    		if(!methodName || [methodName isKindOfClass:[NSNull class]]) {
                ispy_log("[Whitelist] Error, methodName was null.");
    			continue;
    		}
    		std::string *classNameString = new std::string([name UTF8String]);
    		std::string *methodNameString = new std::string([methodName UTF8String]);
    		if(!classNameString || !methodNameString) {
    			if(methodNameString)
    				delete methodNameString;
    			if(classNameString)
    				delete classNameString;
    			continue;
    		}
    		//ispy_log("[Whitelist] Adding [%s %s]", classNameString->c_str(), methodNameString->c_str());
            
            shouldSendUpdate = ( (m == numMethods - 1) && (i == numClasses - 1) );
            watchlist_add_method_real(classNameString, methodNameString, WATCHLIST_PRESENT, shouldSendUpdate);
    		delete methodNameString;
    		delete classNameString;
    	}
    }

    [[iSpy sharedInstance] tellBrowserToRefreshWhitelist];
    
    // We've updated the watchlist, save it to disk
    [[iSpy sharedInstance] saveState];

    return @{
    	@"status": @"OK",
    	@"JSON": @{},
    };
}

-(NSDictionary *) removeMethodsFromWhitelist:(NSDictionary *)args {
    DEBUG(@"[RPC] removeMethodsFromWhitelist");
    int i, numClasses, m, numMethods;
    static std::unordered_map<std::string, std::unordered_map<std::string, int> > WhitelistClassMap;

    NSArray *classes = [args objectForKey:@"classes"];
    if(classes == nil || [classes isKindOfClass:[NSNull class]]) {
        return @{
            @"status": @"error",
            @"errorMessage": @"Empty class list"
        };
    }

    numClasses = [classes count];

    // Iterate through all the class names, adding each one to our lookup table
    for(i = 0; i < numClasses; i++) {
        NSDictionary *itemToAdd = [classes objectAtIndex:i];
		if(!itemToAdd || [itemToAdd isKindOfClass:[NSNull class]])
		{
            ispy_log("[Whitelist] Error, itemToAdd was null.");
			continue;
		}

        NSString *name = [itemToAdd objectForKey:@"class"];
        if(!name || [name isKindOfClass:[NSNull class]]) {
            continue;
        }

        NSArray *methods = [itemToAdd objectForKey:@"methods"];
        if(!methods || [methods isKindOfClass:[NSNull class]]) {
            continue;
        }

        numMethods = [methods count];
        
        // If we're passed an empty list of methods, remove the entire class
        if(!numMethods) {
            std::string *classNameString = new std::string([name UTF8String]);
            watchlist_remove_class(classNameString);
            delete classNameString;
            continue;
        }

        for(m = 0; m < numMethods; m++) {
            NSString *methodName = [methods objectAtIndex:m];
            if(!methodName ||[methodName isKindOfClass:[NSNull class]]) {
                continue;
            }
            std::string *classNameString = new std::string([name UTF8String]);
            std::string *methodNameString = new std::string([methodName UTF8String]);
            if(!classNameString || !methodNameString) {
                if(methodNameString)
                    delete methodNameString;
                if(classNameString)
                    delete classNameString;
                continue;
            }
            ispy_log("[Whitelist] Removing [%s %s]", classNameString->c_str(), methodNameString->c_str());
            watchlist_remove_method(classNameString, methodNameString);
            delete methodNameString;
            delete classNameString;
        }
    }

    [[iSpy sharedInstance] tellBrowserToRefreshWhitelist];

    // We've updated the watchlist, save it to disk
    [[iSpy sharedInstance] saveState];
    return @{
        @"status": @"OK",
        @"JSON": @{},
    };
}

/*
 * 	Classes and internals
 */


-(NSDictionary *) getNumberOfObjcEvents:(NSDictionary *)args {
    DEBUG(@"[RPC] Calling get_objc_event_log_count()");
    long count = get_objc_event_log_count();
    DEBUG(@"[RPC] Refresh len: %ld", count);

    return @{
        @"status": @"OK",
        @"JSON": @{
            @"count": [NSNumber numberWithLong:count]
        },
    };
}

-(NSDictionary *) refreshObjCEvents:(NSDictionary *)args {
    DEBUG(@"[RPC] refreshObjCEvents");
	static BOOL isRefreshing = false;
    long start = 0, numEventsToRead = -1;

	if(isRefreshing)
		return nil;

	isRefreshing = true;

    if([args objectForKey:@"start"])
        start = [[args objectForKey:@"start"] longValue];
    
    if([args objectForKey:@"count"])
        numEventsToRead = [[args objectForKey:@"count"] longValue];

    NSArray *events = get_objc_event_log(start, numEventsToRead);
    if(events)
        NSLog(@"refresh len: %ld", (unsigned long)[events count]);
    else
        NSLog(@"[RPC] refreshObjCEvents failed to get event log");

	isRefreshing = false;

    return @{
        @"status": @"OK",
        @"JSON": @{
            @"events": (events) ? events : @[]
        },
    };
}

-(NSDictionary *) classList:(NSDictionary *)args {
    DEBUG(@"[RPC] classList");
	NSArray *classes = [[iSpy sharedInstance] classes];
	return @{
		@"status": @"OK",
		@"JSON": @{
            @"classes": classes,
        },
	};
}

-(NSDictionary *) classDump:(NSDictionary *)args {
    DEBUG(@"[RPC] classDump");
    NSDictionary *classes = [[iSpy sharedInstance] classDump];
    return @{
        @"status": @"OK",
        @"JSON": @{
            @"classes": classes,
        },
    };
}

-(NSDictionary *) classListWithProtocolInfo:(NSDictionary *)args {
    DEBUG(@"[RPC] classListWithProtocolInfo");
	NSArray *classes = [[iSpy sharedInstance] classesWithSuperClassAndProtocolInfo];
	return @{
		@"status": @"OK",
		@"JSON": @{
            @"classes": classes,
        },
	};
}

-(NSDictionary *) classDumpClass:(NSDictionary *)args {
    DEBUG(@"[RPC] classDumpClass");
    NSString *className = [args objectForKey:@"class"];
    if(className == nil) {
        return @{
            @"status": @"error",
            @"errorMessage": @"Empty class name",
        };
    }

    NSDictionary *classDump = [[iSpy sharedInstance] classDumpClass:className];
    if(classDump == nil) {
        return @{
            @"status": @"error",
            @"errorMessage": @"Empty methods list",
        };
    }

    if([args objectForKey:@"DOMElement"]) {
        return @{
            @"status": @"OK",
            @"DOMElement": [args objectForKey:@"DOMElement"],
            @"JSON": @{
                @"classDump": classDump
            }
        };
    } else {
        return @{
            @"status": @"OK",
            @"JSON": @{
                @"classDump": classDump
            }
        };
    }
}

-(NSDictionary *) classDumpClassFull:(NSDictionary *)args {
    DEBUG(@"[RPC] classDumpClassFull");
    NSString *className = [args objectForKey:@"class"];
    if(className == nil) {
        return @{
            @"status": @"error",
            @"errorMessage": @"Empty class name",
        };
    }

    NSLog(@"[RPC] Dispatching to classDumpClassFull: %@", className);
    NSDictionary *classDump = [[iSpy sharedInstance] classDumpClassFull:className];
    //NSLog(@"[iSpy RPC] back from classDumpClassFull with object: %@", classDump); 
    if(classDump == nil) {
        NSLog(@"[RPC] classDumpClassFull failed");
        return @{
            @"status": @"error",
            @"errorMessage": @"Empty methods list",
        };
    }

    NSLog(@"[RPC] Success!");
    //NSLog(@"[RPC] ClassDump: %@ for args %@", classDump, args);
    if([args objectForKey:@"DOMElement"]) {
        return @{
            @"status": @"OK",
            @"DOMElement": [args objectForKey:@"DOMElement"],
            @"JSON": @{
                @"classDump": classDump
            }
        };
    } else {
        return @{
            @"status": @"OK",
            @"JSON": @{
                @"classDump": classDump
            }
        };
    }
}

-(NSDictionary *) methodsForClass:(NSDictionary *)args {
    DEBUG(@"[RPC] methodsForClass: args: %@", args);
	NSString *className = [args objectForKey:@"class"];
    NSNumber *classID = [args objectForKey:@"id"];

    NSLog(@"The ID is %@", classID);

    if(className == nil) {
    	return @{
    		@"status": @"error",
    		@"errorMessage": @"Empty class name",
    	};
    }

    NSArray *methods = [[iSpy sharedInstance] methodListForClass:className];
    if(methods == nil) {
    	return @{
    		@"status": @"error",
    		@"errorMessage": @"Empty methods list",
    	};
    }

    return @{
    	@"status": @"OK",
    	@"JSON": @{
            @"name": className,
            @"methods": methods,
            @"id": classID
        },
    };
}

-(NSDictionary *) propertiesForClass:(NSDictionary *)args {
    DEBUG(@"[RPC] propertiesForClass");
	NSString *className = [args objectForKey:@"class"];
    if(className == nil) {
    	return @{
    		@"status": @"error",
    		@"errorMessage": @"Empty class name"
    	};
    }

    NSArray *properties = [[iSpy sharedInstance] propertiesForClass:className];
    if(properties == nil) {
    	return @{
    		@"status": @"error",
    		@"errorMessage": @"Empty properties list"
    	};
    }

    return @{
    	@"status": @"OK",
    	@"JSON": @{
            @"name": className,
            @"properties": properties,
        },
    };
}

-(NSDictionary *) protocolsForClass:(NSDictionary *)args {
    DEBUG(@"[RPC] protocolsForClass");
	NSString *className = [args objectForKey:@"class"];
    if(className == nil) {
    	return @{
    		@"status": @"error",
    		@"errorMessage": @"Empty class name"
    	};
    }

    NSArray *protocols = [[iSpy sharedInstance] protocolsForClass:className];
    if(protocols == nil) {
    	return @{
    		@"status": @"error",
    		@"errorMessage": @"Empty protocols list"
    	};
    }

    return @{
    	@"status": @"OK",
    	@"JSON": @{
            @"name": className,
            @"protocols": protocols,
        },
    };
}

-(NSDictionary *) iVarsForClass:(NSDictionary *)args {
    DEBUG(@"[RPC] iVarsForClass");
	NSString *className = [args objectForKey:@"class"];
    if(className == nil) {
    	return @{
    		@"status": @"error",
    		@"errorMessage": @"Empty class name"
    	};
    }

    NSArray *iVars = [[iSpy sharedInstance] iVarsForClass:className];
    if(iVars == nil) {
    	return @{
    		@"status": @"error",
    		@"errorMessage": @"Empty iVars list"
    	};
    }


    return @{
    	@"status": @"OK",
    	@"JSON": @{
            @"name": className,
            @"iVars": iVars,
        },
    };
}

-(NSDictionary *) infoForMethod:(NSDictionary *)args {
    DEBUG(@"[RPC] infoForMethod");
	NSString *className = [args objectForKey:@"class"];
	NSString *methodName = [args objectForKey:@"method"];
    NSString *isInstanceStr = [args objectForKey:@"isInstance"];
    BOOL isInstance;

	if(className == nil || methodName == nil) {
    	return @{
    		@"status": @"error",
    		@"errorMessage": @"Empty class and/or name"
    	};
    }

    if(isInstanceStr == nil)
        isInstance = true;
    else if([isInstanceStr isEqualToString:@"1"] || [isInstanceStr isEqualToString:@"true"])
        isInstance = true;
    else
        isInstance = false;

    Class cls = objc_getClass([className UTF8String]);
    if(cls == nil) {
    	return @{
    		@"status": @"error",
    		@"errorMessage": @"That class doesn't exist"
    	};
    }

    SEL selector = sel_registerName([methodName UTF8String]);
    if(selector == nil) {
    	return @{
    		@"status": @"error",
    		@"errorMessage": @"That selector name was bad"
    	};
    }

    NSLog(@"class: %@ // method: %s", cls, [methodName UTF8String]);

    NSDictionary *infoDict = [[iSpy sharedInstance] infoForMethod:selector inClass:cls isInstanceMethod:isInstance];
    if(infoDict == nil) {
    	return @{
    		@"status": @"error",
    		@"errorMessage": @"Error fetching information for that class/method"
    	};
    }

    return @{
    	@"status": @"OK",
    	@"JSON": @{
            @"methodInfo": infoDict
        },
    };
}


/*
 *	Protocol RPC
 */

-(NSDictionary *) methodsForProtocol:(NSDictionary *)args {
    DEBUG(@"[RPC] methodsForProtocol");
	NSString *protocolName = [args objectForKey:@"protocol"];
    if(protocolName == nil) {
    	return @{
    		@"status": @"error",
    		@"errorMessage": @"Empty protocol name"
    	};
    }

    NSArray *methods = [[iSpy sharedInstance] methodsForProtocol:objc_getProtocol([protocolName UTF8String])];
    if(methods == nil) {
    	return @{
    		@"status": @"error",
    		@"errorMessage": @"Empty methods list"
    	};
    }

    return @{
    	@"status": @"OK",
    	@"JSON": methods
    };
}

-(NSDictionary *) propertiesForProtocol:(NSDictionary *)args {
    DEBUG(@"[RPC] propertiesForProtocol");
	NSString *protocolName = [args objectForKey:@"protocol"];
    if(protocolName == nil) {
    	return @{
    		@"status": @"error",
    		@"errorMessage": @"Empty protocol name"
    	};
    }

    NSArray *properties = [[iSpy sharedInstance] propertiesForProtocol:objc_getProtocol([protocolName UTF8String])];
    if(properties == nil) {
    	return @{
    		@"status": @"error",
    		@"errorMessage": @"Empty properties list"
    	};
    }

    return @{
    	@"status": @"OK",
    	@"JSON": properties
    };
}


/*
 *	Instance RPC
 */


-(NSDictionary *) instanceAtAddress:(NSDictionary *)args {
    DEBUG(@"[RPC] instanceAtAddress");
	NSString *addr = [args objectForKey:@"address"];
    if(addr == nil) {
    	return @{
    		@"status": @"error",
    		@"errorMessage": @"Empty address value"
    	};
    }

    return @{
    	@"status":@"OK",
    	@"JSON": [[InstanceTracker sharedInstance] instanceAtAddress:addr]
    };
}


-(NSDictionary *) instancesOfAppClasses:(NSDictionary *)args {
    DEBUG(@"[RPC] instancesOfAppClasses");
	return @{
		@"status":@"OK",
		@"JSON": @{
            @"classInstances": [[InstanceTracker sharedInstance] instancesOfAppClasses],
        },
	};
}


/*
 *	App info RPC
 */

-(NSDictionary *) applicationIcon:(NSDictionary *)args {
    DEBUG(@"[RPC] applicationIcon");
	UIImage *appIcon = [UIImage imageNamed:[[NSBundle mainBundle].infoDictionary[@"CFBundleIcons"][@"CFBundlePrimaryIcon"][@"CFBundleI‌​conFiles"] firstObject]];
	if(!appIcon) {
		appIcon = [UIImage imageNamed: [[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIconFiles"] objectAtIndex:0]];
		if(!appIcon) {
			appIcon = [UIImage imageNamed:@"Icon@2x.png"];
			if(!appIcon) {
				appIcon = [UIImage imageNamed:@"Icon-72.png"];
				if(!appIcon) {
					appIcon = [UIImage imageNamed:@"/var/www/iSpy/img/bf-orange-alpha.png"];
					if(!appIcon) {
						return @{
							@"status":@"error",
							@"error": @"WTF, no app icon"
						};
					}
				}
			}
		}
	}
	
	//NSLog(@"Icon files: %@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIconFiles"]);
	NSLog(@"appIcon: %@", appIcon);
	NSData *PNG = UIImagePNGRepresentation(appIcon);
	NSLog(@"PNG: %@", appIcon);
	NSString *base64PNG = [PNG base64EncodedStringWithOptions:0];

	return @{
		@"status":@"OK",
		@"JSON": @{
			@"imageURI": [NSString stringWithFormat:@"data:image/png;base64,%@", base64PNG]
		}
	};
}

-(NSDictionary *) appInfo:(NSDictionary *)args {
    DEBUG(@"[RPC] appInfo");
	NSDictionary *infoDict = [[NSBundle mainBundle] infoDictionary];
	NSArray *keys = [infoDict allKeys];
	NSMutableDictionary *interestingProperties = [[NSMutableDictionary alloc] init];

	for(int i=0; i < [keys count]; i++) {
		id obj = [keys objectAtIndex:i];
		if(!obj) {
			continue;
		}
		if([[infoDict objectForKey:obj] class] == objc_getClass("__NSCFString")) {
			[interestingProperties setObject:[NSString stringWithString:[infoDict objectForKey:obj]] forKey:obj];
		}
	}

	return @{
		@"status":@"OK",
		@"JSON": interestingProperties
	};
}


-(NSDictionary *) keyChainItems:(NSDictionary *)args {
    DEBUG(@"[RPC] keychainItems");
	NSDictionary *keychainItems = [[iSpy sharedInstance] keyChainItems];
    return @{
		@"status":@"OK",
		@"JSON": keychainItems
	};
}

-(NSDictionary *) updateKeychain:(NSDictionary *)args {
    DEBUG(@"[RPC] updateKeychain");
    NSString *service = [args objectForKey:@"svce"];
    NSString *chain = [args objectForKey:@"chain"];
    NSData *data = [[NSData alloc] initWithBase64EncodedString:[args objectForKey:@"data"] options:NSDataBase64DecodingIgnoreUnknownCharacters];
    NSDictionary *keychainItems = [[iSpy sharedInstance] updateKeychain:chain forService:service withData:data];
    NSLog(@"Returning...");
    return @{
        @"status":@"OK",
        @"JSON": keychainItems
    };
}

-(NSDictionary *) bypassSSLPinning:(NSDictionary *)args {
    DEBUG(@"[RPC] bypassSSLPinning");
	NSString *state = [args objectForKey:@"state"];
    if(state == nil) {
    	return @{
    		@"status": @"error",
    		@"errorMessage": @"Empty address value"
    	};
    }

    if([state isEqualToString:@"true"] || [state isEqualToString:@"TRUE"]) {
        [[[iSpy sharedInstance] SSLPinningBypass] setEnabled:[NSNumber numberWithBool:TRUE]];
    } else if([state isEqualToString:@"false"] || [state isEqualToString:@"FALSE"]) {
        [[[iSpy sharedInstance] SSLPinningBypass] setEnabled:[NSNumber numberWithBool:FALSE]];
    } else {
        return @{
            @"status":@"error",
            @"errorMessage":@"Must specify true or false"
        };    
    }

    return @{
    	@"status":@"OK",
    	@"JSON": @{ @"status": @"ok"}
    };
}

@end


