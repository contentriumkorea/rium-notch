#include <stdint.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/sysctl.h>
#include <unistd.h>

int rium_claude_catches_sigint(int pid, uint64_t sec, uint64_t usec) {
    struct kinfo_proc info = {0};
    size_t size = sizeof(info);
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    if (pid <= 1 || usec >= 1000000 ||
        sysctl(mib, 4, &info, &size, NULL, 0) != 0 || size != sizeof(info)) return 0;
    return info.kp_proc.p_pid == pid && info.kp_eproc.e_ucred.cr_uid == geteuid() &&
        (uint64_t)info.kp_proc.p_starttime.tv_sec == sec &&
        (uint64_t)info.kp_proc.p_starttime.tv_usec == usec &&
        (info.kp_proc.p_sigcatch & (1u << (SIGINT - 1))) != 0;
}
