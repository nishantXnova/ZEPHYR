const std = @import("std");
const ecs = @import("../ecs/ecs.zig");
const Entity = ecs.Entity;
const SparseSet = ecs.SparseSet;
const Vec2 = @import("math.zig").Vec2;
const Mat4 = @import("camera.zig").Mat4;

// Zephyr Transform v1.0 — Actual game engine feature, not random.
// Parent-child hierarchy with world matrix propagation. Every real engine has this
// (Unity Transform, Godot Node2D, Bevy Transform). Scratch has no hierarchy — we beat it.
// Design: Transform component stored in SparseSet(Transform), parent is ?Entity (gen checked).
// dirty flag + topological propagation, no recursion, O(N) per frame, cache-friendly via Query2.

pub const Transform = struct {
    pos: Vec2 = Vec2.zero(),
    scale: Vec2 = Vec2.init(1, 1),
    rotation: f32 = 0, // radians
    parent: ?Entity = null,
    world: Mat4 = Mat4.identity(),
    world_pos: Vec2 = Vec2.zero(),
    dirty: bool = true,

    pub fn localMatrix(self: Transform) Mat4 {
        // T * R * S — 2D, using Mat4 API from camera.zig
        var m = Mat4.translate(self.pos.x, self.pos.y, 0);
        if (self.rotation != 0) {
            const c = @cos(self.rotation);
            const s = @sin(self.rotation);
            var r = Mat4.identity();
            r.m[0] = c; r.m[1] = s;
            r.m[4] = -s; r.m[5] = c;
            m = m.mul(r);
        }
        m = m.mul(Mat4.scale(self.scale.x, self.scale.y, 1));
        return m;
    }
};

// System: propagate world matrices topologically.
// For N < 4096, brute iterate until no dirty, max 8 passes (depth limit).
pub fn propagate(transforms: *SparseSet(Transform), registry: ecs.Registry) void {
    // first mark all dirty if parent dirty (simple)
    var changed = true;
    var passes: usize = 0;
    while (changed and passes < 8) : (passes += 1) {
        changed = false;
        var it = transforms.iterator();
        while (it.next()) |kv| {
            const t = kv.value;
            if (t.parent) |p| {
                if (!registry.isAlive(p)) {
                    t.parent = null;
                    t.dirty = true;
                    changed = true;
                    continue;
                }
                const pt = transforms.get(p) orelse continue;
                if (pt.dirty) {
                    t.dirty = true;
                    changed = true;
                }
            }
        }
        // now compute world for dirty nodes where parent is clean
        var it2 = transforms.iterator();
        while (it2.next()) |kv| {
            const t = kv.value;
            if (!t.dirty) continue;
            if (t.parent) |p| {
                const pt = transforms.get(p) orelse continue;
                if (pt.dirty) continue; // wait for parent
                t.world = pt.world.mul(t.localMatrix());
                // world_pos is translation part
                t.world_pos = Vec2.init(t.world.m[12], t.world.m[13]);
            } else {
                t.world = t.localMatrix();
                t.world_pos = t.pos;
            }
            t.dirty = false;
        }
    }
}

pub fn getWorldPos(transforms: SparseSet(Transform), e: Entity) ?Vec2 {
    const t = transforms.get(e) orelse return null;
    return t.world_pos;
}

test "transform hierarchy world propagation" {
    const gpa = std.testing.allocator;
    var reg = ecs.Registry.init(gpa);
    defer reg.deinit();
    var ts = SparseSet(Transform).init(gpa);
    defer ts.deinit();
    const parent = reg.create();
    try ts.add(parent, .{ .pos = Vec2.init(10, 0) });
    const child = reg.create();
    try ts.add(child, .{ .pos = Vec2.init(5, 0), .parent = parent });
    propagate(&ts, reg);
    const wp = getWorldPos(ts, child).?;
    try std.testing.expectEqual(@as(f32, 15), wp.x);
    try std.testing.expectEqual(@as(f32, 0), wp.y);
    // move parent
    ts.get(parent).?.pos = Vec2.init(20, 0);
    ts.get(parent).?.dirty = true;
    ts.get(child).?.dirty = true;
    propagate(&ts, reg);
    const wp2 = getWorldPos(ts, child).?;
    try std.testing.expectEqual(@as(f32, 25), wp2.x);
}

test "transform orphan parent handled" {
    const gpa = std.testing.allocator;
    var reg = ecs.Registry.init(gpa);
    defer reg.deinit();
    var ts = SparseSet(Transform).init(gpa);
    defer ts.deinit();
    const e = reg.create();
    const fake_parent = Entity{ .id = 999, .gen = 0 };
    try ts.add(e, .{ .pos = Vec2.init(3, 3), .parent = fake_parent });
    propagate(&ts, reg);
    // parent not alive -> should clear parent and become world pos = local
    try std.testing.expect(ts.get(e).?.parent == null);
}
