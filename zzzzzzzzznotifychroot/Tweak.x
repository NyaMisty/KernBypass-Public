#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#include <spawn.h>
#include "../config.h"

static UIWindow *window = nil;
static BOOL autoEnabled;

static void easy_spawn(const char *args[]) {
    pid_t pid;
    int status;
    posix_spawn(&pid, args[0], NULL, NULL, (char * const*)args, NULL);
    waitpid(pid, &status, WEXITED);
}

static BOOL isProcessRunning(NSString *processName) {
    BOOL running = NO;

    NSString *command = [NSString stringWithFormat:@"ps ax | grep %@ | grep -v grep | wc -l", processName];

    FILE *pf;
    char data[512];

    pf = popen([command cStringUsingEncoding:NSASCIIStringEncoding],"r");

    if (!pf) {
        fprintf(stderr, "Could not open pipe for output.\n");
        return NO;
    }

    fgets(data, 512, pf);

    int val = (int)[[NSString stringWithUTF8String:data] integerValue];
    if (val != 0) {
        running = YES;
    }

    if (pclose(pf) != 0) {
        fprintf(stderr," Error: Failed to close command stream \n");
    }

    return running;
}

@interface FBSSystemService : NSObject
+ (instancetype)sharedService;
- (int)pidForApplication:(NSString *)bundleId;
@end

@interface RBSProcessIdentity
@property (nonatomic, readonly) NSString *embeddedApplicationIdentifier;
@end

@interface FBProcessExecutionContext
@property (nonatomic, assign) NSDictionary *environment;
@property (nonatomic, assign) RBSProcessIdentity *identity;
@end

@interface FBApplicationProcess
@property (nonatomic, assign) FBProcessExecutionContext *executionContext;
@end

extern CFNotificationCenterRef CFNotificationCenterGetDistributedCenter(void);

BOOL isEnableApplication(NSString *bundleID) {
    NSDictionary *pref = [NSDictionary dictionaryWithContentsOfFile:PREF_PATH];

    if (!pref || pref[bundleID] == nil) {
        return NO;
    }

    return [pref[bundleID] boolValue];
}

int    page_size          = 0x4000;
#include <mach/mach.h>
#include <mach-o/loader.h>
#include <mach-o/dyld_images.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <sys/param.h>
#include <sys/mman.h>
#include <stdint.h>
#include <os/log.h>
#define ___MIN(X, Y) (((X) < (Y)) ? (X) : (Y))

kern_return_t mach_vm_read_overwrite(vm_map_t, mach_vm_address_t,
                                     mach_vm_size_t, mach_vm_address_t,
                                     mach_vm_size_t *);
kern_return_t mach_vm_remap(vm_map_t, mach_vm_address_t *, mach_vm_size_t,
                            mach_vm_offset_t, int, vm_map_t, mach_vm_address_t,
                            boolean_t, vm_prot_t *, vm_prot_t *, vm_inherit_t);
kern_return_t mach_vm_write(vm_map_t, mach_vm_address_t, vm_offset_t,
                            mach_msg_type_number_t);
kern_return_t mach_vm_allocate(vm_map_t, mach_vm_address_t *, mach_vm_size_t, int);
kern_return_t mach_vm_deallocate(vm_map_t, mach_vm_address_t, mach_vm_size_t);
kern_return_t mach_vm_region(vm_map_t, mach_vm_address_t *, mach_vm_size_t *,
                             vm_region_flavor_t, vm_region_info_t,
                             mach_msg_type_number_t *, mach_port_t *);


