const std = @import("std");
const backend = @import("../backend.zig");
const internal = @import("../internal.zig");
const Size = @import("../data.zig").Size;
const ListAtom = @import("../data.zig").ListAtom;
const Atom = @import("../data.zig").Atom;

/// A dropdown to select a value.
pub const Dropdown = struct {
    pub usingnamespace @import("../internal.zig").All(Dropdown);

    peer: ?backend.Dropdown = null,
    widget_data: Dropdown.WidgetData = .{},
    /// The list of values that the user can select in the dropdown.
    /// The strings are owned by the caller.
    values: ListAtom([]const u8),
    /// Whether the user can interact with the button, that is
    /// whether the button can be pressed or not.
    enabled: Atom(bool) = Atom(bool).of(true),
    selected_index: Atom(usize) = Atom(usize).of(0),
    // TODO: exclude of Dropdown.Config
    /// This is a read-only property.
    selected_value: Atom([]const u8) = Atom([]const u8).of(""),

    pub fn init(config: Dropdown.Config) Dropdown {
        var component = Dropdown.init_events(Dropdown{
            .values = ListAtom([]const u8).init(internal.lasting_allocator),
        });
        internal.applyConfigStruct(&component, config);
        // TODO: self.selected_value.dependOn(&.{ self.values, self.selected_index })
        return component;
    }

    fn onEnabledAtomChange(newValue: bool, userdata: ?*anyopaque) void {
        const self: *Dropdown = @ptrCast(@alignCast(userdata));
        self.peer.?.setEnabled(newValue);
    }

    fn onSelectedIndexAtomChange(newValue: usize, userdata: ?*anyopaque) void {
        const self: *Dropdown = @ptrCast(@alignCast(userdata));
        self.peer.?.setSelectedIndex(newValue);
        self.selected_value.set(self.values.get(newValue));
    }

    fn onValuesChange(list: *ListAtom([]const u8), userdata: ?*anyopaque) void {
        const self: *Dropdown = @ptrCast(@alignCast(userdata));
        self.selected_value.set(list.get(self.selected_index.get()));
        var iterator = list.iterate();
        defer iterator.deinit();
        self.peer.?.setValues(iterator.getSlice());
    }

    fn onPropertyChange(self: *Dropdown, property_name: []const u8, new_value: *const anyopaque) !void {
        if (std.mem.eql(u8, property_name, "selected")) {
            const value: *const usize = @ptrCast(@alignCast(new_value));
            self.selected_index.set(value.*);
        }
    }

    pub fn show(self: *Dropdown) !void {
        if (self.peer == null) {
            var peer = try backend.Dropdown.create();
            peer.setEnabled(self.enabled.get());
            {
                var iterator = self.values.iterate();
                defer iterator.deinit();
                peer.setValues(iterator.getSlice());
            }
            self.selected_value.set(self.values.get(self.selected_index.get()));
            peer.setSelectedIndex(self.selected_index.get());
            self.peer = peer;
            try self.setupEvents();
            _ = try self.enabled.addChangeListener(.{ .function = onEnabledAtomChange, .userdata = self });
            _ = try self.selected_index.addChangeListener(.{ .function = onSelectedIndexAtomChange, .userdata = self });
            _ = try self.values.addChangeListener(.{ .function = onValuesChange, .userdata = self });
            try self.addPropertyChangeHandler(&onPropertyChange);
        }
    }

    pub fn getPreferredSize(self: *Dropdown, available: Size) Size {
        _ = available;
        if (self.peer) |peer| {
            return peer.getPreferredSize();
        } else {
            return Size{ .width = 100.0, .height = 40.0 };
        }
    }
};

pub fn dropdown(config: Dropdown.Config) *Dropdown {
    return Dropdown.alloc(config);
}
