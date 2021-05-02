//---------jelbrekLib------//
//Thanks to @Jakeashacks
//original code : https://github.com/jakeajames/jelbrekLib/blob/master/vnode_utils.h

#include "vnode_utils.h"

unsigned off_v_mount = 0xd8;             // vnode::v_mount
unsigned off_mnt_flag = 0x70;            // mount::mnt_flag
unsigned off_mnt_kern_flag = 0x74;            // mount::mnt_kern_flag


uint64_t current_proc() {
    uint64_t proc = proc_of_pid(getpid());
    //printf("proc: %llx\n", proc);
    return proc;
}


uint64_t get_devvp(uint64_t vp) {
    uint64_t p_mount = kernel_read64(vp + off_v_mount);
    uint64_t kxpacd_mount = kxpacd(p_mount);
    uint64_t devvp = kernel_read64(kxpacd_mount + 0x980);
    return devvp;
}

char *get_vnode_name(uint64_t vp) {
    uint64_t vp_nameaddr = kernel_read64(vp + 0xb8);
    char buf[0x100] = { 0 };
    kernel_read(vp_nameaddr, buf, sizeof(buf));
    int buflen = strlen(buf) + 1;
    char *ret = malloc(buflen);
    strcpy(ret, buf);
    return ret;
}

void get_vnode_path(uint64_t targetvp, char *path, int *path_len) {
    #define VROOT 0x000001 /* root of its file system */
    char buf[MAXPATHLEN + 1] = {0};
    char *buf_end            = &buf[MAXPATHLEN];
    //char v_name[256]         = {0};

    vnode_lookup_context rootContext =  {0};
    vnode_lookup_get("/", &rootContext);
    uint64_t rootpv = rootContext.vp;
    vnode_lookup_put(&rootContext);
    uint64_t pv        = targetvp;
    while (pv != 0 && pv != rootpv) {
        char *v_name = get_vnode_name(pv);
        strcpy(buf_end - strlen(v_name) - 1, v_name);
        buf_end[-1] = '/';
        buf_end     = buf_end - strlen(v_name) - 1;
        free(v_name);

        uint32_t v_flag = kernel_read32(pv + 0x54); // KERN_STRUCT_OFFSET(vnode, v_flag)
        if (v_flag & VROOT) {
            break;
        }

        //lastpv = pv;
        uint64_t p_vparent = kernel_read64(pv + 0xc0); // v_parent
        uint64_t kxpacd_parent = kxpacd(p_vparent);
        printf("v_parent: %llx\n", kxpacd_parent);
        pv = kxpacd_parent;
        //exit(222);
    }
    *(--buf_end)                 = '/';
    buf_end[strlen(buf_end) - 1] = 0;
    strcpy(path, buf_end);
    if (path_len) {
        *path_len = strlen(path);
    }
}

void print_vnode_info(uint64_t vp) {
    uint32_t usecount = kernel_read32(vp + off_vnode_usecount);
    uint32_t iocount = kernel_read32(vp + off_vnode_iocount);
    char vnode_path[0x300] = {0};
    get_vnode_path(vp, vnode_path, NULL);
    uint64_t devvp = get_devvp(vp);
    char *devvpname = get_vnode_name(devvp);
    printf("vp = 0x%llx, usecount = %d, iocount = %d, vppath = %s, devvp = 0x%llx, devvpname = %s\n",
                vp, usecount, iocount, vnode_path, devvp, devvpname);
    //free(vpname);
    free(devvpname);
}

