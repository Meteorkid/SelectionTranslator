#ifndef PSNResolver_h
#define PSNResolver_h

#include <ApplicationServices/ApplicationServices.h>
#include <sys/types.h>

/// Resolves a legacy ProcessSerialNumber to a live PID, or 0 if the sender
/// has already exited. This is isolated in C because Swift marks the
/// deprecated Process Manager API unavailable.
pid_t STProcessIDForSerialNumber(ProcessSerialNumber psn);

#endif /* PSNResolver_h */
