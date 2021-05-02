#include <stdio.h>

#include "kernelhelper/kernel.h"
#include "vnode_utils.h"

struct hfs_mount_args {
	const char	*fspec;			/* block special device to mount */
	uid_t	hfs_uid;		/* uid that owns hfs files (standard HFS only) */
	gid_t	hfs_gid;		/* gid that owns hfs files (standard HFS only) */
	mode_t	hfs_mask;		/* mask to be applied for hfs perms  (standard HFS only) */
	uint32_t hfs_encoding;		/* encoding for this volume (standard HFS only) */
	struct	timezone hfs_timezone;	/* user time zone info (standard HFS only) */
	int		flags;			/* mounting flags, see below */
	int     journal_tbuffer_size;   /* size in bytes of the journal transaction buffer */
	int		journal_flags;          /* flags to pass to journal_open/create */
	int		journal_disable;        /* don't use journaling (potentially dangerous) */
};


int main(int argc, char *argv[], char *envp[]) {
    if (argc != 5) {
        printf("Usage: rawmount fstype mountpoint mount_flag devpath\n");
        return 1;
    }
    
    struct hfs_mount_args mountarg = {0};
    mountarg.fspec = argv[4];
    uint32_t flag = 0;
    if (argv[3][0] == '0' && argv[3][1] == 'x') {
        sscanf(argv[3], "0x%x", &flag);
    } else {
        sscanf(argv[3], "%d", &flag);
    }
    printf(
        "calling mount with: \n"
        "   fstype: %s\n"
        "   mountpoint: %s\n"
        "   flag: %d\n"
        "   devpath: %s\n", argv[1], argv[2], flag, mountarg.fspec);
    mount(argv[1], argv[2], flag, &mountarg);
    return 0;
}