int patch_many_page__(uint64_t beginaddr, void *data, size_t size) {
    mach_port_t self_port = mach_task_self();

    uint64_t page_align_address = (uint64_t)beginaddr & ~(uint64_t)(page_size - 1);
    uint64_t page_align_size = beginaddr + size - page_align_address;
    uint64_t start_off = beginaddr - page_align_address;
    for (int pageoff = 0; pageoff < page_align_size; pageoff += page_size) {
        uint64_t curpage = page_align_address + pageoff;
        os_log(OS_LOG_DEFAULT, "Patching page %llx!", curpage);
        uint64_t remap_page = (uint64_t)mmap(0, page_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, VM_MAKE_TAG(255), 0);
        if ((void *)remap_page == MAP_FAILED) {
            os_log(OS_LOG_DEFAULT, "mmap page failed! errno %d", errno);
            return 1;
        }
        
        mmap((void *)curpage, page_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, VM_MAKE_TAG(255), 0);

        // copy origin page
        memcpy((void *)remap_page, (void *)curpage, page_size);

        
        if (pageoff == 0) {
            // patch buffer
            memcpy((void *)(remap_page + start_off), (char *)data, ___MIN(page_size - start_off, size));
        } else {
            uint64_t dataoff = pageoff - start_off;
            memcpy((void *)(remap_page), (char *)data + dataoff, ___MIN(page_size, size - dataoff));
        }

        // change permission
        mprotect((void *)remap_page, page_size, PROT_READ | PROT_WRITE);

        mprotect((void *)remap_page, page_size, PROT_READ | PROT_EXEC);
        mach_vm_address_t dest_page_address_ = (mach_vm_address_t)curpage;
        vm_prot_t         curr_protection, max_protection;
        kern_return_t kr = mach_vm_remap(self_port, &dest_page_address_, page_size, 0, VM_FLAGS_OVERWRITE | VM_FLAGS_FIXED, self_port,
                            (mach_vm_address_t)remap_page, TRUE, &curr_protection, &max_protection, VM_INHERIT_COPY);
        if (kr != KERN_SUCCESS) {
            os_log(OS_LOG_DEFAULT, "mach_vm_remap page failed: %d", kr);
            return 2;
        }

        // unmap the origin page
        int err = munmap((void *)remap_page, (mach_vm_address_t)page_size);
        if (err == -1) {
            os_log(OS_LOG_DEFAULT, "munmap page failed: %d", errno);
            return 3;
        }
    
    }
    return 0;
}
int patch_many_page(uint64_t beginaddr, void *data, size_t size) {
    mach_port_t self_port = mach_task_self();

    uint64_t page_align_address = (uint64_t)beginaddr & ~(uint64_t)(page_size - 1);
    uint64_t page_align_size = ((beginaddr + size - page_align_address) + page_size - 1) / page_size * page_size;
    //uint64_t page_align_size = beginaddr + size - page_align_address;
    uint64_t start_off = beginaddr - page_align_address;

    //os_log(OS_LOG_DEFAULT, "Patching page %llx!", curpage);
    uint64_t remap_page = (uint64_t)mmap(0, page_align_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, VM_MAKE_TAG(255), 0);
    if ((void *)remap_page == MAP_FAILED) {
        os_log(OS_LOG_DEFAULT, "mmap page failed! errno %d", errno);
        return 1;
    }
    
    for (uint64_t curpage = page_align_address; curpage <= page_align_address + page_align_size; curpage += page_size) {
        mmap((void *)curpage, page_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, VM_MAKE_TAG(255), 0);
    }

    // copy origin page
    memcpy((void *)remap_page, (void *)page_align_address, page_align_size);

    
    // patch buffer
    memcpy((void *)(remap_page + start_off), (char *)data, size);

    // change permission
    mprotect((void *)remap_page, page_align_size, PROT_READ | PROT_WRITE);

    mprotect((void *)remap_page, page_align_size, PROT_READ | PROT_EXEC);
    mach_vm_address_t dest_page_address_ = (mach_vm_address_t)page_align_address;
    vm_prot_t         curr_protection, max_protection;
    kern_return_t kr = mach_vm_remap(self_port, &dest_page_address_, page_align_size, 0, VM_FLAGS_OVERWRITE | VM_FLAGS_FIXED, self_port,
                        (mach_vm_address_t)remap_page, TRUE, &curr_protection, &max_protection, VM_INHERIT_COPY);
    if (kr != KERN_SUCCESS) {
        os_log(OS_LOG_DEFAULT, "mach_vm_remap page failed: %d", kr);
        return 2;
    }

    // unmap the origin page
    int err = munmap((void *)remap_page, (mach_vm_address_t)page_align_size);
    if (err == -1) {
        os_log(OS_LOG_DEFAULT, "munmap page failed: %d", errno);
        return 3;
    }

    return 0;
}

