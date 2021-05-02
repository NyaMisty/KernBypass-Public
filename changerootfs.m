#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdint.h>
#include <dirent.h>

#include "config.h"
#include "kernelhelper/kernel.h"
#include <sys/ucred.h>
#include "vnode_utils.h"
#include "utils.h"

extern CFNotificationCenterRef CFNotificationCenterGetDistributedCenter(void);

void set_sandbox(uint64_t proc, uint64_t *pSandboxLabel) {
    uint64_t ucred = kernel_read64(proc + 0xf0); // confirmed on ios 14.0 b2 xr & 14.2 ipad air3

    printf("proc_ucred: %llx\n", ucred);

    ucred = kxpacd(ucred);

    printf("unpac-proc_ucred: %llx\n", ucred);

    uint64_t ucred_label = kernel_read64(ucred + 0x78); // ucred->cr_label
    printf("proc_ucred_label: %llx\n", ucred_label);

    ucred_label = kxpacd(ucred_label);
    printf("unpac-proc_ucred_label: %llx\n", ucred_label);

    uint64_t ucred_label_perpolicy_0 = kernel_read64(ucred_label + 8); // ucred->cr_label->l_perpolicy[1]
    printf("original sandbox polify: %llx\n", ucred_label_perpolicy_0);

    uint64_t ucred_label_perpolicy_1 = kernel_read64(ucred_label + 16); // ucred->cr_label->l_perpolicy[1]
    printf("original sandbox polify: %llx\n", ucred_label_perpolicy_1);

    //kernel_write64(ucred_label + 8, 0);
    if (!*pSandboxLabel) {
        kernel_write64(ucred_label + 16, 0);
        *pSandboxLabel = ucred_label_perpolicy_1;
    } else {
        kernel_write64(ucred_label + 16, *pSandboxLabel);
    }
}

uint64_t rootvp;
vnode_lookup_context rootvp_lookupContext;

bool prepare_vnode() {
    int err = vnode_lookup_get(FAKEROOTDIR, &rootvp_lookupContext);
    if (err) {
        printf("failed to lookup fakeroot vp! err: %d", err);
        return false;
    }
    rootvp = rootvp_lookupContext.vp;
    //printf("Ori rootvp info:\n    ");
    //print_vnode_info(rootvp);
    
    return true;
}

bool change_rootvnode(uint64_t vp, uint64_t proc) {
    
    if (!vp) return false;
    //printf("vp:%"PRIx64"\n",vp);

    //exit(110);

    uint64_t filedesc = kernel_read64(proc + off_p_pfd);
    //printf("reading pfd:%"PRIx64"\n",filedesc);

    uint64_t ori_cdir_vp = kernel_read64(filedesc + off_fd_cdir);
    //printf("Ori cdir vp info:\n    ");
    //print_vnode_info(ori_cdir_vp);
    char cdir_path[0x300] = {0};
    get_vnode_path(ori_cdir_vp, cdir_path, NULL);
    vnode_lookup_close(cdir_path, ori_cdir_vp);
    vnode_ref(vp);
    kernel_write64(filedesc + off_fd_cdir, vp);
    //printf("writing fd_cdir:%"PRIx64"\n",(filedesc + off_fd_cdir));

    uint64_t ori_rdir_vp = kernel_read64(filedesc + off_fd_rdir);
    if (ori_rdir_vp) {
        char rdir_path[0x300] = {0};
        get_vnode_path(ori_rdir_vp, rdir_path, NULL);
        vnode_lookup_close(rdir_path, ori_rdir_vp);
    }
    int usecount = vnode_ref(vp);
    kernel_write64(filedesc + off_fd_rdir, vp);
    //printf("writing fd_rdir:%"PRIx64"\n",(filedesc + off_fd_rdir));
    
    printf("rootvp cur usecount: %d\n", usecount);
    
    uint32_t fd_flags = kernel_read32(filedesc + 0x58);
    //printf("setting up fd_flags:%"PRIx64"\n",filedesc + 0x58);

    fd_flags |= 1; // FD_CHROOT = 1;
    
    kernel_write32(filedesc + 0x58, fd_flags);
    //printf("finish fd_flags:%"PRIx32"\n",fd_flags);
    return true;
}

void changeroot(pid_t pid) {
    //uint64_t rootvp = get_vnode_with_chdir(FAKEROOTDIR);
    //uint64_t rootvp = get_vnode_with_chdir("/");

    //set_vnode_usecount(rootvp, 0x2000, 0x2000);    

    uint64_t proc = proc_of_pid(pid);
    //printf("getting proc_t:%"PRIx64"\n",proc);
    if (!proc) return;

    /*uint64_t sandboxLabel = 0;
    set_sandbox(proc, &sandboxLabel);
    usleep(100 * 1000);
    kill(pid, SIGCONT);
    usleep(400 * 1000);*/
    change_rootvnode(rootvp, proc);
    usleep(100 * 1000);
    //set_sandbox(proc, &sandboxLabel);
    kill(pid, SIGCONT);
    
}

void receive_notify_chrooter(CFNotificationCenterRef center,
                             void * observer,
                             CFStringRef name,
                             const void * object,
                             CFDictionaryRef userInfo) {
                                 
    NSDictionary *info = (__bridge NSDictionary*)userInfo;
    
    NSLog(@"receive notify %@", info);
    
    pid_t pid = [info[@"Pid"] intValue];
    changeroot(pid);
}

int main(int argc, char *argv[], char *envp[]) {
    
    int err = init_kernel();
    if (err) {
        printf("error init_kernel\n");
        return 1;
    }
    
    if (is_empty(FAKEROOTDIR) || access(FAKEROOTDIR"/private/var/containers", F_OK) != 0) {
        printf("error fakeroot not mounted\n");
        return 1;
    }

    if (!prepare_vnode()) {
        printf("error in prepare_vnode!\n");
        return 1;
    }
    

    if (argc > 1) {
        int target = atoi(argv[1]);
        changeroot(target);
        return 0;
    }

    CFNotificationCenterAddObserver(CFNotificationCenterGetDistributedCenter(),
                                    NULL,
                                    receive_notify_chrooter,
                                    CFSTR(Notify_Chrooter),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    printf("start changerootfs\n");

    CFRunLoopRun();

    return 1;
}
