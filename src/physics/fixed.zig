const std = @import("std");

// Zephyr Fixed v2.1 — i32.16 Q16.16 deterministic physics.
// Cross-CPU determinism: no f32 FPU mode, no SIMD reordering, no -ffast-math drift.
// One f32 accumulation order change breaks rollback hash; i32.16 is bit-identical Intel↔AMD.
// Scale 65536, range ±32767.999, enough for 2D platformer (WW 800, WH 480, TILE 16).

pub const SCALE: i32 = 1 << 16;

pub const Q16 = struct {
    raw: i32 = 0,
    pub fn fromInt(i: i32) Q16 { return .{ .raw = i * SCALE }; }
    pub fn fromFloat(f: f32) Q16 { return .{ .raw = @intFromFloat(@round(f * @as(f32, SCALE))) }; }
    pub fn toFloat(self: Q16) f32 { return @as(f32, @floatFromInt(self.raw)) / @as(f32, SCALE); }
    pub fn add(a: Q16, b: Q16) Q16 { return .{ .raw = a.raw + b.raw }; }
    pub fn sub(a: Q16, b: Q16) Q16 { return .{ .raw = a.raw - b.raw }; }
    pub fn mul(a: Q16, b: Q16) Q16 {
        const prod: i64 = @as(i64, a.raw) * @as(i64, b.raw);
        return .{ .raw = @intCast(prod >> 16) };
    }
    pub fn mulInt(a: Q16, b: i32) Q16 { return .{ .raw = a.raw * b }; }
    pub fn div(a: Q16, b: Q16) Q16 {
        const n: i64 = (@as(i64, a.raw) << 16);
        return .{ .raw = @intCast(@divFloor(n, @as(i64, b.raw))) };
    }
    pub fn abs(a: Q16) Q16 { return .{ .raw = if (a.raw < 0) -a.raw else a.raw }; }
    pub fn clamp(v: Q16, lo: Q16, hi: Q16) Q16 {
        if (v.raw < lo.raw) return lo;
        if (v.raw > hi.raw) return hi;
        return v;
    }
};

pub const VecQ = struct {
    x: Q16 = .{},
    y: Q16 = .{},
    pub fn init(x: f32, y: f32) VecQ { return .{ .x = Q16.fromFloat(x), .y = Q16.fromFloat(y) }; }
    pub fn toFloat(self: VecQ) struct { x: f32, y: f32 } { return .{ .x = self.x.toFloat(), .y = self.y.toFloat() }; }
};

pub const RectQ = struct {
    x: Q16 = .{},
    y: Q16 = .{},
    w: Q16 = .{},
    h: Q16 = .{},
    pub fn init(x: f32, y: f32, w: f32, h: f32) RectQ { return .{ .x = Q16.fromFloat(x), .y = Q16.fromFloat(y), .w = Q16.fromFloat(w), .h = Q16.fromFloat(h) }; }
    pub fn overlaps(a: RectQ, b: RectQ) bool {
        return a.x.raw < b.x.raw + b.w.raw and a.x.raw + a.w.raw > b.x.raw and
            a.y.raw < b.y.raw + b.h.raw and a.y.raw + a.h.raw > b.y.raw;
    }
};

test "Q16 fromFloat roundtrip" {
    const a = Q16.fromFloat(1.5);
    try std.testing.expectEqual(@as(f32, 1.5), a.toFloat());
    const b = Q16.fromFloat(-2.25);
    try std.testing.expectEqual(@as(f32, -2.25), b.toFloat());
    const c = Q16.add(a, b);
    try std.testing.expectEqual(@as(f32, -0.75), c.toFloat());
    const d = Q16.mul(Q16.fromFloat(2), Q16.fromFloat(3));
    try std.testing.expectEqual(@as(f32, 6), d.toFloat());
}

test "RectQ overlaps deterministic" {
    const a = RectQ.init(0, 0, 10, 10);
    const b = RectQ.init(5, 5, 10, 10);
    const c = RectQ.init(20, 20, 5, 5);
    try std.testing.expect(a.overlaps(b));
    try std.testing.expect(!a.overlaps(c));
}
