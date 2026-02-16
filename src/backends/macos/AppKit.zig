// TODO: auto-generator from objective-c files?
const objc = @import("objc");
pub const NSUInteger = u64;

pub const NSApplicationActivationPolicy = enum(NSUInteger) {
    Regular,
    Accessory,
};

pub const NSWindowStyleMask = struct {
    pub const Borderless: NSUInteger = 0;
    pub const Titled: NSUInteger = 1 << 0;
    pub const Closable: NSUInteger = 1 << 1;
    pub const Miniaturizable: NSUInteger = 1 << 2;
    pub const Resizable: NSUInteger = 1 << 3;
    pub const Utility: NSUInteger = 1 << 4;
    pub const FullScreen: NSUInteger = 1 << 14;
    pub const FullSizeContentView: NSUInteger = 1 << 15;
};

pub const NSBackingStore = enum(NSUInteger) {
    /// Deprecated.
    Retained,
    /// Deprecated.
    Nonretained,
    /// The window renders all drawing into a display buffer and then flushes it to the screen.
    Buffered,
};

pub extern var NSDefaultRunLoopMode: objc.c.id;

pub const NSEventMaskAny: NSUInteger = @import("std").math.maxInt(NSUInteger);

pub const CGFloat = f64;

pub const CGPoint = extern struct {
    x: CGFloat,
    y: CGFloat,
};

pub const CGSize = extern struct {
    width: CGFloat,
    height: CGFloat,
};

pub const CGRect = extern struct {
    origin: CGPoint,
    size: CGSize,

    pub fn make(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) CGRect {
        return .{
            .origin = .{ .x = x, .y = y },
            .size = .{ .width = width, .height = height },
        };
    }
};

pub const NSRect = CGRect;

pub const nil: objc.c.id = null;

pub const NSStringEncoding = enum(NSUInteger) {
    ASCII = 1,
    NEXTSTEP,
    JapaneseEUC,
    UTF8,
    ISOLatin1,
    Symbol,
    NonLossyASCII,
    ShiftJIS,
    ISOLatin2,
    Unicode,
    WindowsCP1251,
    WindowsCP1252,
    WindowsCP1253,
    WindowsCP1254,
    WindowsCP1250,
    ISO2022JP,
    MacOSRoman,
    UTF16,
    UTF16BigEndian,
    UTF16LittleEndian,
    UTF32,
    UTF32BigEndian,
    UTF32LittleEndian,
    Proprietary,
};

pub fn nsString(str: [*:0]const u8) objc.Object {
    const NSString = objc.getClass("NSString").?;
    const object = NSString.msgSend(objc.Object, "alloc", .{})
        .msgSend(objc.Object, "initWithUTF8String:", .{str});
    return object;
}

// --- NSEvent types ---

pub const NSEventType = struct {
    pub const LeftMouseDown: NSUInteger = 1;
    pub const LeftMouseUp: NSUInteger = 2;
    pub const RightMouseDown: NSUInteger = 3;
    pub const RightMouseUp: NSUInteger = 4;
    pub const MouseMoved: NSUInteger = 5;
    pub const LeftMouseDragged: NSUInteger = 6;
    pub const RightMouseDragged: NSUInteger = 7;
    pub const KeyDown: NSUInteger = 10;
    pub const KeyUp: NSUInteger = 11;
    pub const FlagsChanged: NSUInteger = 12;
    pub const ApplicationDefined: NSUInteger = 15;
    pub const ScrollWheel: NSUInteger = 22;
    pub const OtherMouseDown: NSUInteger = 25;
    pub const OtherMouseUp: NSUInteger = 26;
};

pub const NSTrackingAreaOptions = struct {
    pub const MouseEnteredAndExited: NSUInteger = 0x01;
    pub const MouseMoved: NSUInteger = 0x02;
    pub const ActiveAlways: NSUInteger = 0x80;
    pub const ActiveInActiveApp: NSUInteger = 0x40;
    pub const InVisibleRect: NSUInteger = 0x200;
    pub const AssumeInside: NSUInteger = 0x100;
};

