#import <os/log.h>
#include "substrate.h"
#include <stdlib.h>
#include <fcntl.h>
#include <string.h>
#include <xpc/xpc.h>

%hook OSLaunchdJob

- (id)initWithPlist:(xpc_object_t)obj domain:(id)domain {
	const char *desc = xpc_copy_description(obj);
	if (!desc) {
		return %orig;
	}
	os_log(OS_LOG_DEFAULT, "RunningBoard launchd req: %{public}s", desc);
	free((void *)desc);

	xpc_object_t args = xpc_dictionary_get_array(obj, "ProgramArguments");
	const char *mainExec = xpc_array_get_string(args, 0);
	os_log(OS_LOG_DEFAULT, "got main exec %{public}s!", mainExec);
	char pathbuf[0x300] = {0};
	strcpy(pathbuf, mainExec);
	strcat(pathbuf, "_kernbypass");
	os_log(OS_LOG_DEFAULT, "check kernbypass stub: %{public}s", pathbuf);
	if (!access(pathbuf, F_OK)) {
		os_log(OS_LOG_DEFAULT, "patching main exec into ours: %{public}s", pathbuf);
		xpc_array_set_string(args, 0, pathbuf);
	}
	return %orig;
}

%end

%ctor {
	%init;
}