#include <stdio.h>

#include "kernelhelper/kernel.h"
#include "vnode_utils.h"

int main(int argc, char *argv[], char *envp[]) {
    if (argc != 4) {
        printf("Usage: setmntflag [set|clr|get] /XXX 0xXXXX\n");
        return 1;
    }

    int err = init_kernel();
    if (err) {
        printf("error init_kernel\n");
        return 1;
    }

    bool isset = false;
    if (!strcmp(argv[1], "set")) {
        isset = true;
    } else if (!strcmp(argv[1], "clr")) {
        isset = false;
    } else if (!strcmp(argv[1], "get")) {
        vnode_lookup_context context = {0};
        vnode_lookup_get(argv[2], &context);
        print_vnode_info(context.vp);
        vnode_lookup_put(&context);
        uint32_t flag = force_mntflag(argv[2], NULL);
        printf("mntflag: 0x%x\n", flag);
        return 0;
    } else {
        exit(1);
    }

    uint32_t pflag = 0;
    if (!strcmp(argv[3], "UNION")) {
        pflag = MNT_UNION;
    } else if (!strcmp(argv[3], "RDONLY")) {
        pflag = MNT_RDONLY;
    } else if (!strcmp(argv[3], "NOSUID")) {
        pflag = MNT_NOSUID;
    }

    uint32_t flag = force_mntflag(argv[2], NULL);
    if (flag == 0xffffffff) {
        printf("failed to get original mnt_flag!\n");
        exit(1);
    }
    uint32_t oriflag = flag;
    if (isset) {
        flag |= pflag;
    } else {
        flag &= ~pflag;
    }
    printf("setting flag from 0x%x to 0x%x\n", oriflag, flag);
    force_mntflag(argv[2], &flag);
    return 0;
}
