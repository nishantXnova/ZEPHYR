const std = @import("std");
const math = std.math;

pub const Vec2 = struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn init(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }
    pub fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }
    pub fn sub(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }
    pub fn scale(v: Vec2, s: f32) Vec2 {
        return .{ .x = v.x * s, .y = v.y * s };
    }
    pub fn length(v: Vec2) f32 {
        return math.sqrt(v.x * v.x + v.y * v.y);
    }
    pub fn zero() Vec2 {
        return .{ .x = 0, .y = 0 };
    }
};

pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    pub fn init(x: f32, y: f32, w: f32, h: f32) Rect {
        return .{ .x = x, .y = y, .w = w, .h = h };
    }
    pub fn left(self: Rect) f32 {
        return self.x;
    }
    pub fn right(self: Rect) f32 {
        return self.x + self.w;
    }
    pub fn top(self: Rect) f32 {
        return self.y;
    }
    pub fn bottom(self: Rect) f32 {
        return self.y + self.h;
    }
    pub fn overlaps(a: Rect, b: Rect) bool {
        return a.left() < b.right() and a.right() > b.left() and
            a.top() < b.bottom() and a.bottom() > b.top();
    }
    pub fn contains(self: Rect, p: Vec2) bool {
        return p.x >= self.left() and p.x <= self.right() and
            p.y >= self.top() and p.y <= self.bottom();
    }
};

pub const clamp = math.clamp;
pub const lerp = struct {
    pub fn f32Lerp(a: f32, b: f32, t: f32) f32 {
        return a + (b - a) * t;
    }
};

pub const Mat4 = @import("camera.zig").Mat4;
pub const Camera2D = @import("camera.zig").Camera2D;

test "Rect overlaps" {
    const a = Rect.init(0, 0, 10, 10);
    const b = Rect.init(5, 5, 10, 10);
    const c = Rect.init(20, 20, 5, 5);
    try std.testing.expect(a.overlaps(b));
    try std.testing.expect(!a.overlaps(c));
}
