pub const ElementId = usize;

pub extern fn jsPrint(msg: [*]const u8, len: usize) void;
pub extern fn jsCreateElement(name: [*]const u8, nameLen: usize) ElementId;
pub extern fn appendElement(parent: ElementId, child: ElementId) void;
pub extern fn setRoot(root: ElementId) void;
pub extern fn setText(element: ElementId, textPtr: [*]const u8, textLen: usize) void;
pub extern fn setPos(element: ElementId, x: usize, y: usize) void;
pub extern fn setSize(element: ElementId, w: usize, h: usize) void;
pub extern fn getWidth(element: ElementId) c_int;
pub extern fn getHeight(element: ElementId) c_int;
pub extern fn now() f64;

pub fn print(msg: []const u8) void {
    jsPrint(msg.ptr, msg.len);
}

pub fn createElement(name: []const u8) ElementId {
    return jsCreateElement(name.ptr, name.len);
}

pub fn write(_: void, msg: []const u8) error{}!usize {
    jsPrint(msg.ptr, msg.len);
    return msg.len;
}