pub const NSAlertStyle = struct {
    pub const Warning: NSUInteger = 0;
    pub const Informational: NSUInteger = 1;
    pub const Critical: NSUInteger = 2;
};

pub const NSButtonType = struct {
    pub const MomentaryLight: NSUInteger = 0;
    pub const PushOnPushOff: NSUInteger = 1;
    pub const Toggle: NSUInteger = 2;
    pub const Switch: NSUInteger = 3; // checkbox
    pub const Radio: NSUInteger = 4;
    pub const MomentaryChange: NSUInteger = 5;
    pub const OnOff: NSUInteger = 6;
    pub const MomentaryPushIn: NSUInteger = 7;
};

pub const NSControlStateValue = struct {
    pub const Off: i64 = 0;
    pub const On: i64 = 1;
    pub const Mixed: i64 = -1;
};

pub const NSBezelStyle = struct {
    pub const Rounded: NSUInteger = 1;
    pub const RegularSquare: NSUInteger = 2;
    pub const SmallSquare: NSUInteger = 6;
    pub const Inline: NSUInteger = 15;
};

// --- CoreGraphics types and externs ---

pub const CGContextRef = ?*anyopaque;
pub const CGColorSpaceRef = ?*anyopaque;
pub const CGGradientRef = ?*anyopaque;
pub const CGImageRef = ?*anyopaque;

pub const CGGradientDrawingOptions = struct {
    pub const DrawsBeforeStartLocation: u32 = 1 << 0;
    pub const DrawsAfterEndLocation: u32 = 1 << 1;
};

pub const CGBitmapInfo = struct {
    pub const AlphaInfoMask: u32 = 0x1F;
    pub const ByteOrderMask: u32 = 0x7000;
    pub const ByteOrder32Big: u32 = 4 << 12;
    pub const ByteOrder32Little: u32 = 2 << 12;
    pub const PremultipliedLast: u32 = 1;
    pub const PremultipliedFirst: u32 = 2;
    pub const Last: u32 = 3;
    pub const First: u32 = 4;
    pub const NoneSkipLast: u32 = 5;
    pub const NoneSkipFirst: u32 = 6;
};

pub extern "c" fn CGContextSetRGBFillColor(ctx: CGContextRef, r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) void;
pub extern "c" fn CGContextSetRGBStrokeColor(ctx: CGContextRef, r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) void;
pub extern "c" fn CGContextAddRect(ctx: CGContextRef, rect: CGRect) void;
pub extern "c" fn CGContextFillRect(ctx: CGContextRef, rect: CGRect) void;
pub extern "c" fn CGContextStrokeRect(ctx: CGContextRef, rect: CGRect) void;
pub extern "c" fn CGContextClearRect(ctx: CGContextRef, rect: CGRect) void;
pub extern "c" fn CGContextAddEllipseInRect(ctx: CGContextRef, rect: CGRect) void;
pub extern "c" fn CGContextMoveToPoint(ctx: CGContextRef, x: CGFloat, y: CGFloat) void;
pub extern "c" fn CGContextAddLineToPoint(ctx: CGContextRef, x: CGFloat, y: CGFloat) void;
pub extern "c" fn CGContextAddArc(ctx: CGContextRef, x: CGFloat, y: CGFloat, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: c_int) void;
pub extern "c" fn CGContextAddArcToPoint(ctx: CGContextRef, x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, radius: CGFloat) void;
pub extern "c" fn CGContextStrokePath(ctx: CGContextRef) void;
pub extern "c" fn CGContextFillPath(ctx: CGContextRef) void;
pub extern "c" fn CGContextSetLineWidth(ctx: CGContextRef, width: CGFloat) void;
pub extern "c" fn CGContextSaveGState(ctx: CGContextRef) void;
pub extern "c" fn CGContextRestoreGState(ctx: CGContextRef) void;
pub extern "c" fn CGContextClip(ctx: CGContextRef) void;
pub extern "c" fn CGContextDrawImage(ctx: CGContextRef, rect: CGRect, image: CGImageRef) void;
pub extern "c" fn CGContextBeginPath(ctx: CGContextRef) void;
pub extern "c" fn CGContextClosePath(ctx: CGContextRef) void;
pub extern "c" fn CGContextDrawLinearGradient(ctx: CGContextRef, gradient: CGGradientRef, startPoint: CGPoint, endPoint: CGPoint, options: u32) void;
pub extern "c" fn CGContextSetTextPosition(ctx: CGContextRef, x: CGFloat, y: CGFloat) void;
pub extern "c" fn CGContextScaleCTM(ctx: CGContextRef, sx: CGFloat, sy: CGFloat) void;
pub extern "c" fn CGContextTranslateCTM(ctx: CGContextRef, tx: CGFloat, ty: CGFloat) void;

