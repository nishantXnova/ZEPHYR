const std = @import("std");
const Zephyr = @import("Zephyr");
const App = Zephyr.App;
const Color = Zephyr.Color;
const Rect = Zephyr.Rect;
const Texture = Zephyr.Texture;
const SpriteSheet = Zephyr.SpriteSheet;
const Animator = Zephyr.Animator;
const win32 = Zephyr.win32;

const WW: f32 = 960;
const WH: f32 = 600;
const SHIP_S: f32 = 48;
const LASER_S = struct { w: f32 = 8, h: f32 = 20 };
const AST_S: f32 = 48;

const Ship = struct {
    x: f32,
    y: f32,
    vx: f32 = 0,
    vy: f32 = 0,
    angle: f32 = -1.570796, // up
    cooldown: f32 = 0,
    alive: bool = true,
};

const Laser = struct {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    alive: bool = true,
    t: f32 = 0,
};

const Asteroid = struct {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    angle: f32 = 0,
    spin: f32 = 0,
    alive: bool = true,
    kind: u32 = 0, // 0 asteroid, 1 enemy
};

const Particle = struct {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    life: f32,
    max: f32,
    col: Color,
};

const Explosion = struct {
    x: f32,
    y: f32,
    t: f32 = 0,
    alive: bool = true,
};

