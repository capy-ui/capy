const Allocator = @import("std").mem.Allocator;
const ArenaAllocator = @import("std").heap.ArenaAllocator;
const ArrayList = @import("std").ArrayList;
const Rgba32 = @import("color.zig").Rgba32;

const MaxDepth = 8;

pub const OctTreeQuantizer = struct {
    rootNode: OctTreeQuantizerNode,
    levels: [MaxDepth]NodeArrayList,
    arenaAllocator: ArenaAllocator,

    const NodeArrayList = ArrayList(*OctTreeQuantizerNode);
    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        var result = Self{
            .rootNode = OctTreeQuantizerNode{},
            .arenaAllocator = ArenaAllocator.init(allocator),
            .levels = undefined,
        };
        var i: usize = 0;
        while (i < result.levels.len) : (i += 1) {
            result.levels[i] = NodeArrayList.init(allocator);
        }
        result.rootNode.init(0, &result) catch unreachable;
        return result;
    }

    pub fn deinit(self: *Self) void {
        self.arenaAllocator.deinit();
        var i: usize = 0;
        while (i < self.levels.len) : (i += 1) {
            self.levels[i].deinit();
        }
    }

    pub fn allocateNode(self: *Self) !*OctTreeQuantizerNode {
        return try self.arenaAllocator.allocator().create(OctTreeQuantizerNode);
    }

    pub fn addLevelNode(self: *Self, level: i32, node: *OctTreeQuantizerNode) !void {
        try self.levels[@intCast(usize, level)].append(node);
    }

    pub fn addColor(self: *Self, color: Rgba32) !void {
        try self.rootNode.addColor(color, 0, self);
    }

    pub fn getPaletteIndex(self: Self, color: Rgba32) !usize {
        return try self.rootNode.getPaletteIndex(color, 0);
    }

    pub fn makePalette(self: *Self, colorCount: usize, palette: []Rgba32) anyerror![]Rgba32 {
        var paletteIndex: usize = 0;

        var rootLeafNodes = try self.rootNode.getLeafNodes(self.arenaAllocator.child_allocator);
        defer rootLeafNodes.deinit();
        var leafCount = rootLeafNodes.items.len;

        var level: usize = MaxDepth - 1;
        while (level >= 0) : (level -= 1) {
            for (self.levels[level].items) |node| {
                leafCount -= @intCast(usize, node.removeLeaves());
                if (leafCount <= colorCount) {
                    break;
                }
            }
            if (leafCount <= colorCount) {
                break;
            }
            try self.levels[level].resize(0);
        }

        var processedRoofLeafNodes = try self.rootNode.getLeafNodes(self.arenaAllocator.child_allocator);
        defer processedRoofLeafNodes.deinit();

        for (processedRoofLeafNodes.items) |node| {
            if (paletteIndex >= colorCount) {
                break;
            }
            if (node.isLeaf()) {
                palette[paletteIndex] = node.getColor();
                node.paletteIndex = paletteIndex;
                paletteIndex += 1;
            }
        }

        return palette[0..paletteIndex];
    }
};

const OctTreeQuantizerNode = struct {
    red: u32 = 0,
    green: u32 = 0,
    blue: u32 = 0,
    referenceCount: usize = 0,
    paletteIndex: usize = 0,
    children: [8]?*Self = undefined,

    const Self = @This();
    const NodeArrayList = ArrayList(*Self);

    pub fn init(self: *Self, level: i32, parent: *OctTreeQuantizer) !void {
        self.red = 0;
        self.green = 0;
        self.blue = 0;
        self.referenceCount = 0;
        self.paletteIndex = 0;

        var i: usize = 0;
        while (i < self.children.len) : (i += 1) {
            self.children[i] = null;
        }

        if (level < (MaxDepth - 1)) {
            try parent.addLevelNode(level, self);
        }
    }

    pub fn isLeaf(self: Self) bool {
        return self.referenceCount > 0;
    }

    pub fn getColor(self: Self) Rgba32 {
        return Rgba32.initRgb(@intCast(u8, self.red / self.referenceCount), @intCast(u8, self.green / self.referenceCount), @intCast(u8, self.blue / self.referenceCount));
    }

    pub fn addColor(self: *Self, color: Rgba32, level: i32, parent: *OctTreeQuantizer) anyerror!void {
        if (level >= MaxDepth) {
            self.red += color.r;
            self.green += color.g;
            self.blue += color.b;
            self.referenceCount += 1;
            return;
        }
        const index = getColorIndex(color, level);
        if (index >= self.children.len) {
            return error.InvalidColorIndex;
        }
        if (self.children[index]) |child| {
            try child.addColor(color, level + 1, parent);
        } else {
            var newNode = try parent.allocateNode();
            try newNode.init(level, parent);
            try newNode.addColor(color, level + 1, parent);
            self.children[index] = newNode;
        }
    }

    pub fn getPaletteIndex(self: Self, color: Rgba32, level: i32) anyerror!usize {
        if (self.isLeaf()) {
            return self.paletteIndex;
        }
        const index = getColorIndex(color, level);
        if (self.children[index]) |child| {
            return try child.getPaletteIndex(color, level + 1);
        } else {
            for (self.children) |childOptional| {
                if (childOptional) |child| {
                    return try child.getPaletteIndex(color, level + 1);
                }
            }
        }

        return error.ColorNotFound;
    }

    pub fn getLeafNodes(self: Self, allocator: Allocator) anyerror!NodeArrayList {
        var leafNodes = NodeArrayList.init(allocator);

        for (self.children) |childOptional| {
            if (childOptional) |child| {
                if (child.isLeaf()) {
                    try leafNodes.append(child);
                } else {
                    var childNodes = try child.getLeafNodes(allocator);
                    defer childNodes.deinit();
                    for (childNodes.items) |childNode| {
                        try leafNodes.append(childNode);
                    }
                }
            }
        }

        return leafNodes;
    }

    pub fn removeLeaves(self: *Self) i32 {
        var result: i32 = 0;
        for (self.children) |childOptional, i| {
            if (childOptional) |child| {
                self.red += child.red;
                self.green += child.green;
                self.blue += child.blue;
                self.referenceCount += child.referenceCount;
                result += 1;
                self.children[i] = null;
            }
        }
        return result - 1;
    }

    inline fn getColorIndex(color: Rgba32, level: i32) usize {
        var index: usize = 0;
        var mask = @as(u8, 0b10000000) >> @intCast(u3, level);
        if (color.r & mask != 0) {
            index |= 0b100;
        }
        if (color.g & mask != 0) {
            index |= 0b010;
        }
        if (color.b & mask != 0) {
            index |= 0b001;
        }
        return index;
    }
};
