const std = @import("std");

const c = @cImport({
    @cInclude("stb_image.h");
});

pub const Image = struct {
    w: i32,
    h: i32,
    channels: i32,
    data: [*]u8,

    pub fn loadFromFile(path: []const u8, allocator: std.mem.Allocator) !Image {
        // c string
        const cpath = try allocator.dupeZ(u8, path);
        defer allocator.free(cpath);
        var w: c_int = 0;
        var h: c_int = 0;
        var ch: c_int = 0;
        const data = c.stbi_load(cpath.ptr, &w, &h, &ch, 4);
        if (data == null) {
            const reason = if (c.stbi_failure_reason()) |r| std.mem.span(r) else "unknown";
            std.log.err("stb_image load failed '{s}': {s}", .{ path, reason });
            return error.ImageLoadFailed;
        }
        return .{ .w = w, .h = h, .channels = 4, .data = data };
    }
    pub fn free(self: Image) void {
        c.stbi_image_free(self.data);
    }
};

pub const stb = c;