pub extern "c" fn CGGradientCreateWithColorComponents(space: CGColorSpaceRef, components: [*]const CGFloat, locations: ?[*]const CGFloat, count: usize) CGGradientRef;
pub extern "c" fn CGGradientRelease(gradient: CGGradientRef) void;
pub extern "c" fn CGColorSpaceCreateDeviceRGB() CGColorSpaceRef;
pub extern "c" fn CGColorSpaceRelease(space: CGColorSpaceRef) void;

pub extern "c" fn CGBitmapContextCreate(data: ?*anyopaque, width: usize, height: usize, bitsPerComponent: usize, bytesPerRow: usize, space: CGColorSpaceRef, bitmapInfo: u32) CGContextRef;
pub extern "c" fn CGBitmapContextCreateImage(ctx: CGContextRef) CGImageRef;
pub extern "c" fn CGContextRelease(ctx: CGContextRef) void;
pub extern "c" fn CGImageRelease(image: CGImageRef) void;

// --- CoreText types and externs ---

pub const CTFontRef = ?*anyopaque;
pub const CTLineRef = ?*anyopaque;

pub extern "c" fn CTFontCreateWithName(name: CFStringRef, size: CGFloat, matrix: ?*const anyopaque) CTFontRef;
pub extern "c" fn CTLineCreateWithAttributedString(attrString: CFAttributedStringRef) CTLineRef;
pub extern "c" fn CTLineGetTypographicBounds(line: CTLineRef, ascent: ?*CGFloat, descent: ?*CGFloat, leading: ?*CGFloat) CGFloat;
pub extern "c" fn CTLineDraw(line: CTLineRef, ctx: CGContextRef) void;

// --- CoreFoundation types and externs ---

pub const CFStringRef = ?*anyopaque;
pub const CFAttributedStringRef = ?*anyopaque;
pub const CFDictionaryRef = ?*anyopaque;
pub const CFAllocatorRef = ?*anyopaque;
pub const CFTypeRef = ?*anyopaque;

pub const CFStringEncoding_UTF8: u32 = 0x08000100;

pub extern "c" var kCFAllocatorDefault: CFAllocatorRef;
pub extern "c" var kCFTypeDictionaryKeyCallBacks: anyopaque;
pub extern "c" var kCFTypeDictionaryValueCallBacks: anyopaque;
pub extern "c" var kCTFontAttributeName: CFStringRef;
pub extern "c" var kCTForegroundColorAttributeName: CFStringRef;

pub extern "c" fn CFStringCreateWithBytes(alloc: CFAllocatorRef, bytes: [*]const u8, numBytes: i64, encoding: u32, isExternalRep: u8) CFStringRef;
pub extern "c" fn CFAttributedStringCreate(alloc: CFAllocatorRef, str: CFStringRef, attributes: CFDictionaryRef) CFAttributedStringRef;
pub extern "c" fn CFDictionaryCreate(alloc: CFAllocatorRef, keys: [*]const ?*const anyopaque, values: [*]const ?*const anyopaque, numValues: i64, keyCallBacks: *const anyopaque, valueCallBacks: *const anyopaque) CFDictionaryRef;
pub extern "c" fn CFRelease(obj: ?*anyopaque) void;
