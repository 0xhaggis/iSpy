#ifndef __ISPY_INSTANCE__
#define __ISPY_INSTANCE__

typedef std::unordered_map<unsigned int, unsigned int> InstanceMap_t;

@interface InstanceTracker : NSObject {

}
@property (assign) InstanceMap_t *instanceMap;
@property (assign) BOOL enabled;

+(InstanceTracker *) sharedInstance;
-(void) installHooks;
-(void) start;
-(void) stop;
-(void) clear;
-(NSArray *)instancesOfAllClasses;  
-(NSArray *) instancesOfAppClasses;
-(id)instanceAtAddress:(NSString *)addr; 
// Don't call these
-(id)__instanceAtAddress:(NSString *)addr;
-(NSArray *)__dumpInstance:(id)instance;
@end

// Hooks
id bf_alloc(Class cls, SEL selector);
id bf_dealloc(id obj, SEL selector);
id bf_NSAllocateObject(Class cls, NSUInteger extraBytes, NSZone *zone);
id bf_objc_constructInstance(Class cls, void *bytes);
id bf_objc_destructInstance(id obj);
//int _isClassFromApp(const char *className);

// Helper functions
void bf_init_instance_tracker();

#endif // __ISPY_INSTANCE__
