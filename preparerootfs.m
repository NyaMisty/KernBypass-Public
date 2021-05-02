#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>
#include <stdio.h>

#include "config.h"
#include "kernelhelper/kernel.h"
#include "vnode_utils.h"
#include "utils.h"

#include <sys/syscall.h>
#include <sys/snapshot.h>
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>

#if defined(USE_DEV_FAKEVAR) 
#define FAKEVARDIR "/var/mobile/kernbypass_assetfakevar"
#define FINAL_FAKEVARDIR FAKEROOTDIR"/dev/fakevar"
#elif defined(USE_TMPFS_FAKEVAR)
#define FAKEVARDIR "/var/mobile/kernbypass_asset/fakevar"
#define FINAL_FAKEVARDIR FAKEROOTDIR"/private/var"
#elif defined(USE_DMG)
#define FAKEVAR_DMG "/var/mobile/kernbypass_asset/test.dmg"
#define FINAL_FAKEVARDIR FAKEROOTDIR"/private/var"
#else
#error "SPECIFY FAKEVAR METHOD!"
#endif

void hardlink_var(const char *path) {
    char src[1024];
    const char *relapath = path + strlen(FINAL_FAKEVARDIR);
    snprintf(src, sizeof(src), "/private/var/%s", relapath);
    printf("Linking: %s -> %s\n", src, path);
    //copy_file_in_memory((char *)path, src, true);
    char mountcmd[2048] = {0};
    snprintf(mountcmd, sizeof(mountcmd), "mount_bindfs '%s' '%s'", src, path);
    printf("   exec: %s\n", mountcmd);
    system(mountcmd);
    //force_set_rw(path);
}

void symlink_var(const char *path) {
    char src[1024];
    const char *relapath = path + strlen(FINAL_FAKEVARDIR);
    snprintf(src, sizeof(src), "/private/var/%s", relapath);
    printf("Linking: %s -> %s\n", src, path);
    printf("    rmdir: %d, errno: %d\n", rmdir(path), errno);
    printf("    symlink: %d, errno: %d\n", symlink(src, path), errno);
}

void listdir(const char *name, int indent) {
    DIR *dir;
    struct dirent *entry;

    if (!(dir = opendir(name))) return;
    
    char path[1024];
    int childs = 0;
    while ((entry = readdir(dir)) != NULL) {
        snprintf(path, sizeof(path), "%s/%s", name, entry->d_name);
        if (entry->d_type == DT_DIR) {
            if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
                continue;
            printf("%*s[%s]\n", indent, "", entry->d_name);
            listdir(path, indent + 2);
            childs += 1;
        } else {
/*
#ifdef USE_HARDLINK
            hardlink_var(path);
#else
            symlink_var(path);
#endif
            printf("%*s- %s\n", indent, "", entry->d_name);
            childs += 1;
*/
            continue;
        }
    }
    if (childs == 0) {
        if (indent == 0) {
            printf("FATAL! Empty fakevar root!!\n");
            return;
        }
#ifdef USE_HARDLINK
        hardlink_var(name);
#else
        symlink_var(name);
#endif
    }
    closedir(dir);
}


#if defined(USE_DMG)