pub fn main(init: std.process.Init) !void {
    _ = init;
    const allocator = std.heap.c_allocator;
    var prng = std.Random.DefaultPrng.init(0xCAFEBABE1234);
    const rng = prng.random();

    var app = try App.init(.{ .title = "Zephyr Space War — WASD/Arrows move, SPACE laser, P pause", .width = @intFromFloat(WW), .height = @intFromFloat(WH) });
    defer app.deinit();

    // Assets — high quality
    var ship_tex_l: ?Texture = null; var ship_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/ship.png", allocator) catch null) |t| { ship_tex_l = t; ship_tex = &ship_tex_l.?; }
    defer if (ship_tex_l) |*t| t.deinit();
    var laser_tex_l: ?Texture = null; var laser_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/laser.png", allocator) catch null) |t| { laser_tex_l = t; laser_tex = &laser_tex_l.?; }
    defer if (laser_tex_l) |*t| t.deinit();
    var asteroid_tex_l: ?Texture = null; var asteroid_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/asteroid.png", allocator) catch null) |t| { asteroid_tex_l = t; asteroid_tex = &asteroid_tex_l.?; }
    defer if (asteroid_tex_l) |*t| t.deinit();
    var enemy_tex_l: ?Texture = null; var enemy_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/enemy.png", allocator) catch null) |t| { enemy_tex_l = t; enemy_tex = &enemy_tex_l.?; }
    defer if (enemy_tex_l) |*t| t.deinit();
    var explosion_tex_l: ?Texture = null; var explosion_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/explosion.png", allocator) catch null) |t| {
        explosion_tex_l = t; explosion_tex = &explosion_tex_l.?;
    }
    defer if (explosion_tex_l) |*t| t.deinit();
    var digits_tex_l: ?Texture = null; var digits_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/digits.png", allocator) catch null) |t| { digits_tex_l = t; digits_tex = &digits_tex_l.?; }
    defer if (digits_tex_l) |*t| t.deinit();
    const score_board = if (digits_tex) |tex| Zephyr.ScoreBoard{ .tex = tex, .x = WW - 110, .y = 12, .digits = 6 } else null;

    var audio = Zephyr.AudioEngine{ .engine = undefined };
    audio.init() catch {};
    defer audio.deinit();
    var laser_snd: ?Zephyr.Sound = if (audio.inited) audio.loadSound("assets/laser.wav", allocator) catch null else null;
    var explode_snd: ?Zephyr.Sound = if (audio.inited) audio.loadSound("assets/explode.wav", allocator) catch null else null;
    defer {
        if (laser_snd) |*s| audio.unload(s);
        if (explode_snd) |*s| audio.unload(s);
    }

    // Game state
    var ship = Ship{ .x = WW / 2 - SHIP_S / 2, .y = WH / 2 - SHIP_S / 2 };
    var lasers: std.ArrayList(Laser) = .empty;
    defer lasers.deinit(allocator);
    var asteroids: std.ArrayList(Asteroid) = .empty;
    defer asteroids.deinit(allocator);
    var particles: std.ArrayList(Particle) = .empty;
    defer particles.deinit(allocator);
    var explosions: std.ArrayList(Explosion) = .empty;
    defer explosions.deinit(allocator);
    // Star Wars — whole dimension moving forward, particles from ahead
    const Star = struct { x: f32, y: f32, z: f32 };
    var stars: [150]Star = undefined;
    for (0..stars.len) |i| {
        stars[i].x = (rng.float(f32) - 0.5) * WW * 2.2;
        stars[i].y = (rng.float(f32) - 0.5) * WH * 2.2;
        stars[i].z = rng.float(f32) * 900 + 100;
    }
    var score: u32 = 0;
    var lives: u32 = 3;
    var wave: u32 = 1;
    var spawn_timer: f32 = 1.2;
    var invuln: f32 = 0;

    std.debug.print("Zephyr Space War — WASD/Arrows thrust/rotate, SPACE laser, R reset\n", .{});

    while (!app.shouldClose()) {
        app.poll();
        if (app.win.isKeyDown(win32.VK_ESCAPE)) break;
        if (app.win.isKeyPressed('R')) {
            ship = .{ .x = WW / 2 - SHIP_S / 2, .y = WH / 2 - SHIP_S / 2, .angle = -1.570796 };
            lasers.clearRetainingCapacity(); asteroids.clearRetainingCapacity(); particles.clearRetainingCapacity(); explosions.clearRetainingCapacity();
            score = 0; lives = 3; wave = 1; spawn_timer = 1.2; invuln = 1.5;
        }

        const dt = app.tick();
        const thrust: f32 = 520;
        const rot_speed: f32 = 3.2;
        const drag: f32 = 0.995;
        const laser_cooldown: f32 = 0.13;

        // Input
        var turn: f32 = 0;
        if (app.win.isKeyDown('A') or app.win.isKeyDown(0x25)) turn -= 1;
        if (app.win.isKeyDown('D') or app.win.isKeyDown(0x27)) turn += 1;
        ship.angle += turn * rot_speed * dt;
        var thrusting = false;
        if (app.win.isKeyDown('W') or app.win.isKeyDown(0x26) or app.win.isKeyDown(win32.VK_UP)) {
            thrusting = true;
            ship.vx += @cos(ship.angle) * thrust * dt;
            ship.vy += @sin(ship.angle) * thrust * dt;
            // thrust particles
            if (rng.float(f32) < 0.7) {
                const ang = ship.angle + std.math.pi + (rng.float(f32) - 0.5) * 0.5;
                particles.append(allocator, .{
                    .x = ship.x + SHIP_S / 2 + @cos(ship.angle) * -18,
                    .y = ship.y + SHIP_S / 2 + @sin(ship.angle) * -18,
                    .vx = @cos(ang) * 80 + rng.float(f32) * 20,
                    .vy = @sin(ang) * 80 + rng.float(f32) * 20,
                    .life = 0.3, .max = 0.3, .col = Color.rgb(255, 140, 40),
                }) catch {};
            }
        }
        ship.vx *= drag; ship.vy *= drag;
        ship.x += ship.vx * dt;
        ship.y += ship.vy * dt;
        // wrap
        if (ship.x < -SHIP_S) ship.x = WW;
        if (ship.x > WW) ship.x = -SHIP_S;
        if (ship.y < -SHIP_S) ship.y = WH;
        if (ship.y > WH) ship.y = -SHIP_S;
        ship.cooldown -= dt;
        if (invuln > 0) invuln -= dt;

        const shooting = app.win.isKeyDown(win32.VK_SPACE);
        if (shooting and ship.cooldown <= 0) {
            ship.cooldown = laser_cooldown;
            const cx = ship.x + SHIP_S / 2 + @cos(ship.angle) * 22;
            const cy = ship.y + SHIP_S / 2 + @sin(ship.angle) * 22;
            lasers.append(allocator, .{
                .x = cx - 4, .y = cy - 10, .vx = @cos(ship.angle) * 520 + ship.vx * 0.3, .vy = @sin(ship.angle) * 520 + ship.vy * 0.3,
            }) catch {};
            if (laser_snd) |*s| audio.play(s);
        }

        // spawn asteroids/enemies
        spawn_timer -= dt;
        if (asteroids.items.len > 30) spawn_timer = 0.4;
        if (particles.items.len > 80) {
            if (particles.items.len > 110) _ = particles.swapRemove(0);
        }
        if (spawn_timer <= 0) {
            spawn_timer = @max(0.35, 1.6 - @as(f32, @floatFromInt(wave)) * 0.07);
            const edge = rng.intRangeAtMost(u32, 0, 3);
            var ax: f32 = 0; var ay: f32 = 0; var avx: f32 = 0; var avy: f32 = 0;
            const sp = 60 + rng.float(f32) * (40 + @as(f32, @floatFromInt(wave)) * 8);
            switch (edge) {
                0 => { ax = -AST_S; ay = rng.float(f32) * WH; avx = sp; avy = (rng.float(f32) - 0.5) * 40; },
                1 => { ax = WW; ay = rng.float(f32) * WH; avx = -sp; avy = (rng.float(f32) - 0.5) * 40; },
                2 => { ax = rng.float(f32) * WW; ay = -AST_S; avx = (rng.float(f32) - 0.5) * 40; avy = sp; },
                else => { ax = rng.float(f32) * WW; ay = WH; avx = (rng.float(f32) - 0.5) * 40; avy = -sp; },
            }
            const is_enemy = rng.float(f32) < 0.22;
            asteroids.append(allocator, .{
                .x = ax, .y = ay, .vx = avx, .vy = avy, .angle = rng.float(f32) * 6.28, .spin = (rng.float(f32) - 0.5) * 2.5, .kind = if (is_enemy) 1 else 0,
            }) catch {};
            if (rng.float(f32) < 0.3) wave += 1;
        }

        // update lasers
        for (lasers.items) |*l| {
            l.x += l.vx * dt; l.y += l.vy * dt; l.t += dt;
            if (l.x < -20 or l.x > WW + 20 or l.y < -20 or l.y > WH + 20) l.alive = false;
            if (l.t > 1.4) l.alive = false;
        }
        // update asteroids
        for (asteroids.items) |*a| {
            a.x += a.vx * dt; a.y += a.vy * dt; a.angle += a.spin * dt;
            // wrap
            if (a.x < -AST_S - 20) a.x = WW + 10;
            if (a.x > WW + 20) a.x = -AST_S - 10;
            if (a.y < -AST_S - 20) a.y = WH + 10;
            if (a.y > WH + 20) a.y = -AST_S - 10;
        }
        // collisions laser vs asteroid
        for (lasers.items) |*l| {
            if (!l.alive) continue;
            for (asteroids.items) |*a| {
                if (!a.alive) continue;
                const lr = Rect.init(l.x, l.y, 8, 20);
                const ar = Rect.init(a.x + 4, a.y + 4, AST_S - 8, AST_S - 8);
                if (lr.overlaps(ar)) {
                    l.alive = false; a.alive = false;
                    score += if (a.kind == 1) 50 else 20;
                    explosions.append(allocator, .{ .x = a.x + AST_S / 2 - 16, .y = a.y + AST_S / 2 - 16 }) catch {};
                    if (explode_snd) |*s| audio.play(s);
                    for (0..14) |_| {
                        const ang = rng.float(f32) * 6.28;
                        const sp = rng.float(f32) * 180 + 40;
                        particles.append(allocator, .{
                            .x = a.x + AST_S / 2, .y = a.y + AST_S / 2,
                            .vx = @cos(ang) * sp, .vy = @sin(ang) * sp,
                            .life = 0.4 + rng.float(f32) * 0.3, .max = 0.7,
                            .col = if (a.kind == 1) Color.rgb(255, 80, 80) else Color.rgb(200, 180, 120),
                        }) catch {};
                    }
                    break;
                }
            }
        }
        // ship vs asteroid
        if (invuln <= 0) {
            const sr = Rect.init(ship.x + 8, ship.y + 8, SHIP_S - 16, SHIP_S - 16);
            for (asteroids.items) |*a| {
                if (!a.alive) continue;
                const ar = Rect.init(a.x + 6, a.y + 6, AST_S - 12, AST_S - 12);
                if (sr.overlaps(ar)) {
                    a.alive = false;
                    if (lives > 0) lives -= 1;
                    invuln = 1.2;
                    explosions.append(allocator, .{ .x = ship.x + SHIP_S / 2 - 16, .y = ship.y + SHIP_S / 2 - 16 }) catch {};
                    if (explode_snd) |*s| audio.play(s);
                    for (0..18) |_| {
                        const ang = rng.float(f32) * 6.28;
                        particles.append(allocator, .{
                            .x = ship.x + SHIP_S / 2, .y = ship.y + SHIP_S / 2,
                            .vx = @cos(ang) * (rng.float(f32) * 200 + 30), .vy = @sin(ang) * (rng.float(f32) * 200 + 30),
                            .life = 0.5, .max = 0.5, .col = Color.rgb(100, 180, 255),
                        }) catch {};
                    }
                    if (lives == 0) {}
                    break;
                }
            }
        }

        // update particles
        var pi: usize = 0;
        while (pi < particles.items.len) {
            var p = &particles.items[pi];
            p.x += p.vx * dt; p.y += p.vy * dt; p.vx *= 0.98; p.vy *= 0.98; p.life -= dt;
            if (p.life <= 0) _ = particles.swapRemove(pi) else pi += 1;
        }
        // update explosions
        for (explosions.items) |*e| {
            e.t += dt * 12; // 12 fps
            if (e.t >= 8) e.alive = false;
        }
        // cull dead
        {
            var i: usize = 0;
            while (i < lasers.items.len) {
                if (!lasers.items[i].alive) _ = lasers.swapRemove(i) else i += 1;
            }
        }
        {
            var i: usize = 0;
            while (i < asteroids.items.len) {
                if (!asteroids.items[i].alive) _ = asteroids.swapRemove(i) else i += 1;
            }
        }
        {
            var i: usize = 0;
            while (i < explosions.items.len) {
                if (!explosions.items[i].alive) _ = explosions.swapRemove(i) else i += 1;
            }
        }

        // title
        {
            var tbuf: [128]u8 = undefined;
            const t = std.fmt.bufPrint(&tbuf, "Zephyr Space War Score {d} Lives {d} Wave {d} {s}", .{ score, lives, wave, if (lives == 0) "GAME OVER R" else if (thrusting) "THRUST" else "" }) catch "Zephyr Space War";
            app.win.setTitle(t);
            if (lives == 0 and app.win.isKeyPressed(win32.VK_SPACE)) {
                ship = .{ .x = WW / 2 - SHIP_S / 2, .y = WH / 2 - SHIP_S / 2, .angle = -1.570796 };
                score = 0; lives = 3; wave = 1; invuln = 1.5;
                lasers.clearRetainingCapacity(); asteroids.clearRetainingCapacity(); particles.clearRetainingCapacity(); explosions.clearRetainingCapacity();
            }
        }

        // stars moving forward — whole dimension flying ahead
        for (0..stars.len) |i| {
            stars[i].z -= (280 + @as(f32, @floatFromInt(wave)) * 12 + (if (thrusting) @as(f32, 120) else 0)) * dt;
            if (stars[i].z < 12) {
                stars[i].z = 900 + rng.float(f32) * 100;
                stars[i].x = (rng.float(f32) - 0.5) * WW * 2.2;
                stars[i].y = (rng.float(f32) - 0.5) * WH * 2.2;
            }
        }
        // draw
        app.beginFrame(Color.rgb(6, 8, 18));
        // forward starfield — particles from ahead, perspective projection
        if (app.batchPtr()) |b| {
            for (stars) |s| {
                const fov: f32 = 420;
                const scale = fov / s.z;
                const sx = WW / 2 + s.x * scale;
                const sy = WH / 2 + s.y * scale;
                const sz = @max(1.2, 3.0 * scale);
                const alpha: u8 = @intFromFloat(std.math.clamp(255 * (1 - s.z / 1000) * 0.9 + 40, 40, 255));
                // streak when thrusting — longer
                const sw = if (thrusting) sz * 1.8 else sz;
                const sh = if (thrusting) sz * 0.7 else sz;
                b.drawRect(sx, sy, sw, sh, Color.rgba(200, 220, 255, alpha));
            }
        } else {
            for (stars) |s| app.win.drawRect(s.x, s.y, 1, 1, Color.rgba(255, 255, 255, 100));
        }
        // asteroids / enemies
        for (asteroids.items) |a| {
            const tex = if (a.kind == 1) enemy_tex else asteroid_tex;
            if (tex) |t| {
                if (app.batchPtr()) |b| {
                    // rotated quad — use drawQuad for 2D→3D pluggable
                    const cx = a.x + AST_S / 2; const cy = a.y + AST_S / 2;
                    const cos_a = @cos(a.angle); const sin_a = @sin(a.angle);
                    const hw: f32 = AST_S / 2; const hh: f32 = AST_S / 2;
                    const p0 = [_]f32{ cx + (-hw * cos_a - -hh * sin_a), cy + (-hw * sin_a + -hh * cos_a) };
                    const p1 = [_]f32{ cx + (hw * cos_a - -hh * sin_a), cy + (hw * sin_a + -hh * cos_a) };
                    const p2 = [_]f32{ cx + (hw * cos_a - hh * sin_a), cy + (hw * sin_a + hh * cos_a) };
                    const p3 = [_]f32{ cx + (-hw * cos_a - hh * sin_a), cy + (-hw * sin_a + hh * cos_a) };
                    // simple: drawTexture with rotation not yet, fallback to rect
                    // For high quality, use drawQuad with texture — but Batch currently draws quad with white tex, so use drawTexture for now
                    _ = p0; _ = p1; _ = p2; _ = p3;
                    b.drawTexture(t, a.x, a.y, AST_S, AST_S);
                }
            } else app.win.drawRect(a.x, a.y, AST_S, AST_S, if (a.kind == 1) Color.red else Color.rgb(140, 120, 110));
        }
        // lasers
        for (lasers.items) |l| {
            if (laser_tex) |t| {
                if (app.batchPtr()) |b| b.drawTexture(t, l.x, l.y, 8, 20);
            } else app.win.drawRect(l.x, l.y, 8, 20, Color.rgb(80, 255, 120));
        }
        // ship — with invuln blink
        if (lives > 0 and (@mod(invuln, 0.2) < 0.1 or invuln <= 0)) {
            if (ship_tex) |t| {
                if (app.batchPtr()) |b| {
                    // rotate ship — for now drawTexture (rotation via drawQuad would be next)
                    b.drawTexture(t, ship.x, ship.y, SHIP_S, SHIP_S);
                    if (thrusting) {
                        // flame
                        const fx = ship.x + SHIP_S / 2 + @cos(ship.angle) * -18 - 4;
                        const fy = ship.y + SHIP_S / 2 + @sin(ship.angle) * -18 - 6;
                        app.win.drawRect(fx, fy, 8, 12, Color.rgb(255, 120, 40));
                    }
                }
            } else {
                app.win.drawRect(ship.x, ship.y, SHIP_S, SHIP_S, Color.rgb(200, 220, 255));
            }
        }
        // particles
        for (particles.items) |p| {
            const a: u8 = @intFromFloat(255 * (p.life / p.max));
            app.win.drawRect(p.x, p.y, 3, 3, Color.rgba(p.col.r, p.col.g, p.col.b, a));
        }
        // explosions — sprite sheet 8 frames 32x32
        if (explosion_tex) |tex| {
            if (app.batchPtr()) |b| {
                for (explosions.items) |e| {
                    const frame: usize = @intFromFloat(@floor(e.t));
                    const f = @min(frame, 7);
                    const sx: f32 = @as(f32, @floatFromInt(f)) * 32;
                    b.drawTextureEx(tex, e.x, e.y, 32, 32, sx, 0, 32, 32, Color.white);

                }
            }
        }
        // score tilemap
        if (score_board) |sb| {
            if (app.batchPtr()) |b| sb.draw(b, score);
            for (0..lives) |i| {
                const lx: f32 = 12 + @as(f32, @floatFromInt(i)) * 20;
                app.win.drawRect(lx, 14, 14, 6, Color.white);
            }
        }
        if (lives == 0) {
            app.win.drawRect(WW / 2 - 100, WH / 2 - 24, 200, 48, Color.rgba(0, 0, 0, 160));
            app.win.drawRectOutline(WW / 2 - 100, WH / 2 - 24, 200, 48, Color.red);
        }

        app.endFrame();
        app.capFps(dt);
    }
}
