pub const ElementId = usize;
pub const CanvasContextId = usize;
pub const EventId = usize;
pub const NetworkRequestId = usize;
pub const ResourceId = usize;

pub const EventType = enum(usize) {
    Resize = 0,
    OnClick,
    TextChange,
    MouseButton,
    MouseMotion,
    MouseScroll,
    UpdateAudio,
};

pub extern fn jsPrint(msg: [*]const u8, len: usize) void;
pub extern fn jsCreateElement(name: [*]const u8, nameLen: usize, elementType: [*]const u8, elementTypeLen: usize) ElementId;
pub extern fn appendElement(parent: ElementId, child: ElementId) void;
pub extern fn setRoot(root: ElementId) void;
pub extern fn setText(element: ElementId, textPtr: [*]const u8, textLen: usize) void;
pub extern fn getTextLen(element: ElementId) usize;
pub extern fn getText(element: ElementId, textPtr: [*]const u8) void;
pub extern fn setPos(element: ElementId, x: usize, y: usize) void;
pub extern fn setSize(element: ElementId, w: usize, h: usize) void;
pub extern fn getWidth(element: ElementId) c_int;
pub extern fn getHeight(element: ElementId) c_int;
pub extern fn now() f64;
pub extern fn hasEvent() bool;
pub extern fn popEvent() EventId;
pub extern fn getEventType(event: EventId) EventType;
pub extern fn getEventTarget(event: EventId) ElementId;
pub extern fn getEventArg(event: EventId, argIdx: usize) usize;
pub extern fn stopExecution() noreturn;
pub extern fn yield() void;

// Canvas related
pub extern fn openContext(element: ElementId) CanvasContextId;
pub extern fn setColor(ctx: CanvasContextId, r: u8, g: u8, b: u8, a: u8) void;
pub extern fn rectPath(ctx: CanvasContextId, x: i32, y: i32, w: u32, h: u32) void;
pub extern fn moveTo(ctx: CanvasContextId, x: i32, y: i32) void;
pub extern fn lineTo(ctx: CanvasContextId, x: i32, y: i32) void;
pub extern fn fillText(ctx: CanvasContextId, textPtr: [*]const u8, textLen: usize, x: i32, y: i32) void;
pub extern fn fillImage(ctx: CanvasContextId, img: ResourceId, x: i32, y: i32) void;
pub extern fn ellipse(ctx: CanvasContextId, x: i32, y: i32, w: u32, h: u32) void;
pub extern fn fill(ctx: CanvasContextId) void;
pub extern fn stroke(ctx: CanvasContextId) void;

// Resources
pub extern fn uploadImage(width: usize, height: usize, stride: usize, is_rgb: bool, bytesPtr: [*]const u8) ResourceId;

// Networking related
// TODO: support more things
pub extern fn fetchHttp(urlPtr: [*]const u8, urlLen: usize) NetworkRequestId;
pub extern fn isRequestReady(id: NetworkRequestId) usize;
pub extern fn readRequest(id: NetworkRequestId, bufPtr: [*]u8, bufLen: usize) usize;

pub fn print(msg: []const u8) void {
    jsPrint(msg.ptr, msg.len);
}

pub fn createElement(name: []const u8, elementType: []const u8) ElementId {
    return jsCreateElement(name.ptr, name.len, elementType.ptr, elementType.len);
}

pub fn write(_: void, msg: []const u8) error{}!usize {
    jsPrint(msg.ptr, msg.len);
    return msg.len;
}