errno_t vnode_lookup_by_fd(const char *path, uint64_t *vpp, int *ret_fd) {
    int fd = open(path, O_RDONLY); // both ok for file and dir
    if (fd == -1) {
        return errno;
    }
    printf("got fd: %d\n", fd);

    uint64_t proc = current_proc();
    
    uint64_t filedesc = kernel_read64(proc + off_p_pfd);
    if (!filedesc) {
        exit(13);
    }

    uint64_t ofiles = kernel_read64(filedesc + 0x0);
    if (!ofiles) {
        exit(13);
    }
    printf("ofiles: %llx\n", ofiles);
    
    uint64_t fileproc = kernel_read64(ofiles + 8 * fd);
    if (!fileproc) {
        exit(13);
    }
    printf("fileproc: %llx\n", fileproc);
    
    uint64_t fp_glob = kernel_read64(fileproc + 16);
    if (!fp_glob) {
        exit(14);
    }
    printf("fp_glob: %llx\n", fp_glob);

    uint64_t fg_data = kernel_read64(fp_glob + 56);
    if (!fg_data) {
        exit(14);
    }
    printf("fg_data: %llx\n", fg_data);
    *vpp = fg_data; 
    printf("vpname: %s\n", get_vnode_name(*vpp));
    return 0;
}

uint32_t vnode_unref(uint64_t vp) {
    uint32_t usecount = kernel_read32(vp + off_vnode_usecount);
    if (usecount == 0) {
        printf("vp %llx's usecount is already zero!\n", vp);
        exit(111);
    }
    kernel_write32(vp + off_vnode_usecount, usecount - 1);
    return usecount - 1;
}

uint32_t vnode_ref(uint64_t vp) {
    uint32_t usecount = kernel_read32(vp + off_vnode_usecount);
    kernel_write32(vp + off_vnode_usecount, usecount + 1);
    return usecount + 1;
}

void set_vnode_usecount(uint64_t vnode_ptr, uint32_t usecount, uint32_t iocount) {
    if (vnode_ptr == 0) return;
    kernel_write32(vnode_ptr + off_vnode_usecount, usecount);
    kernel_write32(vnode_ptr + off_vnode_iocount, iocount);
}

uint64_t vnode_lookup_get(const char *path, vnode_lookup_context *lookupContext) {
    uint64_t vp = 0;
    int fd = -1;
    vnode_lookup_by_fd(path, &vp, &fd);
    lookupContext->vp = vp;
    lookupContext->ptr2 = fd;
    return 0;
    //uint32_t usecount = kernel_read32(vp + off_vnode_usecount);
    //kernel_write32(vp + off_vnode_usecount, usecount+1);
}

void vnode_lookup_put(vnode_lookup_context *lookupContext) {
    //kernel_write32(vp + off_vnode_usecount, usecount-1);`
    close((int)lookupContext->ptr2);
}

int vnode_lookup_close(const char *path, uint64_t orivp) {
    vnode_lookup_context context = {0};
    vnode_lookup_get(path, &context);
    uint64_t vp = context.vp;
    if (vp != orivp) {
        printf("failed to re-get the same vp for path %s!\n", path);
    }
    vnode_unref(orivp);
    vnode_lookup_put(&context);
    return 0;
}


uint32_t force_mntflag(const char *path, uint32_t *flag) {
    //uint64_t orig = _get_vnode_with_chdir_noget(path);
    vnode_lookup_context context = {0};
    int err = vnode_lookup_get(path, &context);
    uint64_t orig = context.vp;
    if (err || !orig) {
        vnode_lookup_put(&context);
        return 0xffffffff;
    }
    printf("got vp: %llx\n", orig);
    uint64_t mount = kernel_read64(orig + off_v_mount);
    uint64_t kxpacd_mount = kxpacd(mount);
    printf("  %s: mount %llx\n", path, kxpacd_mount);
    
    uint32_t oriflag = kernel_read32(kxpacd_mount + off_mnt_flag);
    printf("  %s: oriflag %x\n", path, oriflag);
    if (flag) {
        uint32_t newflag = *flag;
        kernel_write32(kxpacd_mount + off_mnt_flag, newflag);
    }
    vnode_lookup_put(&context);
    return oriflag;
}

