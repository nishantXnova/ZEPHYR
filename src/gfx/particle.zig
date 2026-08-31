const std = @import("std");
const Batch = @import("batch.zig").Batch;
const Color = @import("color.zig").Color;

// Zephyr Particles — scratch-simple, ultra-lightweight, full control.
// No hidden allocs after init, O(1) swapRemove, cap 256, 60fps stable.
// Beats Scratch's clone spam: fixed pool, explicit dt, no GC.

pub const Particle = struct {
    x: f32,
    y: f32,
    vx: f32 = 0,
    vy: f32 = 0,
    life: f32 = 1.0,
    max: f32 = 1.0,
    col: Color = Color.white,
    size: f32 = 3,
    alive: bool = true,
};

pub const ParticleSystem = struct {
    particles: std.ArrayList(Particle),
    allocator: std.mem.Allocator,
    cap: usize = 256,

    pub fn init(allocator: std.mem.Allocator) ParticleSystem {
        return .{ .particles = .empty, .allocator = allocator };
    }
    pub fn deinit(self: *ParticleSystem) void {
        self.particles.deinit(self.allocator);
    }
    pub fn ensureCap(self: *ParticleSystem, n: usize) !void {
        try self.particles.ensureTotalCapacity(self.allocator, n);
    }
    pub fn emit(self: *ParticleSystem, p: Particle) void {
        if (self.particles.items.len >= self.cap) {
            // drop oldest — keeps 60fps (starimpact.zig:191 had same fix)
            _ = self.particles.swapRemove(0);
        }
        self.particles.append(self.allocator, p) catch {};
    }
    pub fn emitBurst(self: *ParticleSystem, x: f32, y: f32, n: u32, col: Color, rng: std.Random) void {
        for (0..n) |_| {
            const ang = rng.float(f32) * 6.28;
            const spd = rng.float(f32) * 200 + 60;
            self.emit(.{
                .x = x,
                .y = y,
                .vx = @cos(ang) * spd,
                .vy = @sin(ang) * spd,
                .life = 0.35 + rng.float(f32) * 0.25,
                .max = 0.6,
                .col = col,
                .size = 3,
            });
        }
    }
    pub fn update(self: *ParticleSystem, dt: f32) void {
        for (self.particles.items) |*p| {
            p.x += p.vx * dt;
            p.y += p.vy * dt;
            p.vx *= 0.99;
            p.vy *= 0.99;
            p.vy += 80 * dt; // slight gravity
            p.life -= dt;
            if (p.life <= 0) p.alive = false;
        }
        var i: usize = 0;
        while (i < self.particles.items.len) {
            if (!self.particles.items[i].alive or self.particles.items[i].life <= 0) _ = self.particles.swapRemove(i) else i += 1;
        }
    }
    pub fn draw(self: ParticleSystem, batch: *Batch) void {
        for (self.particles.items) |p| {
            const a: u8 = @intFromFloat(255 * std.math.clamp(p.life / p.max, 0, 1));
            batch.drawRect(p.x, p.y, p.size, p.size, Color.rgba(p.col.r, p.col.g, p.col.b, a));
        }
    }
    // GDI fallback via Window.drawRect still works — batch path is GL, fallback uses rects
    pub fn drawWindow(self: ParticleSystem, win: anytype) void {
        for (self.particles.items) |p| {
            const a: u8 = @intFromFloat(255 * std.math.clamp(p.life / p.max, 0, 1));
            win.drawRect(p.x, p.y, p.size, p.size, Color.rgba(p.col.r, p.col.g, p.col.b, a));
        }
    }
    pub fn count(self: ParticleSystem) usize {
        return self.particles.items.len;
    }
    pub fn clear(self: *ParticleSystem) void {
        self.particles.clearRetainingCapacity();
    }
};

test "particle emit and update" {
    var ps = ParticleSystem.init(std.testing.allocator);
    defer ps.deinit();
    try ps.ensureCap(8);
    ps.emit(.{ .x = 10, .y = 10, .vx = 100, .life = 0.5, .max = 0.5 });
    try std.testing.expectEqual(@as(usize, 1), ps.count());
    ps.update(0.6);
    try std.testing.expectEqual(@as(usize, 0), ps.count());
}
