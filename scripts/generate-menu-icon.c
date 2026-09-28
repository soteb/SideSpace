/* Build-time vector artwork generator; not linked into the application.
 * clang scripts/generate-menu-icon.c -framework CoreGraphics -framework CoreFoundation -o /tmp/smartwindow-menu-icon
 * /tmp/smartwindow-menu-icon Resources/MenuBarIcon.pdf
 */
#include <CoreGraphics/CoreGraphics.h>
#include <CoreFoundation/CoreFoundation.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL,
        (const UInt8 *)argv[1], (CFIndex)strlen(argv[1]), false);
    if (!url) return 1;
    CGRect bounds = CGRectMake(0, 0, 18, 16);
    CGContextRef context = CGPDFContextCreateWithURL(url, &bounds, NULL);
    CFRelease(url);
    if (!context) return 1;
    CGPDFContextBeginPage(context, NULL);
    CGContextSetGrayStrokeColor(context, 0, 1);
    CGContextSetGrayFillColor(context, 0, 1);
    CGContextSetLineWidth(context, 1.5);
    CGPathRef frame = CGPathCreateWithRoundedRect(
        CGRectMake(0.75, 1.75, 16.5, 12.5), 2.25, 2.25, NULL);
    CGContextAddPath(context, frame);
    CGContextStrokePath(context);
    CGPathRelease(frame);
    /* Empty left margin, solid right pane, transparent gap around the pane. */
    CGPathRef pane = CGPathCreateWithRoundedRect(
        CGRectMake(6, 4, 9, 8), 1, 1, NULL);
    CGContextAddPath(context, pane);
    CGContextFillPath(context);
    CGPathRelease(pane);
    CGPDFContextEndPage(context);
    CGPDFContextClose(context);
    CGContextRelease(context);
    return 0;
}
