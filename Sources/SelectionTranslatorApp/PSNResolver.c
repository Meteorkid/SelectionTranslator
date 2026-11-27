#include "PSNResolver.h"

pid_t STProcessIDForSerialNumber(ProcessSerialNumber psn) {
    pid_t pid = 0;
    if (GetProcessPID(&psn, &pid) != noErr) {
        return 0;
    }
    return pid;
}