/*
uint64_t _get_vnode_with_chdir_noget(const char *path) {
    int err = chdir(path);
    printf("chdir: %d\n", err);

    if (err) return 0;

    uint64_t proc = proc_of_pid(getpid());
    printf("proc: %llx\n", proc);

    uint64_t filedesc = kernel_read64(proc + off_p_pfd);
    printf("filedesc: %llx\n", filedesc);

    uint64_t vp = kernel_read64(filedesc + off_fd_cdir);
    printf("vp: %llx\n", vp);

    return vp;
}

uint64_t get_vnode_with_chdir(const char *path) {
    uint64_t vp = _get_vnode_with_chdir_noget(path);
    if (!vp) {
        printf("failed to get vp of path %s\n", path);
        exit(10);
        return 0;
    }

    uint32_t usecount = kernel_read32(vp + off_vnode_usecount);
    printf("vnode_get: usecount: %x\n", usecount);

    uint32_t iocount = kernel_read32(vp + off_vnode_iocount);
    printf("vnode_get: iocount: %x\n", iocount);

    kernel_write32(vp + off_vnode_usecount, usecount+1);
    kernel_write32(vp + off_vnode_iocount, iocount+1);

    chdir("/");
    return vp;
}

uint64_t release_vnode_with_chdir(const char *path, uint64_t target_vp) {
    uint64_t vp = _get_vnode_with_chdir_noget(path);
    if (!vp) {
        printf("failed to get vp of path %s\n", path);
        exit(10);
        return 0;
    }

    if (vp != target_vp) {
        chdir("/");
        printf("failed to re-get vp to release vp for path %s\n", path);
        exit(11);
    }

    uint32_t usecount = kernel_read32(vp + off_vnode_usecount);
    printf("vnode_put: usecount: %x\n", usecount);

    uint32_t iocount = kernel_read32(vp + off_vnode_iocount);
    printf("vnode_put: iocount: %x\n", iocount);

    kernel_write32(vp + off_vnode_usecount, usecount-1);
    kernel_write32(vp + off_vnode_iocount, iocount-1);

    chdir("/");
    return vp;
    
}


void force_set_rw_remount(const char *path, void (*remouter)(const char *, const char *)) {
    uint64_t orig = _get_vnode_with_chdir_noget(path);
    if (!orig) {
        return;
    }
    uint32_t oriflag = kernel_read32(kxpacd_mount + off_mnt_flag);
    uint32_t orikernflag = kernel_read32(kxpacd_mount + off_mnt_kern_flag);
    uint32_t newflag = oriflag & (~1);
    printf("  %s: oriflag 0x%x orikernflag 0x%x\n", path, oriflag, orikernflag);
    kernel_write32(kxpacd_mount + off_mnt_flag, newflag);

    remouter(path, devpath);
    chdir("/");

    //exit(250);
}

bool copy_file_in_memory(char *original, char *replacement, bool set_usecount) {

    uint64_t orig = get_vnode_with_chdir(original);
    uint64_t fake = get_vnode_with_chdir(replacement);

    if (orig == 0 || fake == 0) {
        printf("hardlink error orig = %llu, fake = %llu\n", orig, fake);
        return false;
    }
    printf("linking vnode %llx to %llx\n", orig, fake);
    //return true;
    struct vnode rvp, fvp;
    kernel_read(orig, &rvp, sizeof(struct vnode));
    kernel_read(fake, &fvp, sizeof(struct vnode));

    fvp.v_usecount = rvp.v_usecount;
    fvp.v_kusecount = rvp.v_kusecount;
    //fvp.v_parent = rvp.v_parent; ?
    fvp.v_freelist = rvp.v_freelist;
    fvp.v_mntvnodes = rvp.v_mntvnodes;
    fvp.v_ncchildren = rvp.v_ncchildren;
    fvp.v_nclinks = rvp.v_nclinks;

    kernel_write(orig, &fvp, sizeof(struct vnode));

    if (set_usecount) {
        set_vnode_usecount(orig, 0x2000, 0x2000);
        set_vnode_usecount(fake, 0x2000, 0x2000);
    }
    return true;

}
*/