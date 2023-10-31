#include "iSpy.common.h"
#include "iSpy.class.h"
#include "iSpy.msgSend.watchlist.h"
#include <iostream>
#include <string>
#include <vector>
#include <memory>

static iSpy *mySpy;

struct interestingCall interestingCalls[] = {
    /*
    {
        // Field meanings:

        "Classification of interesting call",
        "Name of class to trigger on",
        "Name of method to trigger on",
        "Provide a description that will be sent to the iSpy UI",
        "Provide a risk rating",
        should be: INTERESTING_CALL
    }
    */
    // Data Storage
    { 
        "Data Storage",
        "NSManagedObjectContext", 
        "save", 
        "Core Data uses unencrypted SQLite databases. Sensitive information should not be stored here.", 
        "Medium",
        INTERESTING_CALL
    },
    {
        "Data Storage",
        "NSDictionary",
        "writeToFile",
        "Sensitive data should not be saved in this manner.",
        "Medium",
        INTERESTING_CALL
    },
    {
        "Data Storage",
        "NSUserDefaults",
        "init",
        "Sensitive data should not be saved using NSUserDefaults.",
        "Medium",
        INTERESTING_CALL
    },
    {
        "Data Storage",
        "NSURLCache",
        "initWithMemoryCapacity:diskCapacity:diskPath:",
        "Sensitive SSL-encrypted data may be stored in the clear using NSURLCache.",
        "Medium",
        INTERESTING_CALL
    },
    {
        "Data Storage",
        "NSURLCache",
        "storeCachedResponse:forRequest:",
        "Sensitive SSL-encrypted data may be stored in the clear using NSURLCache.",
        "Medium",
        INTERESTING_CALL
    },
    {
        "Data Storage",
        "NSURLCache",
        "setDiskCapacity:",
        "Sensitive SSL-encrypted data may be stored in the clear using NSURLCache.",
        "Medium",
        INTERESTING_CALL
    },
    { NULL }
};

/*
    @{
        @"FooClass": @{
            "className": "FooClass",
            "methods": @[
                @"fooMethod",
                @"barMethod",
            ]
        },
        @"OtherClass": @{
            "className": "OtherClass",
            "methods": @[
                @"doStuff",
                @"moreStuff",
            ]    
        }
    }
*/
extern NSDictionary *watchlist_copy_watchlist() {
    NSMutableDictionary *watchlist = [[NSMutableDictionary alloc] init];
    ClassMap_t *ClassMap = [[iSpy sharedInstance] classWhitelist];
    int count;

    for(ClassMap_t::iterator c_it = (*ClassMap).begin(); c_it != (*ClassMap).end(); ++c_it) {
        MethodMap_t methods = c_it->second;
        const char *className = c_it->first.c_str();
        NSMutableDictionary *watchlistEntry = [[NSMutableDictionary alloc] init];
        NSMutableArray *methodArray = [[NSMutableArray alloc] init];

        count = 0;
        for(MethodMap_t::iterator m_it = methods.begin(); m_it != methods.end(); m_it++) {    
            const char *methodName = m_it->first.c_str();
            [methodArray addObject:[NSString stringWithUTF8String:methodName]];
            count++;
        }
        NSString *classNameNS = [NSString stringWithUTF8String:className];

        /// get number of methods in class
        unsigned int methodCount = [[iSpy sharedInstance] countMethodsForClass:className];
        [watchlistEntry setObject:classNameNS forKey:@"className"];
        [watchlistEntry setObject:methodArray forKey:@"methods"];
        [watchlistEntry setObject:[NSNumber numberWithInt:methodCount] forKey:@"methodCountForClass"];
        [watchlistEntry setObject:[NSNumber numberWithInt:count] forKey:@"methodCountForWhitelist"];
        [watchlist setObject:watchlistEntry forKey:classNameNS];
    }
    return watchlist;
}

extern void watchlist_send_websocket_update(const char *messageType, const char *className, const char *methodName) {
    if(!messageType || !className)
        return;

    NSDictionary *message = @{
        @"messageType": [NSString stringWithUTF8String:messageType],
        @"messageData": @{
                @"classes": @[
                    @{
                        @"class": [NSString stringWithUTF8String:className],
                        @"method": (methodName) ? [NSString stringWithUTF8String:methodName] : @""
                    }
                ]
        }
    };
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:message
        options:(NSJSONWritingOptions)0
        error:&error
    ];
    if(!jsonData)
        return;

    NSString *dataStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    if(!dataStr)
        return;

    bf_websocket_write([dataStr UTF8String]);
}

extern void watchlist_add_method_real(std::string *className, std::string *methodName, unsigned int type, BOOL shouldSendUpdate) {
    ClassMap_t *ClassMap = [[iSpy sharedInstance] classWhitelist];
    (*ClassMap)[*className][*methodName] = (unsigned long)type;
    
    if(shouldSendUpdate)
        watchlist_send_websocket_update("watchlistChanged", className->c_str(), methodName->c_str());
}

extern void watchlist_add_method(std::string *className, std::string *methodName, unsigned int type) {
    watchlist_add_method_real(className, methodName, type, false); // add to watchlist and notify the browser, if connected
}

extern void watchlist_remove_method(std::string *className, std::string *methodName) {
    watchlist_remove_method_real(className, methodName, false);
}

extern void watchlist_remove_method_real(std::string *className, std::string *methodName, BOOL shouldRefresh) {
    ClassMap_t *ClassMap = [[iSpy sharedInstance] classWhitelist];
    (*ClassMap)[*className].erase(*methodName);
    
    if(shouldRefresh)
        watchlist_send_websocket_update("watchlistChanged", className->c_str(), methodName->c_str());
}

