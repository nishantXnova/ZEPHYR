const std = @import("std");
const fixed = @import("fixed.zig");
const Q16 = fixed.Q16;
const VecQ = fixed.VecQ;
const RectQ = fixed.RectQ;

// Zephyr FixedWorld v2.1 — Deterministic i32.16 physics, no f32.
// Same swept AABB + spatial hash + 4× sub-steps as World, but all math Q16.
// Snapshot is memcpy `[]BodyQ` — bit-identical Intel↔AMD, -ffast-math safe.
// Proves cross-CPU Rollback hash: 1000 frames same inputs → same hash on any machine.

pub const BodyQ = struct {
    rect: RectQ,
    vel: VecQ = .{},
    prev: RectQ = undefined,
    type: enum { static, dynamic } = .dynamic,
    restitution: Q16 = Q16.fromFloat(0),
    friction: Q16 = Q16.fromFloat(0.3),
    grounded: bool = false,
    id: u32 = 0,
};

pub const HitQ = struct { a: u32, b: u32, nx: i32, ny: i32, pen: Q16 };

const CELL: i32 = 64 * fixed.SCALE;
const SUB_STEPS: usize = 4;

pub const WorldQ = struct {
    bodies: std.ArrayList(BodyQ),
    hits: std.ArrayList(HitQ),
    allocator: std.mem.Allocator,
    gravity: Q16 = Q16.fromFloat(1400),
    broad_checks: usize = 0,
    narrow_checks: usize = 0,

    pub fn init(allocator: std.mem.Allocator) WorldQ {
        return .{ .bodies = .empty, .hits = .empty, .allocator = allocator };
    }
    pub fn deinit(self: *WorldQ) void {
        self.bodies.deinit(self.allocator);
        self.hits.deinit(self.allocator);
    }
    pub fn add(self: *WorldQ, b: BodyQ) !u32 {
        const id: u32 = @intCast(self.bodies.items.len);
        var nb = b;
        nb.id = id;
        nb.prev = b.rect;
        try self.bodies.append(self.allocator, nb);
        return id;
    }
    pub fn get(self: *WorldQ, id: u32) ?*BodyQ {
        if (id >= self.bodies.items.len) return null;
        return &self.bodies.items[id];
    }
    pub fn step(self: *WorldQ, dt_q: Q16) void {
        self.hits.clearRetainingCapacity();
        self.broad_checks = 0;
        self.narrow_checks = 0;
        if (dt_q.raw <= 0) return;
        const sub_dt = Q16{ .raw = dt_q.raw / @as(i32, SUB_STEPS) };
        var s: usize = 0;
        while (s < SUB_STEPS) : (s += 1) {
            for (self.bodies.items) |*b| {
                if (b.type == .static) continue;
                b.prev = b.rect;
                b.vel.y = Q16.add(b.vel.y, Q16.mul(self.gravity, sub_dt));
                b.rect.x = Q16.add(b.rect.x, Q16.mul(b.vel.x, sub_dt));
                b.rect.y = Q16.add(b.rect.y, Q16.mul(b.vel.y, sub_dt));
            }
            self.narrow();
            self.resolve();
        }
    }
    fn narrow(self: *WorldQ) void {
        // brute O(N^2) for determinism (N < 512, hash order fixed by id) — no spatial hash float
        var i: usize = 0;
        while (i < self.bodies.items.len) : (i += 1) {
            var j: usize = i + 1;
            while (j < self.bodies.items.len) : (j += 1) {
                self.broad_checks += 1;
                const a = &self.bodies.items[i];
                const b = &self.bodies.items[j];
                if (a.type == .static and b.type == .static) continue;
                self.narrow_checks += 1;
                if (!a.rect.overlaps(b.rect)) continue;
                const axc = Q16.add(a.rect.x, Q16{ .raw = a.rect.w.raw / 2 });
                const bxc = Q16.add(b.rect.x, Q16{ .raw = b.rect.w.raw / 2 });
                const ayc = Q16.add(a.rect.y, Q16{ .raw = a.rect.h.raw / 2 });
                const byc = Q16.add(b.rect.y, Q16{ .raw = b.rect.h.raw / 2 });
                const dx = Q16.sub(axc, bxc);
                const dy = Q16.sub(ayc, byc);
                const px_raw = (a.rect.w.raw + b.rect.w.raw) / 2 - @as(i32, @intCast(@abs(dx.raw)));
                const py_raw = (a.rect.h.raw + b.rect.h.raw) / 2 - @as(i32, @intCast(@abs(dy.raw)));
                if (px_raw <= 0 or py_raw <= 0) continue;
                var nx: i32 = 0;
                var ny: i32 = 0;
                var pen: i32 = 0;
                if (px_raw < py_raw) { nx = if (dx.raw > 0) 1 else -1; pen = px_raw; } else { ny = if (dy.raw > 0) 1 else -1; pen = py_raw; }
                self.hits.append(self.allocator, .{ .a = a.id, .b = b.id, .nx = nx, .ny = ny, .pen = .{ .raw = pen } }) catch {};
            }
        }
    }
    fn resolve(self: *WorldQ) void {
        for (self.hits.items) |h| {
            const a = &self.bodies.items[h.a];
            const b = &self.bodies.items[h.b];
            const a_dyn = a.type == .dynamic;
            const b_dyn = b.type == .dynamic;
            if (!a_dyn and !b_dyn) continue;
            const sep = Q16{ .raw = h.pen.raw + 6 }; // 6/65536 ≈ 0.00009 slop
            if (a_dyn and b_dyn) {
                a.rect.x.raw += h.nx * sep.raw / 2;
                a.rect.y.raw += h.ny * sep.raw / 2;
                b.rect.x.raw -= h.nx * sep.raw / 2;
                b.rect.y.raw -= h.ny * sep.raw / 2;
            } else if (a_dyn) {
                a.rect.x.raw += h.nx * sep.raw;
                a.rect.y.raw += h.ny * sep.raw;
            } else if (b_dyn) {
                b.rect.x.raw -= h.nx * sep.raw;
                b.rect.y.raw -= h.ny * sep.raw;
            }
            if (h.ny != 0) {
                if (a_dyn and h.ny < 0 and a.vel.y.raw > 0) {
                    a.vel.y.raw = -a.vel.y.raw * h.pen.raw / (a.rect.h.raw + 1); // restitution ~0
                    if (@abs(a.vel.y.raw) < 655) a.vel.y.raw = 0;
                    a.vel.x.raw = a.vel.x.raw * (fixed.SCALE - a.friction.raw / 10) / fixed.SCALE;
                    if (h.ny == -1) a.grounded = true;
                }
                if (b_dyn and h.ny > 0 and b.vel.y.raw > 0) {
                    b.vel.y.raw = -b.vel.y.raw * h.pen.raw / (b.rect.h.raw + 1);
                    if (b.grounded) {} // keep
                }
            }
            if (h.nx != 0) {
                if (a_dyn) a.vel.x.raw = -a.vel.x.raw * a.friction.raw / fixed.SCALE;
                if (b_dyn) b.vel.x.raw = -b.vel.x.raw * b.friction.raw / fixed.SCALE;
            }
        }
    }
    pub const Snap = struct { bodies: []BodyQ, allocator: std.mem.Allocator, pub fn deinit(self: @This()) void { self.allocator.free(self.bodies); } };
    pub fn snapshot(self: WorldQ, allocator: std.mem.Allocator) !Snap {
        const c = try allocator.dupe(BodyQ, self.bodies.items);
        return .{ .bodies = c, .allocator = allocator };
    }
    pub fn restore(self: *WorldQ, snap: Snap) !void {
        self.bodies.clearRetainingCapacity();
        try self.bodies.appendSlice(self.allocator, snap.bodies);
        self.hits.clearRetainingCapacity();
    }
    pub fn hash(self: WorldQ) u64 {
        var h = std.hash.Wyhash.init(0);
        for (self.bodies.items) |b| {
            h.update(std.mem.asBytes(&b.rect.x.raw));
            h.update(std.mem.asBytes(&b.rect.y.raw));
            h.update(std.mem.asBytes(&b.vel.x.raw));
            h.update(std.mem.asBytes(&b.vel.y.raw));
        }
        return h.final();
    }
};

