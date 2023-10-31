# iSpy2
iSpy is old now. Frida is far more powerful, convenient, and robust for 99% of all use cases. However, there's some fun stuff in here if you dig. There's a hand-rolled arm64 assembly replacement of `objc_msgSend` that logs method calls according to a whitelist controllable by you, the user, via an API or via some other control mechanism (ironically you could use Frida to grab the iSpy singleton `[iSpy sharedInstance]` and manipulate iSpy very easily. I used to use Cycript back in the day). 

There's a bunch of anti-anti-swizzling, anti-SSL-pinning, etc. if anyone finds that stuff interesting. There's a conventient bunch of helper functions to do arbitrary method swizzling of Objective-C methods. Not sure how much of that is still relevant these days. Oh, iSpy is FAST, especially when configured to log to ElasticSearch.

# No docs, who dis?
Yeah sorry. Source code is your documentation. `make` to build `iSpy.dylib`. Use the sideloader de jour for whatever jailbreak / dev profile you're using. Look at your phone's console log for more information... if this thing even runs on modern iPhones / iOSs.  