void recoverCodeSign() {
    NSString *curExec = [[NSBundle mainBundle] executablePath];
    NSString *oriExec = [curExec substringWithRange:NSMakeRange(0,[curExec length] - [@"_kernbypass" length])];
    NSLog(@"Opening original exec %@", oriExec);
    FILE *orifd = fopen([oriExec UTF8String], "rb");
    if (!orifd) {
        NSLog(@"Failed to open original exec!!!");
        exit(88);
    }
    char macho_header[0x2000] = {0};
    size_t readlen = 0;
    if ((readlen = fread(macho_header, 1, sizeof(macho_header), orifd)) != sizeof(macho_header)) {
        NSLog(@"Failed to read original exec!!! actually read %zx", readlen);
        exit(89);
    };
    
    
    uint64_t LC_VMAddr = 0;
    size_t LC_FileOff = 0;
    size_t LC_FileSize = 0;

    struct mach_header_64 *hdr = (struct mach_header_64 *)macho_header;
    struct load_command *curLC = (struct load_command *)(hdr + 1);
    for (int i = 0; i < hdr->ncmds; i++) {
        //NSLog(@"Processing load command %d", curLC->cmd);
        if (curLC->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *curSegLC = (struct segment_command_64 *)curLC;
            NSLog(@"Examining segment %s", curSegLC->segname);
            if (!strcmp(curSegLC->segname, "__LINKEDIT")) {
                LC_VMAddr = curSegLC->vmaddr;
                LC_FileOff = curSegLC->fileoff;
                LC_FileSize = curSegLC->filesize;
            }
        }
        curLC = (struct load_command *)((char *)curLC + curLC->cmdsize);
    }

    NSLog(@"Found ori linkedit vmaddr %llx, fileoff %zx, filesize %zx!", LC_VMAddr, LC_FileOff, LC_FileSize);
    
    uint64_t base = (uint64_t)_dyld_get_image_header(0);
    uint64_t slide = (uint64_t)_dyld_get_image_vmaddr_slide(0);
    NSLog(@"Patching header...");
    if (!!patch_many_page(base, macho_header, sizeof(macho_header))) {
        NSLog(@"Failed to patch header!");
    }
    
    
    NSLog(@"Patching linkedit...");
    fseek(orifd, LC_FileOff, SEEK_SET);
    char *codesign_data = malloc(LC_FileSize);
    fread(codesign_data, LC_FileSize, 1, orifd);
    if (!!patch_many_page(LC_VMAddr + slide, codesign_data, LC_FileSize)) {
        NSLog(@"Failed to patch linkedit blob!");
    }
    fclose(orifd);
    NSLog(@"Finished recovering code sign!");
}