int mount_dmg(const char *mountpoint) {
    printf("attaching our fakevar dmg %s\n", FAKEVAR_DMG);
    FILE* fp = popen("attach "FAKEVAR_DMG, "r");
    usleep(1000 * 1000 * 2);
    char buf[100] = {0};
    size_t ret = fread(buf, 1, sizeof(buf) - 1, fp);
    if (ret <= 0) {
        printf("failed to attach dmg!\n");
        return 1;
    }
    printf("got attach command output (%zu bytes): %s\n", ret, buf);
    while (buf[--ret] == '\n');
    buf[ret+1] = 0;

    char *diskpath = strrchr(buf, '\n') + 1;
    if (!(diskpath-1) || strncmp(diskpath, "disk", 4) != 0) {
        printf("Unexpected attach output: %s", diskpath);
        return 1;
    }
    printf("parsed attached disk path %s\n", diskpath);
    
    int err;
    /*
    typedef struct {
        char     *fspec;
        uid_t     hfs_uid;
        gid_t     hfs_gid;
        mode_t    hfs_mask;
        u_int32_t hfs_encoding;
        struct    timezone hfs_timezone;
        int       flags;
        int       journal_tbuffer_size;
        int       journal_flags;
        int       journal_disable;
    } hfs_mount_args;
    hfs_mount_args arg = { 0 };
    arg.fspec = diskpath;
    arg.hfs_uid = 501;
    arg.hfs_gid = 501;
    arg.hfs_mask = 0755;
    int err = mount("hfs", FAKEROOTDIR"/private/var", 0, &arg);
    if(err != 0){
        printf("mount fakevar fs error = %d\n", err);
        return 1;
    }*/
    char command[1000] = {0};
    snprintf(command, sizeof(command), "fsck_hfs /dev/%s", diskpath);
    printf("Executing command: %s\n", command);
    err = system(command);
    if (err != 0) {
        printf("fsck fakevar dmg failed!!\n");
	    return 1;
    }
    snprintf(command, sizeof(command), "mount -t hfs /dev/%s %s", diskpath, mountpoint);
    printf("Executing command: %s\n", command);
    err = system(command);
    if (err != 0) {
        printf("mount devfs error = %d\n", err);
        return 1;
    }
    return 0;
}

int link_folders() {
    if (mount_dmg(FAKEROOTDIR"/private/var") != 0) {
        printf("mount dmg fail!\n");
        return 1;
    }
    listdir(FAKEROOTDIR"/private/var", 0);
    return 0;
}

#elif defined(USE_DEV_FAKEVAR)
int link_folders() {
    printf("Copyiny fakevar dir from: %s\n", FAKEVARDIR);
    if (copy_dir(FAKEVARDIR, FINAL_FAKEVARDIR)) {
        return 1;
    }
    printf("Linking fakevar dir!\n");
    listdir(FINAL_FAKEVARDIR, 0);
    
    printf("Linking fakevar to var!\n");
    copy_file_in_memory(FAKEROOTDIR"/private/var", FINAL_FAKEVARDIR, true);
    return 0;
}

#elif defined(USE_TMPFS_FAKEVAR)
int mount_tmpfs(const char *mountpoint) {
    char command[1000] = {0};
    snprintf(command, sizeof(command), "mount_tmpfs %s", mountpoint);
    printf("Executing command: %s\n", command);
    int err = system(command);
    if (err != 0) {
        printf("mount tmpfs error = %d\n", err);
        return 1;
    }
    return 0;
}

int link_folders() {
    if (mount_tmpfs(FINAL_FAKEVARDIR) != 0) {
        printf("mount tmpfs fail!\n");
        return 1;
    }
    if (copy_dir(FAKEVARDIR, FINAL_FAKEVARDIR)) {
        return 1;
    }
    listdir(FINAL_FAKEVARDIR, 0);
    //listdir(FAKEVARDIR, 0);
    return 0;
}

#else
    #error "Specify a fakevar method!"
#endif


int main(int argc, char *argv[], char *envp[]) {
    
    if (!is_empty(FAKEROOTDIR) && access(FAKEROOTDIR"/private/var/containers", F_OK) == 0) {
        printf("error already mounted\n");
        return 1;
    }
    
    int err = init_kernel();
    if (err) {
        return 1;
    }
    
    if (is_empty(FAKEROOTDIR)) {

        int fd = open("/", O_RDONLY);
        
        printf("open root directory fd = %d\n", fd);
        
        printf("trying to mount kernbypass snapshot...");
        err = fs_snapshot_mount(fd, FAKEROOTDIR, "kernbypass", 0);
        
        if (err != 0) {
            printf("failed to mount kernbypass snapshot(error %d), fallbacking to orig-fs\n", err);

            err = fs_snapshot_mount(fd, FAKEROOTDIR, "orig-fs", 0);
            if (err != 0) {
                printf("mount snapshot error = %d\n", err);
                return 1;
            }
        }
        
        err = mount("devfs", FAKEROOTDIR"/dev", 0, 0);
        
        if (err != 0) {
            printf("mount devfs error = %d\n", err);
            return 1;
        }
        
        close(fd);
    }
    
    return link_folders();
}
