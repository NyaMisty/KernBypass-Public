/* How to Hook with Logos
Hooks are written with syntax similar to that of an Objective-C @implementation.
You don't need to #include <substrate.h>, it will be done automatically, as will
the generation of a class list and an automatic constructor.

%hook ClassName

// Hooking a class method
+ (id)sharedInstance {
	return %orig;
}

// Hooking an instance method with an argument.
- (void)messageName:(int)argument {
	%log; // Write a message about this call, including its class, name and arguments, to the system log.

	%orig; // Call through to the original function with its original arguments.
	%orig(nil); // Call through to the original function with a custom argument.

	// If you use %orig(), you MUST supply all arguments (except for self and _cmd, the automatically generated ones.)
}

// Hooking an instance method with no arguments.
- (id)noArguments {
	%log;
	id awesome = %orig;
	[awesome doSomethingElse];

	return awesome;
}

// Always make sure you clean up after yourself; Not doing so could have grave consequences!
%end
*/
#import <os/log.h>
#include "substrate.h"
#include <stdlib.h>
#include <fcntl.h>
#include <string.h>
const char *xpc_bundle_get_executable_path(void *);
const char *(*ori_xpc_bundle_get_executable_path)(void *);

static int logfd;

void doLog(const char *str) {
	write(logfd, str, strlen(str));
	write(logfd, "\n", 1);
	fsync(logfd);
}

const char *hook_xpc_bundle_get_executable_path(void *dict) {
	const char *oriRet = ori_xpc_bundle_get_executable_path(dict);
	doLog(oriRet);
	//os_log(OS_LOG_DEFAULT, "xpc_bundle_get_executable_path: %s", oriRet);
	return oriRet;
}

%ctor {
	logfd = open("/private/var/log/com.apple.xpc.launchd/testlog", O_WRONLY | O_CREAT, 0777);
	//void *p_xpc_bundle_get_executable_path = MSFindSymbol(MSGetImageByName("/usr/lib/libSystem.B.dylib"), "_xpc_bundle_get_executable_path");
	void *p_xpc_bundle_get_executable_path = xpc_bundle_get_executable_path;
	doLog("p_xpc_bundle_get_executable_path\n");
	os_log(OS_LOG_DEFAULT, "p_xpc_bundle_get_executable_path: %p", p_xpc_bundle_get_executable_path);
	MSHookFunction(p_xpc_bundle_get_executable_path, hook_xpc_bundle_get_executable_path, (void **)&ori_xpc_bundle_get_executable_path);
}