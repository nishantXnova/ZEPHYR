const std = @import("std");
const gl = @import("gl.zig");
const Image = @import("image.zig").Image;

pub const Texture = struct {
    id: gl.GLuint,
    w: i32,
    h: i32,

    pub fn initWhite() !Texture {
        var id: gl.GLuint = 0;
        gl.GenTextures(1, @ptrCast(&id));
        gl.BindTexture(gl.TEXTURE_2D, id);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        const white: [4]u8 = .{ 255, 255, 255, 255 };
        gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, &white);
        gl.BindTexture(gl.TEXTURE_2D, 0);
        return .{ .id = id, .w = 1, .h = 1 };
    }

    pub fn initSolid(r: u8, g: u8, b: u8, a: u8) !Texture {
        var id: gl.GLuint = 0;
        gl.GenTextures(1, @ptrCast(&id));
        gl.BindTexture(gl.TEXTURE_2D, id);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        const pix: [4]u8 = .{ r, g, b, a };
        gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, &pix);
        gl.BindTexture(gl.TEXTURE_2D, 0);
        return .{ .id = id, .w = 1, .h = 1 };
    }

    pub fn initFromRGBA(w: i32, h: i32, pixels: []const u8) !Texture {
        var id: gl.GLuint = 0;
        gl.GenTextures(1, @ptrCast(&id));
        gl.BindTexture(gl.TEXTURE_2D, id);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixels.ptr);
        gl.BindTexture(gl.TEXTURE_2D, 0);
        return .{ .id = id, .w = w, .h = h };
    }

    pub fn bind(self: Texture, slot: u32) void {
        gl.ActiveTexture(gl.TEXTURE0 + slot);
        gl.BindTexture(gl.TEXTURE_2D, self.id);
    }

    pub fn deinit(self: *Texture) void {
        gl.DeleteTextures(1, @ptrCast(&self.id));
        self.id = 0;
    }

    pub fn initFromFile(path: []const u8, allocator: std.mem.Allocator) !Texture {
        const img = try Image.loadFromFile(path, allocator);
        defer img.free();
        return try initFromRGBA(img.w, img.h, img.data[0..@as(usize, @intCast(img.w * img.h * 4))]);
    }
};
