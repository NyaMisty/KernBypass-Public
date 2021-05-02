#include "kernel.h"
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>

#define kCFCoreFoundationVersionNumber_iOS_12_0    (1535.12)
#define kCFCoreFoundationVersionNumber_iOS_13_0_b2 (1656)
#define kCFCoreFoundationVersionNumber_iOS_13_0_b1 (1652.20)
#define kCFCoreFoundationVersionNumber_iOS_14_0_b1 (1740)

#include "../firmware.h"
//---------maphys and vnodebypass----------//
//Thanks to 0x7ff & @XsF1re
//original code : https://github.com/0x7ff/maphys/blob/master/maphys.c
//original code : https://github.com/XsF1re/vnodebypass/blob/master/main.m

uint32_t off_p_pid = 0;
uint32_t off_p_pfd = 0;
uint32_t off_fd_rdir = 0;
uint32_t off_fd_cdir = 0;
uint32_t off_vnode_iocount = 0;
uint32_t off_vnode_usecount = 0;

int offset_init() {
    if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_14_0_b1) {
        // ios 14
        off_p_pid = 0x68;
        off_p_pfd = 0xf8;
        off_fd_rdir = 0x40;
        off_fd_cdir = 0x38;
        off_vnode_iocount = 0x64;
        off_vnode_usecount = 0x60;
        return 0;
    }

    if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_13_0_b2) {
        // ios 13
        off_p_pid = 0x68;
        off_p_pfd = 0x108;
        off_fd_rdir = 0x40;
        off_fd_cdir = 0x38;
        off_vnode_iocount = 0x64;
        off_vnode_usecount = 0x60;
        return 0;
    }

    if (kCFCoreFoundationVersionNumber == kCFCoreFoundationVersionNumber_iOS_13_0_b1) {
        //ios 13b1
        printf("iOS 13.0 beta1 not supported");
        return -1;
    }

    if (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_13_0_b1 && kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_12_0) {
        //ios 12
        off_p_pid = 0x60;
        off_p_pfd = 0x100;
        off_fd_rdir = 0x40;
        off_fd_cdir = 0x38;
        off_vnode_iocount = 0x64;
        off_vnode_usecount = 0x60;
        return 0;
    }

    return -1;
}

//Use JelbrekLib
#if defined(USE_JELBREK_LIB)
// shim
#include "jelbrekLib.h"
#elif defined(USE_DIMENTIO)
#include "libdimentio.h"
#elif defined(USE_LIBKRW)
#include "libkrw.h"
#include "libdimentio.h"
#endif

uint32_t kernel_read32(uint64_t where) {
#if defined(USE_JELBREK_LIB)
    return KernelRead_32bits(where);
#elif defined(USE_DIMENTIO)
    uint32_t out = 0;
	kread_buf_tfp0(where, &out, sizeof(uint32_t));
	return out;
#elif defined(USE_LIBKRW)
    uint32_t out = 0;
    kread(where, &out, sizeof(uint32_t));
    return out;
#else
    #error "fuck"
#endif
}

uint64_t kernel_read64(uint64_t where) {
#if defined(USE_JELBREK_LIB)
    return KernelRead_64bits(where);
#elif defined(USE_DIMENTIO)
    uint64_t out;
	kread_buf_tfp0(where, &out, sizeof(uint64_t));
	return out;
#elif defined(USE_LIBKRW)
    uint64_t out = 0;
    kread(where, &out, sizeof(uint64_t));
    return out;
#else
    #error "fuck"
#endif
}

void kernel_write32(uint64_t where, uint32_t what) {
#if defined(USE_JELBREK_LIB)
    KernelWrite_32bits(where, what);
#elif defined(USE_DIMENTIO)
    uint32_t _what = what;
	kwrite_buf_tfp0(where, &_what, sizeof(uint32_t));
#elif defined(USE_LIBKRW)
    uint32_t _what = what;
	kwrite((void *)&_what, where, sizeof(uint32_t));
#endif
}

void kernel_write64(uint64_t where, uint64_t what) {
#if defined(USE_JELBREK_LIB)
    KernelWrite_64bits(where, what);
#elif defined(USE_DIMENTIO)
    uint64_t _what = what;
	kwrite_buf_tfp0(where, &_what, sizeof(uint64_t));
#elif defined(USE_LIBKRW)
    uint64_t _what = what;
	kwrite((void *)&_what, where, sizeof(uint64_t));
#endif
}

