const std = @import("std");

// Mat4 column-major for OpenGL
pub const Mat4 = struct {
    m: [16]f32 = .{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    },

    pub fn identity() Mat4 {
        return .{};
    }
    pub fn ortho(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) Mat4 {
        var r: Mat4 = .{};
        r.m[0] = 2.0 / (right - left);
        r.m[5] = 2.0 / (top - bottom);
        r.m[10] = -2.0 / (far - near);
        r.m[12] = -(right + left) / (right - left);
        r.m[13] = -(top + bottom) / (top - bottom);
        r.m[14] = -(far + near) / (far - near);
        return r;
    }
    pub fn translate(x: f32, y: f32, z: f32) Mat4 {
        var r = Mat4.identity();
        r.m[12] = x;
        r.m[13] = y;
        r.m[14] = z;
        return r;
    }
    pub fn scale(x: f32, y: f32, z: f32) Mat4 {
        var r = Mat4.identity();
        r.m[0] = x;
        r.m[5] = y;
        r.m[10] = z;
        return r;
    }
    pub fn mul(a: Mat4, b: Mat4) Mat4 {
        var r: Mat4 = .{ .m = undefined };
        for (0..4) |i| {
            for (0..4) |j| {
                var sum: f32 = 0;
                for (0..4) |k| sum += a.m[k * 4 + j] * b.m[i * 4 + k];
                // actually column-major: r[col*4+row] = sum
                r.m[i * 4 + j] = sum;
            }
        }
        return r;
    }
};

pub const Camera2D = struct {
    pos: struct { x: f32 = 0, y: f32 = 0 } = .{},
    zoom: f32 = 1.0,
    viewport_w: f32,
    viewport_h: f32,

    pub fn init(w: f32, h: f32) Camera2D {
        return .{ .viewport_w = w, .viewport_h = h };
    }
    pub fn projection(self: Camera2D) Mat4 {
        // ortho with (0,0) top-left like our GDI coords
        return Mat4.ortho(0, self.viewport_w, self.viewport_h, 0, -1, 1);
    }
    pub fn view(self: Camera2D) Mat4 {
        return Mat4.translate(-self.pos.x, -self.pos.y, 0).mul(Mat4.scale(self.zoom, self.zoom, 1));
    }
    pub fn combined(self: Camera2D) Mat4 {
        return self.projection().mul(self.view());
    }
};
