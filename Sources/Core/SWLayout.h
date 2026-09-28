#ifndef SW_LAYOUT_H
#define SW_LAYOUT_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* All rectangles use macOS logical points, in global AX coordinates (top-left).
   No AppKit, allocation, IPC, or persistent state in this module. */
typedef struct { double x, y, width, height; } SWRect;
typedef struct {
    uint32_t identifier;
    bool builtIn;
    SWRect frame;
    SWRect visibleFrame;
} SWDisplay;
typedef enum {
    SWLayoutInvalid = 0,
    SWLayoutKeep,
    SWLayoutInternal,
    SWLayoutExternal,
    SWLayoutClamshell
} SWLayoutAction;
typedef struct {
    SWLayoutAction action;
    size_t currentIndex;
    size_t targetIndex;
    SWRect target;
    bool crossesDisplay;
} SWLayoutPlan;

bool SWRectValid(SWRect r);
bool SWRectNear(SWRect a, SWRect b, double tolerance);
double SWRectIntersectionArea(SWRect a, SWRect b);
size_t SWFindDisplay(SWRect window, const SWDisplay *displays, size_t count);
SWRect SWMarginFrame(SWDisplay display, double leftMargin);
/* dockDisplayID: 0 selects built-in; UINT32_MAX means disconnected selection.
   A single connected display always receives the margin. */
SWLayoutPlan SWMakePlan(SWRect window, const SWDisplay *displays, size_t count,
                        uint32_t preferredExternalID, uint32_t dockDisplayID, double leftMargin,
                        double tolerance);
#endif
