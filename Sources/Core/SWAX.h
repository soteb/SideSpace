#ifndef SW_AX_H
#define SW_AX_H
#include <sys/types.h>
#include <ApplicationServices/ApplicationServices.h>
#include "SWLayout.h"
/* Returned window is owned by the caller (CFRelease). AX IPC belongs on the
   serial work queue, never on AppKit's main event loop. */
AXError SWAXCopyWindow(pid_t pid, AXUIElementRef *window);
AXError SWAXReadFrame(AXUIElementRef window,SWRect *frame);
bool SWAXIsMinimized(AXUIElementRef window);
bool SWAXIsFullScreen(AXUIElementRef window);
bool SWAXHasSheet(AXUIElementRef window);
AXError SWAXRestoreAndRaise(AXUIElementRef window);
/* shouldStop runs between AX writes. NULL never stops. A true result leaves any
   earlier write in place and returns kAXErrorCannotComplete. */
typedef bool (*SWAXShouldStop)(void *context);
AXError SWAXApplyFrame(AXUIElementRef window,SWRect target,SWAXShouldStop shouldStop,void *context);
const char *SWAXErrorMessage(AXError error);
#endif
