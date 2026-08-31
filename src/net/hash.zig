const std = @import("std");
const PhysicsWorld = @import("../physics/world.zig").World;

// Zephyr Hash v0.8 — per-frame xxhash desync detection.
// Hash snapshot bytes (bodies rect/vel) exchanged alongside input in Packet.hash.
// First divergence flagged — separates "demo once" from "trustworthy netcode".
// Uses Wyhash (std.hash.Wyhash) — fast, no allocs.

pub fn hashWorld(world: PhysicsWorld) u64 {
    var h = std.hash.Wyhash.init(0);
    for (world.bodies.items) |b| {
        // hash rect + vel deterministically — fixed order, no map iteration
        const rect_bytes = std.mem.asBytes(&b.rect);
        h.update(rect_bytes);
        const vel_bytes = std.mem.asBytes(&b.vel);
        h.update(vel_bytes);
        // grounded as u8
        h.update(&[_]u8{ if (b.grounded) 1 else 0 });
    }
    return h.final();
}

pub fn hashBytes(bytes: []const u8) u64 {
    var h = std.hash.Wyhash.init(0);
    h.update(bytes);
    return h.final();
}

test "hash deterministic" {
    const gpa = std.testing.allocator;
    var w = PhysicsWorld.init(gpa);
    defer w.deinit();
    _ = try w.add(.{ .rect = @import("../core/math.zig").Rect.init(0, 0, 16, 16), .type = .dynamic, .vel = @import("../core/math.zig").Vec2.init(10, 0) });
    const h1 = hashWorld(w);
    const snap = try w.snapshot(gpa);
    defer snap.deinit();
    w.step(0.016);
    const h2 = hashWorld(w);
    try std.testing.expect(h1 != h2);
    try w.restore(snap);
    const h3 = hashWorld(w);
    try std.testing.expectEqual(h1, h3);
}

test "hash stress 1000 same inputs" {
    const gpa = std.testing.allocator;
    var w1 = PhysicsWorld.init(gpa);
    defer w1.deinit();
    var w2 = PhysicsWorld.init(gpa);
    defer w2.deinit();
    _ = try w1.add(.{ .rect = @import("../core/math.zig").Rect.init(0, 100, 200, 16), .type = .static });
    _ = try w2.add(.{ .rect = @import("../core/math.zig").Rect.init(0, 100, 200, 16), .type = .static });
    const id1 = try w1.add(.{ .rect = @import("../core/math.zig").Rect.init(50, 0, 16, 16), .type = .dynamic, .vel = @import("../core/math.zig").Vec2.init(0, 100) });
    const id2 = try w2.add(.{ .rect = @import("../core/math.zig").Rect.init(50, 0, 16, 16), .type = .dynamic, .vel = @import("../core/math.zig").Vec2.init(0, 100) });
    _ = id1; _ = id2;
    for (0..1000) |_| { w1.step(0.016); w2.step(0.016); }
    const h1 = hashWorld(w1);
    const h2 = hashWorld(w2);
    try std.testing.expectEqual(h1, h2);
}
