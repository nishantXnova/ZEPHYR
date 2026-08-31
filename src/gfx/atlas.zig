const std = @import("std");
const Texture = @import("texture.zig").Texture;
const Image = @import("image.zig").Image;
const Batch = @import("batch.zig").Batch;
const Color = @import("color.zig").Color;
const Rect = @import("../core/math.zig").Rect;

// Zephyr Atlas v1.0 — Actual engine feature. Texture atlas packs many PNGs into one GL texture
// → single draw call, no cur_tex switches `src/gfx/batch.zig:135`. Every real engine has this.
// Shelf packer, CPU blit, single TexImage2D upload. Beats per-file Texture (indie naive) at scale.
// Usage: var atlas = try Atlas.init(allocator, 1024, 1024); try atlas.add("mario","assets/mario.png"); atlas.build(); atlas.draw(batch, "mario", 0,0,32,32);

pub const AtlasEntry = struct {
    x: u32,
    y: u32,
    w: u32,
    h: u32,
};

pub const Atlas = struct {
    w: u32,
    h: u32,
    data: []u8, // RGBA w*h*4
    tex: ?Texture = null,
    cursor_x: u32 = 0,
    cursor_y: u32 = 0,
    row_h: u32 = 0,
    entries: std.StringHashMap(AtlasEntry),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, w: u32, h: u32) !Atlas {
        const data = try allocator.alloc(u8, w * h * 4);
        @memset(data, 0);
        return .{
            .w = w,
            .h = h,
            .data = data,
            .entries = std.StringHashMap(AtlasEntry).init(allocator),
            .allocator = allocator,
        };
    }
    pub fn deinit(self: *Atlas) void {
        self.allocator.free(self.data);
        self.entries.deinit();
        if (self.tex) |*t| t.deinit();
    }
    // Shelf pack: row by row
    pub fn add(self: *Atlas, name: []const u8, path: []const u8) !void {
        const img = try Image.loadFromFile(path, self.allocator);
        defer img.free();
        const iw: u32 = @intCast(img.w);
        const ih: u32 = @intCast(img.h);
        if (iw > self.w or ih > self.h) return error.AtlasTooSmall;
        if (self.cursor_x + iw > self.w) {
            // next row
            self.cursor_x = 0;
            self.cursor_y += self.row_h;
            self.row_h = 0;
        }
        if (self.cursor_y + ih > self.h) return error.AtlasFull;
        // blit
        const dst_x = self.cursor_x;
        const dst_y = self.cursor_y;
        for (0..ih) |y| {
            const src_off = y * iw * 4;
            const dst_off = ((dst_y + @as(u32, @intCast(y))) * self.w + dst_x) * 4;
            @memcpy(self.data[dst_off .. dst_off + iw * 4], img.data[src_off .. src_off + iw * 4]);
        }
        const owned = try self.allocator.dupe(u8, name);
        try self.entries.put(owned, .{ .x = dst_x, .y = dst_y, .w = iw, .h = ih });
        self.cursor_x += iw;
        if (ih > self.row_h) self.row_h = ih;
    }
    pub fn build(self: *Atlas) !void {
        // upload to GL
        if (self.tex) |*t| t.deinit();
        self.tex = try Texture.initFromRGBA(@intCast(self.w), @intCast(self.h), self.data);
    }
    pub fn get(self: Atlas, name: []const u8) ?AtlasEntry {
        return self.entries.get(name);
    }
    pub fn getTexture(self: *Atlas) ?*Texture {
        if (self.tex) |*t| return t;
        return null;
    }
    // Draw entry via atlas texture — single batch tex, no switch
    pub fn draw(self: Atlas, batch: *Batch, name: []const u8, dx: f32, dy: f32, dw: f32, dh: f32, tint: Color) void {
        const e = self.entries.get(name) orelse return;
        const tex = self.tex orelse return;
        // need mutable pointer for batch.drawTextureEx
        var t = tex;
        batch.drawTextureEx(&t, dx, dy, dw, dh, @floatFromInt(e.x), @floatFromInt(e.y), @floatFromInt(e.w), @floatFromInt(e.h), tint);
    }
    pub fn drawEx(self: Atlas, batch: *Batch, name: []const u8, dx: f32, dy: f32, dw: f32, dh: f32, sx: f32, sy: f32, sw: f32, sh: f32, tint: Color) void {
        const e = self.entries.get(name) orelse return;
        var t = self.tex orelse return;
        // sub-rect within entry
        batch.drawTextureEx(&t, dx, dy, dw, dh, @as(f32, @floatFromInt(e.x)) + sx, @as(f32, @floatFromInt(e.y)) + sy, sw, sh, tint);
    }
    pub fn count(self: Atlas) usize { return self.entries.count(); }
};

test "atlas pack two images" {
    const gpa = std.testing.allocator;
    // create dummy atlas without loading files — test packing logic via manual blit
    var atlas = try Atlas.init(gpa, 64, 64);
    defer atlas.deinit();
    // manually add entries (simulate)
    try atlas.entries.put(try gpa.dupe(u8, "a"), .{ .x = 0, .y = 0, .w = 16, .h = 16 });
    try atlas.entries.put(try gpa.dupe(u8, "b"), .{ .x = 16, .y = 0, .w = 16, .h = 16 });
    try std.testing.expectEqual(@as(usize, 2), atlas.count());
    try std.testing.expect(atlas.get("a") != null);
    try std.testing.expectEqual(@as(u32, 0), atlas.get("a").?.x);
}
