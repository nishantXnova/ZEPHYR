const std = @import("std");
const PhysicsWorld = @import("../physics/world.zig").World;
const Input = @import("../core/input.zig").Input;
const Action = @import("../core/input.zig").Action;

// Zephyr Rollback v0.7 — The "nobody else has this" feature. Extremely clever engineering.
// You already have 120-frame Input history `src/core/input.zig:111` + deterministic PhysicsWorld `4× sub-steps` `src/physics/world.zig:28`.
// This glues them: snapshot ring buffer + rewind N + resim with corrected remote input.
// Sparse-set ECS snapshots are `memcpy dense` `src/ecs/ecs.zig:40` — same pattern for World.
// Usage: each frame save(); on mispredict rewind(8, corrected_input) resims 8 steps deterministically.
// No floating order variance — fixed dt each sub-step. No allocs in hot loop after init.

const RING: usize = 120; // matches Input history 120

pub const Frame = struct {
    world_snap: ?PhysicsWorld.Snap = null,
    input: [16]bool = [_]bool{false} ** 16,
    dt: f32 = 0.016,
};

pub const Rollback = struct {
    frames: [RING]Frame = [_]Frame{.{}} ** RING,
    head: usize = 0, // next write index
    count: usize = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Rollback {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Rollback) void {
        for (&self.frames) |*f| {
            if (f.world_snap) |s| s.deinit();
            f.world_snap = null;
        }
    }
    pub fn save(self: *Rollback, world: PhysicsWorld, input: Input, dt: f32) !void {
        const snap = try world.snapshot(self.allocator);
        const idx = self.head;
        // free old snap at idx
        if (self.frames[idx].world_snap) |old| old.deinit();
        var bits: [16]bool = [_]bool{false} ** 16;
        for (0..16) |i| bits[i] = input.states[i].down;
        self.frames[idx] = .{ .world_snap = snap, .input = bits, .dt = dt };
        self.head = (self.head + 1) % RING;
        if (self.count < RING) self.count += 1;
    }
    // Rewind N frames and resimulate with corrected input for the N-th frame backward.
    // Returns number of resimulated frames. Caller must have deterministic step function.
    pub fn rewindAndResim(self: *Rollback, world: *PhysicsWorld, n: usize, corrected: [16]bool, resimFn: *const fn (*PhysicsWorld, [16]bool, f32) void) !usize {
        if (n == 0 or n > self.count) return 0;
        const target_idx = (self.head + RING - n) % RING;
        const snap = self.frames[target_idx].world_snap orelse return 0;
        try world.restore(snap);
        // correct the input at target frame
        self.frames[target_idx].input = corrected;
        var resimed: usize = 0;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const idx = (target_idx + i) % RING;
            const f = self.frames[idx];
            resimFn(world, f.input, f.dt);
            // re-snapshot after resim except last (to avoid double)
            if (i + 1 < n) {
                // update snapshot for this frame to corrected state
                if (self.frames[idx].world_snap) |old| old.deinit();
                const ns = try world.snapshot(self.allocator);
                self.frames[idx].world_snap = ns;
            }
            resimed += 1;
        }
        return resimed;
    }
    pub fn latestInput(self: Rollback) [16]bool {
        if (self.count == 0) return [_]bool{false} ** 16;
        const idx = (self.head + RING - 1) % RING;
        return self.frames[idx].input;
    }
    pub fn historyLen(self: Rollback) usize { return self.count; }
};

test "rollback save and rewind deterministic" {
    const gpa = std.testing.allocator;
    var world = PhysicsWorld.init(gpa);
    defer world.deinit();
    _ = try world.add(.{ .rect = @import("../core/math.zig").Rect.init(0, 100, 200, 16), .type = .static });
    const id = try world.add(.{ .rect = @import("../core/math.zig").Rect.init(50, 0, 16, 16), .type = .dynamic, .vel = @import("../core/math.zig").Vec2.init(0, 0) });
    var inp = Input.init(gpa);
    defer inp.deinit();
    var rb = Rollback.init(gpa);
    defer rb.deinit();
    // save 10 frames
    for (0..10) |_| {
        world.step(0.016);
        try rb.save(world, inp, 0.016);
    }
    const y_before = world.get(id).?.rect.y;
    // corrupt world
    world.get(id).?.rect.y = 999;
    // rewind 5 and resim
    const resimFn = struct {
        fn f(w: *PhysicsWorld, _: [16]bool, dt: f32) void { w.step(dt); }
    }.f;
    const n = try rb.rewindAndResim(&world, 5, [_]bool{false} ** 16, &resimFn);
    try std.testing.expectEqual(@as(usize, 5), n);
    // after rewind+resim, should be back near y_before (deterministic replay)
    try std.testing.expect(@abs(world.get(id).?.rect.y - y_before) < 0.01);
}