void kernel_write(uint64_t where, void *buf, size_t size) {
#if defined(USE_JELBREK_LIB)
    KernelWrite(where, buf, size);
#elif defined(USE_DIMENTIO)
	kwrite_buf_tfp0(where, buf, size);
#elif defined(USE_LIBKRW)
	kwrite(buf, where, size);
#endif
}

void kernel_read(uint64_t where, void *buf, size_t size) {
#if defined(USE_JELBREK_LIB)
    KernelRead(where, buf, size);
#elif defined(USE_DIMENTIO)
	kread_buf_tfp0(where, buf, size);
#elif defined(USE_LIBKRW)
	kread(where, buf, size);
#endif
}


#ifndef USE_JELBREK_LIB
uint64_t proc_of_pid(pid_t pid) {
    uint64_t proc = kernel_read64(allproc);
    uint64_t current_pid = 0;

    while (proc) {
        current_pid = kernel_read32(proc + off_p_pid);
        //printf("proc_of_pid: %llx %llu\n", proc, current_pid);
        if (current_pid == pid) return proc;
        proc = kernel_read64(proc);
    }

    return 0;
}
#endif

kern_return_t __kread_buf_wrap(kaddr_t from, void *to, mach_vm_size_t sz) {
    return kread(from, to, sz);
}
kern_return_t __kwrite_buf_wrap(kaddr_t to, const void *from, mach_msg_type_number_t sz) {
    return kwrite((void *)from, to, sz);
}

int t1sz_boot = 0;
uint64_t kxpacd(uint64_t pacPtr) {
    if(t1sz_boot != 0) {
		pacPtr |= ~((1ULL << (64U - t1sz_boot)) - 1U);
	}
    return pacPtr;
}


int init_kernel() {
    cpu_subtype_t subtype;
	size_t sz = sizeof(subtype);
    if(sysctlbyname("hw.cpusubtype", &subtype, &sz, NULL, 0) == 0) {
		if(subtype == CPU_SUBTYPE_ARM64E) {
			t1sz_boot = 25;
		}
    } else {
        printf("failed to get cpu type!\n");
        return 1;
    }

#if defined(USE_JELBREK_LIB)
    if (init_tfp0() != KERN_SUCCESS) {
        printf("get tfp0 failed!\n");
        return 1;
    }
    uint64_t kbase = get_kbase(&kslide);

    if (kbase == 0) {
        printf("failed get_kbase\n");
        return 1;
    }

    int err = init_with_kbase(tfp0, kbase, NULL);
    if (err) {
        printf("init failed: %d\n", err);
        return 1;
    }

    err = offset_init();
    if (err) {
        printf("offset init failed: uint64_t proc_of_pid(pid_t pid: %d\n", err);
        return 1;
    }

    uint64_t proc = kernel_read64(allproc);
    uint64_t current_pid = 0;

    while (proc) {
        current_pid = kernel_read32(proc + off_p_pid);
        if (current_pid == pid) return proc;
        proc = kernel_read64(proc);
    }
    return 0;
//Not use jelbrekLib
#elif defined(USE_DIMENTIO)
  printf("======= init_kernel =======\n");

  if (dimentio_init(0, NULL, NULL) != KERN_SUCCESS) {
      printf("failed dimentio_init!\n");
      return 1;
  }

  if (init_tfp0() != KERN_SUCCESS) {
      printf("failed init_tfp0!\n");
      return 1;
  }

  if (kbase == 0) {
      printf("failed get kbase\n");
      return 1;
  }

  kern_return_t err = offset_init();

  if (err) {
      printf("offset init failed: %d\n", err);
      return 1;
  }
  return 0;
#elif defined(USE_LIBKRW)
    uint64_t curkbase = 0;
    kbase(&curkbase);
    if (dimentio_init(curkbase, __kread_buf_wrap, __kwrite_buf_wrap) != KERN_SUCCESS) {
      printf("failed dimentio_init!\n");
      return 1;
    }
    kern_return_t err = offset_init();
    if (err) {
      printf("offset init failed: %d\n", err);
      return 1;
    }
    return 0;
#endif
}