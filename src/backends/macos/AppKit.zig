// TODO: auto-generator from objective-c files?
pub const NSUInteger = u64;

pub const NSWindowStyleMask = struct {
    pub const Borderless: NSUInteger = 0;
    pub const Titled: NSUInteger = 1 << 0;
    pub const Closable: NSUInteger = 1 << 1;
    pub const Miniaturizable: NSUInteger = 1 << 2;
    pub const Resizable: NSUInteger = 1 << 3;
    pub const Utility: NSUInteger = 1 << 4;
    pub const FullScreen: NSUInteger = 1 << 14;
};

pub const NSBackingStore = enum(NSUInteger) {
    /// Deprecated.
    Retained,
    /// Deprecated.
    Nonretained,
    /// The window renders all drawing into a display buffer and then flushes it to the screen.
    Buffered,
};