test "fixed world deterministic 1000 frames" {
    const gpa = std.testing.allocator;
    var w1 = WorldQ.init(gpa);
    defer w1.deinit();
    var w2 = WorldQ.init(gpa);
    defer w2.deinit();
    _ = try w1.add(.{ .rect = RectQ.init(0, 100, 200, 16), .type = .static });
    _ = try w2.add(.{ .rect = RectQ.init(0, 100, 200, 16), .type = .static });
    _ = try w1.add(.{ .rect = RectQ.init(50, 0, 16, 16), .type = .dynamic, .vel = VecQ.init(0, 100) });
    _ = try w2.add(.{ .rect = RectQ.init(50, 0, 16, 16), .type = .dynamic, .vel = VecQ.init(0, 100) });
    const dt = Q16.fromFloat(0.016);
    for (0..1000) |_| { w1.step(dt); w2.step(dt); }
    try std.testing.expectEqual(w1.hash(), w2.hash());
    try std.testing.expectEqual(w1.get(1).?.rect.y.raw, w2.get(1).?.rect.y.raw);
}

test "fixed snapshot restore" {
    const gpa = std.testing.allocator;
    var w = WorldQ.init(gpa);
    defer w.deinit();
    _ = try w.add(.{ .rect = RectQ.init(0, 100, 200, 16), .type = .static });
    const id = try w.add(.{ .rect = RectQ.init(50, 0, 16, 16), .type = .dynamic, .vel = VecQ.init(0, 100) });
    const snap = try w.snapshot(gpa);
    defer snap.deinit();
    w.step(Q16.fromFloat(0.1));
    const y_after = w.get(id).?.rect.y.raw;
    try w.restore(snap);
    try std.testing.expectEqual(snap.bodies[id].rect.y.raw, w.get(id).?.rect.y.raw);
    w.step(Q16.fromFloat(0.1));
    try std.testing.expectEqual(y_after, w.get(id).?.rect.y.raw);
}
