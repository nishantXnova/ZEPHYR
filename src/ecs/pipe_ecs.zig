//! Pipe ECS — systems for Zephyr Flappy. Pluggable 2D → 3D (just add Z).
const std = @import("std");
const ecs = @import("ecs.zig");
const math = @import("../core/math.zig");
const Color = @import("../gfx/color.zig").Color;

pub const Pipe = struct {
    x: f32,
    gap_y: f32,
    gap_h: f32,
    width: f32,
    scored: bool = false,
};

pub const Velocity = struct { x: f32 };

// PipeSystem owns its SparseSets and Registry handle
pub const PipeSystem = struct {
    registry: ecs.Registry,
    pipes: ecs.SparseSet(Pipe),
    spawn_timer: f32 = 0,
    spawn_interval: f32 = 1.45,
    speed: f32 = 165,
    pipe_width: f32 = 64,
    pipe_gap: f32 = 145,
    world_w: f32 = 480,
    world_h: f32 = 640,
    ground_h: f32 = 80,
    rng: std.Random,

    pub fn init(allocator: std.mem.Allocator, rng: std.Random, world_w: f32, world_h: f32) PipeSystem {
        return .{
            .registry = ecs.Registry.init(allocator),
            .pipes = ecs.SparseSet(Pipe).init(allocator),
            .rng = rng,
            .world_w = world_w,
            .world_h = world_h,
            .spawn_timer = 1.45 * 0.5,
        };
    }
    pub fn deinit(self: *PipeSystem) void {
        self.pipes.deinit();
        self.registry.deinit();
    }
    pub fn reset(self: *PipeSystem) void {
        // destroy all pipe entities
        var it = self.pipes.iterator();
        var to_remove: [64]ecs.Entity = undefined;
        var n: usize = 0;
        while (it.next()) |kv| {
            if (n < to_remove.len) {
                to_remove[n] = kv.entity;
                n += 1;
            }
        }
        for (to_remove[0..n]) |e| {
            _ = self.pipes.remove(e);
            self.registry.destroy(e);
        }
        self.spawn_timer = self.spawn_interval * 0.5;
    }

    pub fn update(self: *PipeSystem, dt: f32, score: *u32) void {
        // spawn
        self.spawn_timer -= dt;
        if (self.spawn_timer <= 0) {
            self.spawn_timer = self.spawn_interval;
            const min_y: f32 = 90;
            const max_y: f32 = self.world_h - self.ground_h - 90;
            const gap_y = self.rng.float(f32) * (max_y - min_y) + min_y;
            const e = self.registry.create();
            self.pipes.add(e, .{ .x = self.world_w + 10, .gap_y = gap_y, .gap_h = self.pipe_gap, .width = self.pipe_width }) catch {};
        }
        // move + score + cull
        var it = self.pipes.iterator();
        var dead: [32]ecs.Entity = undefined;
        var dead_n: usize = 0;
        while (it.next()) |kv| {
            kv.value.x -= self.speed * dt;
            if (!kv.value.scored and kv.value.x + kv.value.width < 90) { // BIRD_X
                kv.value.scored = true;
                score.* += 1;
            }
            if (kv.value.x + kv.value.width < -20 and dead_n < dead.len) {
                dead[dead_n] = kv.entity;
                dead_n += 1;
            }
        }
        for (dead[0..dead_n]) |e| {
            _ = self.pipes.remove(e);
            self.registry.destroy(e);
        }
    }

    pub fn checkCollision(self: *PipeSystem, bird_rect: math.Rect) bool {
        var it = self.pipes.iterator();
        while (it.next()) |kv| {
            const p = kv.value.*;
            const top = math.Rect.init(p.x, 0, p.width, p.gap_y - p.gap_h / 2);
            const bot = math.Rect.init(p.x, p.gap_y + p.gap_h / 2, p.width, self.world_h);
            if (bird_rect.overlaps(top) or bird_rect.overlaps(bot)) return true;
        }
        return false;
    }

    pub fn draw(self: *PipeSystem, win: anytype) void {
        var it = self.pipes.iterator();
        while (it.next()) |kv| {
            const p = kv.value.*;
            const top_h = p.gap_y - p.gap_h / 2;
            const bot_y = p.gap_y + p.gap_h / 2;
            const bot_h = self.world_h - self.ground_h - bot_y;
            win.drawRect(p.x, 0, p.width, top_h, Color.pipe);
            win.drawRect(p.x, bot_y, p.width, bot_h, Color.pipe);
            const cap_h: f32 = 22;
            win.drawRect(p.x - 4, top_h - cap_h, p.width + 8, cap_h, Color.rgb(28, 110, 28));
            win.drawRect(p.x - 4, bot_y, p.width + 8, cap_h, Color.rgb(28, 110, 28));
        }
    }
};
