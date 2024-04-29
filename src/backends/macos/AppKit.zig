// TODO: auto-generator from objective-c files?
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
