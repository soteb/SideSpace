#include "SWLayout.h"
#include <math.h>
#include <float.h>

bool SWRectValid(SWRect r) {
    return isfinite(r.x) && isfinite(r.y) && isfinite(r.width) &&
           isfinite(r.height) && r.width > 0 && r.height > 0;
}
bool SWRectNear(SWRect a, SWRect b, double t) {
    return SWRectValid(a) && SWRectValid(b) && isfinite(t) && t >= 0 &&
        fabs(a.x-b.x) <= t && fabs(a.y-b.y) <= t &&
        fabs(a.width-b.width) <= t && fabs(a.height-b.height) <= t;
}
double SWRectIntersectionArea(SWRect a, SWRect b) {
    if (!SWRectValid(a) || !SWRectValid(b)) return 0;
    double w = fmin(a.x+a.width, b.x+b.width) - fmax(a.x,b.x);
    double h = fmin(a.y+a.height,b.y+b.height) - fmax(a.y,b.y);
    return fmax(w,0) * fmax(h,0);
}
size_t SWFindDisplay(SWRect w, const SWDisplay *ds, size_t n) {
    if (!ds || !n || !SWRectValid(w)) return SIZE_MAX;
    size_t best = SIZE_MAX;
    double bestArea = -1, bestDistance = DBL_MAX;
    for (size_t i = 0; i < n; i++) {
        SWRect d = ds[i].frame;
        if (!SWRectValid(d) || !SWRectValid(ds[i].visibleFrame)) continue;
        double area = SWRectIntersectionArea(w,d);
        double dx = w.x+w.width/2 - (d.x+d.width/2);
        double dy = w.y+w.height/2 - (d.y+d.height/2);
        double distance = dx*dx+dy*dy;
        if (area > bestArea || (area == bestArea && distance < bestDistance)) {
            best = i; bestArea = area; bestDistance = distance;
        }
    }
    return best;
}
SWRect SWMarginFrame(SWDisplay d, double margin) {
    SWRect v = d.visibleFrame;
    if (!SWRectValid(d.frame) || !SWRectValid(v) ||
        !isfinite(margin) || margin < 0) return (SWRect){0};
    double left = fmax(d.frame.x+margin,v.x);
    return (SWRect){left,v.y,v.x+v.width-left,v.height};
}
static SWRect dockTarget(SWDisplay d, size_t n, uint32_t dockID, double margin) {
    bool selected=n==1 || (dockID==0 ? d.builtIn : d.identifier==dockID);
    return SWMarginFrame(d,selected?margin:0);
}
SWLayoutPlan SWMakePlan(SWRect w, const SWDisplay *ds, size_t n,
                        uint32_t preferred, uint32_t dockDisplayID, double margin, double tolerance) {
    SWLayoutPlan p = {.action=SWLayoutInvalid,
                      .currentIndex=SIZE_MAX,.targetIndex=SIZE_MAX};
    if (!isfinite(margin) || margin < 0 || margin > 500 ||
        !isfinite(tolerance) || tolerance < 0) return p;
    size_t current = SWFindDisplay(w,ds,n);
    if (current == SIZE_MAX) return p;
    size_t internal = SIZE_MAX, external = SIZE_MAX;
    for (size_t i=0; i<n; i++) {
        if (!SWRectValid(ds[i].frame) || !SWRectValid(ds[i].visibleFrame)) continue;
        if (ds[i].builtIn) { if (internal == SIZE_MAX) internal=i; }
        else if (external == SIZE_MAX || ds[i].identifier == preferred) external=i;
    }
    p.currentIndex=current;
    p.targetIndex=current;
    p.target=dockTarget(ds[current],n,dockDisplayID,margin);
    if (internal == SIZE_MAX) {
        if (!SWRectValid(p.target) || p.target.width < 100) return p;
        p.action=SWRectNear(w,p.target,tolerance) ? SWLayoutKeep : SWLayoutClamshell;
        return p;
    }
    SWRect internalTarget=dockTarget(ds[internal],n,dockDisplayID,margin);
    if (!SWRectValid(internalTarget) || internalTarget.width < 100) return p;
    if (ds[current].builtIn) {
        p.target=internalTarget;
        p.targetIndex=internal;
        if (!SWRectNear(w,internalTarget,tolerance)) p.action=SWLayoutInternal;
        else if (external == SIZE_MAX) p.action=SWLayoutKeep;
        else {
            p.action=SWLayoutExternal;
            p.targetIndex=external;
            p.target=dockTarget(ds[external],n,dockDisplayID,margin);
            if (!SWRectValid(p.target) || p.target.width < 100) { p.action=SWLayoutInvalid; return p; }
        }
    } else {
        p.action=SWLayoutInternal;
        p.targetIndex=internal;
        p.target=internalTarget;
    }
    p.crossesDisplay = p.currentIndex != p.targetIndex;
    return p;
}