void bypassApplication(NSString *bundleID) {
    int pid = [[%c(FBSSystemService) sharedService] pidForApplication:bundleID];

    if (isEnableApplication(bundleID) && pid != -1) {
        NSLog(@"Bypass enabled for executable: %@", [[NSBundle mainBundle] executablePath]);
        if ([[[NSBundle mainBundle] executablePath] hasSuffix:@"_kernbypass"]) {
            recoverCodeSign();
        }
        
        NSDictionary *info = @{
            @"Pid" : [NSNumber numberWithInt:pid]
        };

        CFNotificationCenterPostNotification(CFNotificationCenterGetDistributedCenter(), CFSTR(Notify_Chrooter), NULL, (__bridge CFDictionaryRef)info, YES);


        kill(pid, SIGSTOP);
        usleep(100 * 1000);
        /*
        const char *exec = [[[NSBundle mainBundle] executablePath] UTF8String];
        const char *args[] = {
            exec,
        };
        posix_spawnattr_t attr;
        posix_spawnattr_init(&attr);
        posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETEXEC);
        posix_spawnattr_setflags(&attr, POSIX_SPAWN_START_SUSPENDED);
        int ret = posix_spawn(&pid, "/Applications/DemoApp.app/kernbypass/nuannuan3HD_patch", NULL, &attr, (char * const*)args, NULL);
        if (!!ret) {
            NSLog(@"fuck Sandbox: posix_spawn %d", ret);
            exit(111);
        };*/
    }
}

%group SpringBoardHook

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)arg1 {
    %orig;
    // Automatically enabled on Reboot and Re-Jailbreak etc
    if (autoEnabled && isProcessRunning(@"changerootfs") == NO) {
        easy_spawn((const char *[]){"/usr/bin/kernbypassd", NULL});
    }
    // Alert prompting for Reboot when using previous version
    if ([[NSFileManager defaultManager] removeItemAtPath:@rebootMem error:nil]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"KernByPass Unofficial"
                                                                       message:@"[Note] Please reboot before Enable!!"
                                                                preferredStyle:UIAlertControllerStyleAlert];

        window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
        window.windowLevel = UIWindowLevelAlert;

        [window makeKeyAndVisible];
        window.rootViewController = [[UIViewController alloc] init];
        UIViewController *vc = window.rootViewController;

        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            window.hidden = YES;
            window = nil;
        }];

        [alert addAction:okAction];

        [vc presentViewController:alert animated:YES completion:nil];
    }
    // Notification from Settings (Only work enable) // dirty code
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(runKernBypassd:) name:@Notify_KernBypassd object:nil];
}
%new
- (void)runKernBypassd:(NSNotification *)notification {
    if (isProcessRunning(@"changerootfs") == NO) {
        // run kernbypassd (dirty code)
        // Runs on SpringBoard because the changerootfs will be killed when called from settings
        // (Disabled after restart of SpringBoard)
        easy_spawn((const char *[]){"/usr/bin/kernbypassd", NULL});
    }
}
%end

%hook FBApplicationProcess
- (void)launchWithDelegate:(id)delegate {
    NSDictionary *env = self.executionContext.environment;
    %orig;
    // Choicy compatible? Note:It doesn't work
    if (env[@"_MSSafeMode"] || env[@"_SafeMode"]) {
        bypassApplication(self.executionContext.identity.embeddedApplicationIdentifier);
    }
}
%end

%end // SpringBoardHook End

static void settingsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:PREF_PATH];
    autoEnabled = (BOOL)[dict[@"autoEnabled"] ?: @NO boolValue];
}

static void callKernBypassd(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *identifier = [[NSBundle mainBundle] bundleIdentifier];
    if ([identifier isEqualToString:@"com.apple.springboard"]) {
        // dirty code
        [[NSNotificationCenter defaultCenter] postNotificationName:@Notify_KernBypassd object:nil userInfo:nil];
    }
}

%ctor {
    // Settings Notifications
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    settingsChanged,
                                    CFSTR(Notify_Preferences),
                                    NULL,
                                    CFNotificationSuspensionBehaviorCoalesce);

    settingsChanged(NULL, NULL, NULL, NULL, NULL);

    // Call KernBypassd Notifications
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    callKernBypassd,
                                    CFSTR(Notify_KernBypassd),
                                    NULL,
                                    CFNotificationSuspensionBehaviorCoalesce);

    NSString *identifier = [[NSBundle mainBundle] bundleIdentifier];

    if ([identifier isEqualToString:@"com.apple.springboard"]) {
        %init(SpringBoardHook);
    } else {
        bypassApplication(identifier);
    }
}