extern void watchlist_remove_class(std::string *className) {
    ClassMap_t *ClassMap = [[iSpy sharedInstance] classWhitelist];
    ClassMap_t::iterator c_it = (*ClassMap).find(*className);
    
    ispy_log("[watchlist remove class] Whitelist ptr @ %p", &(*ClassMap));
    if(c_it == ([[iSpy sharedInstance] classWhitelist])->end()) {
        ispy_log("[watchlist remove class] The class %s is not on the watchlist", className->c_str());
    }
    else {
        ispy_log("[watchlist remove class] The class %s is on the watchlist, removing.", className->c_str());
        ClassMap->erase(c_it);
    }
}

extern void watchlist_startup() {
    ispy_log("[watchlist_startup] Startup.");
    // Use a static buffer because shoving the hashmap onto the BSS prevented a crash I was having storing it elsewhere.
    // XXX Should probably debug/fix this sometime.
    static std::unordered_map<std::string, std::unordered_map<std::string, unsigned int> > WhitelistClassMap;
    
    // So here we're setting a pointer property of the iSpy object to point at a local static variable.
    // This is is crazy and should be properly stored in the class singleton. See XXX above.
    ispy_log("[Whitelist_startup] Initializing watchlist pointer");
    ispy_log("[watchlist_startup] Calling sharedInstance");
	mySpy = [iSpy sharedInstance];
    [mySpy setClassWhitelist:&WhitelistClassMap];
	ispy_log("[watchlist_startup] Done. Displaying...");
    ispy_log("[Whitelist_startup] Whitelist ptr @ %p.", [[iSpy sharedInstance] classWhitelist]);
    
    ispy_log("[Whitelist_startup] Done.");
}

// Hard-coded interesting calls are defined above as an example of one way to focus on particular
// functions.
extern void watchlist_add_hardcoded_interesting_calls() {
    ispy_log("[watchlist_add_hardcoded_interesting_calls] Initializing the interesting functions");
    struct interestingCall *call = interestingCalls;

    while(call->classification) {
        ispy_log("call = %p", call);
        std::string tmpClsName = std::string(call->className);
        std::string tmpMthName = std::string(call->methodName);
        watchlist_add_method(&tmpClsName, &tmpMthName, (unsigned long)call);
        call++;
    }
}

void watchlist_add_audit_data_to_watchlist(NSArray *JSON) {
    for(int i = 0; i < [JSON count]; i++) {
        NSDictionary *auditEvent = [JSON objectAtIndex:i];
        ispy_log("[watchlist] Adding audit data for: %s %s", [[auditEvent objectForKey:@"class"] UTF8String], [[auditEvent objectForKey:@"selector"] UTF8String]);
        std::string tmpClsName = std::string([[auditEvent objectForKey:@"class"] UTF8String]);
        std::string tmpMthName = std::string([[auditEvent objectForKey:@"selector"] UTF8String]);
        watchlist_add_method(&tmpClsName, &tmpMthName, (unsigned long)WATCHLIST_AUDIT);
    }
}

extern void watchlist_clear_watchlist() {
    ispy_log("[watchlist_clear_watchlist] Clearning the watchlist");
    //ClassMap_t *watchlist = 
    ispy_log("[watchlist_clear_watchlist] Calling sharedInstance");
    ([[iSpy sharedInstance] classWhitelist])->clear();
    //watchlist->clear();
}

// add all of the classes and methods defined in the application to the objc_msgSend logging watchlist.
void watchlist_add_app_classes() {
    int i, numClasses, m, numMethods;

    // Get a list of all the classes in the app
    ispy_log("[watchlist_add_app_classes] Calling sharedInstance");
    iSpy *mySpy = [iSpy sharedInstance];
    if(!mySpy) {
        NSLog(@"[watchlist_add_app_classes] iSpy is null");
        return;
    } else {
        NSLog(@"[watchlist_add_app_classes] got sharedInstance");
    }

    NSArray *classes = [mySpy classes];
    NSLog(@"[watchlist_add_app_classes] Classes: %@", classes);
    if(!classes) {
        NSLog(@"[watchlist_add_app_classes] classes is null");
        return;
    } else {
        NSLog(@"[watchlist_add_app_classes] got classes");
    }
	numClasses = [classes count];
    
    ispy_log("[watchlist_add_app_classes] adding %d classes...", numClasses);

    // Iterate through all the class names, adding each one to our lookup table
    for(i = 0; i < numClasses; i++) {
    	NSString *name = [classes objectAtIndex:i];
    	if(!name) {
    		continue;
    	}

        if([name isEqualToString:@"iSpy"]) {
            continue;
        }

    	NSArray *methods = [[iSpy sharedInstance] methodListForClass:name];
    	if(!methods) {
    		continue;
    	}

    	numMethods = [methods count];
    	if(!numMethods) {
    		[methods release];
    		[name release];
    		continue;
    	}

    	for(m = 0; m < numMethods; m++) {
    		NSString *methodName = [methods objectAtIndex:m];
    		if(!methodName) {
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
    		//NSLog(@"[Whitelist adding [%s %s]", classNameString->c_str(), methodNameString->c_str());
            watchlist_add_method(classNameString, methodNameString, WATCHLIST_PRESENT);
    		delete methodNameString;
    		delete classNameString;
    	}
    	[name release];
    	[methods release];
    }
    [classes release];

    ispy_log("[watchlist_add_app_classes] Added %d of %d classes to the watchlist.", i, numClasses);   
}

int watchlist_is_class_on_watchlist(char *classNameStr) {
    ClassMap_t *ClassMap = mySpy->_classWhitelist;
    std::string className((const char *)classNameStr);
    ClassMap_t::iterator c_it = (*ClassMap).find(className);

    if(c_it == (*ClassMap).end()) {
        return NO;
    }

    return YES;
}
