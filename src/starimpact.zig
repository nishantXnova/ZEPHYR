const std = @import("std");
const Zephyr = @import("Zephyr");
const App = Zephyr.App;
const Color = Zephyr.Color;
const Rect = Zephyr.Rect;
const Texture = Zephyr.Texture;
const win32 = Zephyr.win32;

const WW: f32 = 640;
const WH: f32 = 720; // vertical shooter
const SHIP_W: f32 = 48;
const SHIP_H: f32 = 48;
const SHIP_SPEED: f32 = 380;
const LASER_W: f32 = 6;
const LASER_H: f32 = 16;
const LASER_SPEED: f32 = 620;
const ENEMY_S: f32 = 32;
const METEOR_S: f32 = 64;
const BOSS_W: f32 = 128;
const BOSS_H: f32 = 96;

const Ship = struct { x: f32, y: f32, lives: u32 = 3, weapon: u32 = 1, shield: f32 = 0 };
const Laser = struct { x: f32, y: f32, vx: f32, vy: f32, dmg: u32 = 1, alive: bool = true };
const Enemy = struct { x: f32, y: f32, vx: f32, vy: f32, hp: u32, kind: u32, alive: bool = true, t: f32 = 0 };
const Meteor = struct { x: f32, y: f32, vy: f32, spin: f32, angle: f32 = 0, hp: u32 = 3, alive: bool = true };
const Boss = struct { x: f32, y: f32, hp: u32, max: u32, alive: bool = true, t: f32 = 0, dir: f32 = 1 };
const PowerUp = struct { x: f32, y: f32, vy: f32 = 50, kind: u32, alive: bool = true }; // 0 weapon,1 health,2 shield
const Particle = struct { x: f32, y: f32, vx: f32, vy: f32, life: f32, max: f32, col: Color };

pub fn main(init: std.process.Init) !void {
    _ = init;
    const allocator = std.heap.c_allocator;
    var prng = std.Random.DefaultPrng.init(0x1234ABCD);
    const rng = prng.random();

    var app = try App.init(.{ .title = "Zephyr Star Impact — Arrows move, SPACE fire, auto-scroll", .width = @intFromFloat(WW), .height = @intFromFloat(WH) });
    defer app.deinit();

    // Assets — Star Impact
    var ship_tex: ?*Texture = null; var ship_l: ?Texture = null;
    if (Texture.initFromFile("assets/si_ship.png", allocator) catch null) |t| { ship_l = t; ship_tex = &ship_l.?; }
    defer if (ship_l) |*t| t.deinit();
    var enemy_tex: [3]?*Texture = .{ null, null, null }; var enemy_l: [3]?Texture = .{ null, null, null };
    for (0..3) |i| {
        var buf: [32]u8 = undefined;
        const p = std.fmt.bufPrint(&buf, "assets/si_enemy{d}.png", .{i}) catch continue;
        if (Texture.initFromFile(p, allocator) catch null) |t| { enemy_l[i] = t; enemy_tex[i] = &enemy_l[i].?; }
    }
    defer for (0..3) |i| if (enemy_l[i]) |*t| t.deinit();
    var meteor_tex_l: ?Texture = null; var meteor_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/si_meteor.png", allocator) catch null) |t| { meteor_tex_l = t; meteor_tex = &meteor_tex_l.?; }
    defer if (meteor_tex_l) |*t| t.deinit();
    var boss_tex_l: ?Texture = null; var boss_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/si_boss.png", allocator) catch null) |t| { boss_tex_l = t; boss_tex = &boss_tex_l.?; }
    defer if (boss_tex_l) |*t| t.deinit();
    var laser_tex_l: ?Texture = null; var laser_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/si_laser.png", allocator) catch null) |t| { laser_tex_l = t; laser_tex = &laser_tex_l.?; }
    defer if (laser_tex_l) |*t| t.deinit();
    var elaser_tex_l: ?Texture = null; var elaser_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/si_elaser.png", allocator) catch null) |t| { elaser_tex_l = t; elaser_tex = &elaser_tex_l.?; }
    defer if (elaser_tex_l) |*t| t.deinit();
    var power_tex: [3]?*Texture = .{ null, null, null }; var power_l: [3]?Texture = .{ null, null, null };
    const power_names = [_][]const u8{ "assets/si_weapon.png", "assets/si_health.png", "assets/si_shield.png" };
    for (0..3) |i| if (Texture.initFromFile(power_names[i], allocator) catch null) |t| { power_l[i] = t; power_tex[i] = &power_l[i].?; };
    defer for (0..3) |i| if (power_l[i]) |*t| t.deinit();
    var bg_tex_l: ?Texture = null; var bg_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/si_bg.png", allocator) catch null) |t| { bg_tex_l = t; bg_tex = &bg_tex_l.?; }
    defer if (bg_tex_l) |*t| t.deinit();
    var explosion_tex_l: ?Texture = null; var explosion_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/explosion.png", allocator) catch null) |t| { explosion_tex_l = t; explosion_tex = &explosion_tex_l.?; }
    defer if (explosion_tex_l) |*t| t.deinit();
    var digits_tex_l: ?Texture = null; var digits_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/digits.png", allocator) catch null) |t| { digits_tex_l = t; digits_tex = &digits_tex_l.?; }
    defer if (digits_tex_l) |*t| t.deinit();
    const score_board = if (digits_tex) |t| Zephyr.ScoreBoard{ .tex = t, .x = WW - 110, .y = 10, .digits = 6 } else null;

    var audio = Zephyr.AudioEngine{ .engine = undefined };
    audio.init() catch {};
    defer audio.deinit();
    var laser_snd: ?Zephyr.Sound = if (audio.inited) audio.loadSound("assets/laser.wav", allocator) catch null else null;
    var explode_snd: ?Zephyr.Sound = if (audio.inited) audio.loadSound("assets/explode.wav", allocator) catch null else null;
    defer { if (laser_snd) |*s| audio.unload(s); if (explode_snd) |*s| audio.unload(s); }

    var ship = Ship{ .x = WW / 2 - SHIP_W / 2, .y = WH - 90 };
    var lasers: std.ArrayList(Laser) = .empty; defer lasers.deinit(allocator);
    var elasers: std.ArrayList(Laser) = .empty; defer elasers.deinit(allocator);
    var enemies: std.ArrayList(Enemy) = .empty; defer enemies.deinit(allocator);
    var meteors: std.ArrayList(Meteor) = .empty; defer meteors.deinit(allocator);
    var powerups: std.ArrayList(PowerUp) = .empty; defer powerups.deinit(allocator);
    var particles: std.ArrayList(Particle) = .empty; defer particles.deinit(allocator);
    var boss: ?Boss = null;
    var boss_bullets: u32 = 0;
    var score: u32 = 0;
    var stage: u32 = 1;
    var scroll: f32 = 0;
    var fleet_timer: f32 = 2.5;
    var meteor_timer: f32 = 4.0;
    var power_timer: f32 = 10;
    var fire_cooldown: f32 = 0;
    var shake: f32 = 0;
    var enemies_killed: u32 = 0;
    var last_title: f32 = 0;
    var last_score: u32 = 0;
    // pre-allocate to avoid realloc lag spikes after 10s
    try lasers.ensureTotalCapacity(allocator, 64);
    try elasers.ensureTotalCapacity(allocator, 32);
    try enemies.ensureTotalCapacity(allocator, 40);
    try meteors.ensureTotalCapacity(allocator, 16);
    try powerups.ensureTotalCapacity(allocator, 8);
    try particles.ensureTotalCapacity(allocator, 128);

    std.debug.print("Star Impact — Arrows/WASD move vertically & fire (SPACE), auto-scroll, fleets, meteors, boss\n", .{});

    while (!app.shouldClose()) {
        app.poll();
        if (app.win.isKeyDown(win32.VK_ESCAPE)) break;
        if (app.win.isKeyPressed('R')) {
            ship = .{ .x = WW / 2 - SHIP_W / 2, .y = WH - 90 }; score = 0; stage = 1; enemies_killed = 0; boss = null;
            lasers.clearRetainingCapacity(); elasers.clearRetainingCapacity(); enemies.clearRetainingCapacity(); meteors.clearRetainingCapacity(); powerups.clearRetainingCapacity(); particles.clearRetainingCapacity();
        }

        const dt = app.tick();
        const scroll_speed: f32 = 90 + @as(f32, @floatFromInt(stage)) * 12;
        scroll += scroll_speed * dt;
        if (scroll > 128) scroll -= 128;
        if (shake > 0) shake -= dt * 12;

        // Controls — simple keypad: move vertically and fire (plus horizontal for fun)
        var dx: f32 = 0; var dy: f32 = 0;
        if (app.win.isKeyDown(0x25) or app.win.isKeyDown('A')) dx -= 1; // LEFT
        if (app.win.isKeyDown(0x27) or app.win.isKeyDown('D')) dx += 1;
        if (app.win.isKeyDown(0x26) or app.win.isKeyDown('W')) dy -= 1;
        if (app.win.isKeyDown(0x28) or app.win.isKeyDown('S')) dy += 1;
        ship.x += dx * SHIP_SPEED * dt;
        ship.y += dy * SHIP_SPEED * dt;
        ship.x = std.math.clamp(ship.x, 8, WW - SHIP_W - 8);
        ship.y = std.math.clamp(ship.y, WH * 0.45, WH - SHIP_H - 12);
        if (ship.shield > 0) ship.shield -= dt;

        fire_cooldown -= dt;
        const firing = app.win.isKeyDown(win32.VK_SPACE);
        if (firing and fire_cooldown <= 0) {
            fire_cooldown = if (ship.weapon >= 3) 0.09 else if (ship.weapon == 2) 0.12 else 0.18;
            const cx = ship.x + SHIP_W / 2;
            const cy = ship.y;
            if (ship.weapon == 1) {
                lasers.append(allocator, .{ .x = cx - 3, .y = cy, .vx = 0, .vy = -LASER_SPEED }) catch {};
            } else if (ship.weapon == 2) {
                lasers.append(allocator, .{ .x = cx - 10, .y = cy + 6, .vx = -30, .vy = -LASER_SPEED }) catch {};
                lasers.append(allocator, .{ .x = cx + 4, .y = cy + 6, .vx = 30, .vy = -LASER_SPEED }) catch {};
            } else {
                lasers.append(allocator, .{ .x = cx - 3, .y = cy, .vx = 0, .vy = -LASER_SPEED }) catch {};
                lasers.append(allocator, .{ .x = cx - 12, .y = cy + 8, .vx = -80, .vy = -LASER_SPEED }) catch {};
                lasers.append(allocator, .{ .x = cx + 6, .y = cy + 8, .vx = 80, .vy = -LASER_SPEED }) catch {};
            }
            if (laser_snd) |*s| audio.play(s);
        }

        // Auto-scroll spawns — fleets
        fleet_timer -= dt;
        if (fleet_timer <= 0 and boss == null) {
            fleet_timer = 2.2 + rng.float(f32) * 1.2;
            const pattern = rng.intRangeAtMost(u32, 0, 2);
            if (pattern == 0) { // V fleet
                for (0..5) |i| {
                    const off: f32 = @as(f32, @floatFromInt(i)) * 1.0 - 2;
                    enemies.append(allocator, .{ .x = WW / 2 - ENEMY_S / 2 + off * 36, .y = -ENEMY_S - @as(f32, @floatFromInt(i)) * 18, .vx = off * 10, .vy = 90 + @as(f32, @floatFromInt(stage)) * 8, .hp = 1, .kind = @intCast(i % 3) }) catch {};
                }
            } else if (pattern == 1) { // line
                for (0..7) |i| enemies.append(allocator, .{ .x = 40 + @as(f32, @floatFromInt(i)) * 70, .y = -ENEMY_S - 10, .vx = 0, .vy = 100, .hp = 1, .kind = @intCast(i % 3) }) catch {};
            } else { // diamond meteor shower
                for (0..4) |i| meteors.append(allocator, .{ .x = rng.float(f32) * (WW - METEOR_S), .y = -METEOR_S - @as(f32, @floatFromInt(i)) * 40, .vy = 120 + rng.float(f32) * 40, .spin = (rng.float(f32) - 0.5) * 3, .hp = 2 }) catch {};
                fleet_timer = 0.6;
            }
        }
        meteor_timer -= dt;
        if (meteor_timer <= 0 and boss == null) {
            meteor_timer = 3.5 + rng.float(f32) * 2;
            meteors.append(allocator, .{ .x = rng.float(f32) * (WW - METEOR_S), .y = -METEOR_S, .vy = 140, .spin = (rng.float(f32) - 0.5) * 2, .hp = 3 }) catch {};
        }
        power_timer -= dt;
        if (power_timer <= 0) {
            power_timer = 12 + rng.float(f32) * 6;
            powerups.append(allocator, .{ .x = rng.float(f32) * (WW - 20), .y = -20, .kind = rng.intRangeAtMost(u32, 0, 2) }) catch {};
        }

        // boss at end of stage
        if (enemies_killed >= 20 + stage * 8 and boss == null and meteors.items.len == 0) {
            boss = .{ .x = WW / 2 - BOSS_W / 2, .y = -BOSS_H, .hp = 80 + stage * 30, .max = 80 + stage * 30 };
        }
        if (particles.items.len > 90) {
            // cap particles to keep 60fps stable
            if (particles.items.len > 120) _ = particles.swapRemove(0);
        }
        if (boss) |*b| {
            b.t += dt;
            // descend then sway
            if (b.y < 50) b.y += 40 * dt else {
                b.x += @sin(b.t * 0.9) * 60 * dt * b.dir;
                if (b.x < 10) b.dir = 1; if (b.x > WW - BOSS_W - 10) b.dir = -1;
                // shoot
                boss_bullets += 1;
                if (boss_bullets % 18 == 0) {
                    for (0..3) |i| {
                        const bx = b.x + 20 + @as(f32, @floatFromInt(i)) * 44;
                        elasers.append(allocator, .{ .x = bx, .y = b.y + BOSS_H - 10, .vx = (rng.float(f32) - 0.5) * 80, .vy = 220 }) catch {};
                    }
                }
            }
            if (b.hp == 0) {
                // explode boss
                for (0..24) |_| {
                    const ang = rng.float(f32) * 6.28;
                    particles.append(allocator, .{ .x = b.x + BOSS_W / 2, .y = b.y + BOSS_H / 2, .vx = @cos(ang) * (rng.float(f32) * 200 + 60), .vy = @sin(ang) * (rng.float(f32) * 200 + 60), .life = 0.6, .max = 0.6, .col = Color.rgb(255, 100, 40) }) catch {};
                }
                shake = 1.2;
                score += 500 * stage;
                stage += 1;
                enemies_killed = 0;
                boss = null;
                if (explode_snd) |*s| audio.play(s);
            }
        }

        // update lasers
        for (lasers.items) |*l| { l.x += l.vx * dt; l.y += l.vy * dt; if (l.y < -20) l.alive = false; }
        for (elasers.items) |*l| { l.x += l.vx * dt; l.y += l.vy * dt; if (l.y > WH + 20) l.alive = false; }
        for (enemies.items) |*e| { e.x += e.vx * dt; e.y += e.vy * dt; e.t += dt; if (e.y > WH + 40) e.alive = false; }
        for (meteors.items) |*m| { m.y += m.vy * dt; m.angle += m.spin * dt; if (m.y > WH + 40) m.alive = false; }
        for (powerups.items) |*p| { p.y += p.vy * dt; if (p.y > WH + 20) p.alive = false; }
        for (particles.items) |*p| { p.x += p.vx * dt; p.y += p.vy * dt; p.vx *= 0.99; p.vy *= 0.99; p.life -= dt; }

        // collisions
        const ship_rect = Rect.init(ship.x + 6, ship.y + 6, SHIP_W - 12, SHIP_H - 12);
        for (lasers.items) |*l| { if (l.alive) {
            const lr = Rect.init(l.x, l.y, LASER_W, LASER_H);
            for (enemies.items) |*e| { if (e.alive) {
                const er = Rect.init(e.x, e.y, ENEMY_S, ENEMY_S);
                if (lr.overlaps(er)) { l.alive = false; e.hp -= l.dmg; if (e.hp == 0) { e.alive = false; enemies_killed += 1; score += 20; for (0..8) |_| particles.append(allocator, .{ .x = e.x + ENEMY_S/2, .y = e.y + ENEMY_S/2, .vx = (rng.float(f32)-0.5)*120, .vy = (rng.float(f32)-0.5)*120, .life = 0.35, .max = 0.35, .col = Color.rgb(255,180,80)}) catch {}; if (explode_snd) |*s| audio.play(s); if (rng.float(f32) < 0.12) powerups.append(allocator, .{ .x = e.x, .y = e.y, .kind = rng.intRangeAtMost(u32,0,2)}) catch {}; } break; }
            } }
            for (meteors.items) |*m| { if (m.alive) {
                const mr = Rect.init(m.x + 8, m.y + 8, METEOR_S - 16, METEOR_S - 16);
                if (lr.overlaps(mr)) { l.alive = false; m.hp -= 1; shake = 0.2; if (m.hp == 0) { m.alive = false; score += 15; for (0..10) |_| particles.append(allocator, .{ .x = m.x+32, .y = m.y+32, .vx = (rng.float(f32)-0.5)*140, .vy = (rng.float(f32)-0.5)*140, .life = 0.4, .max = 0.4, .col = Color.rgb(180,160,140)}) catch {}; if (explode_snd) |*s| audio.play(s); } break; }
            } }
            if (boss) |*b| {
                const br = Rect.init(b.x, b.y, BOSS_W, BOSS_H);
                if (lr.overlaps(br)) { l.alive = false; if (b.hp > 0) b.hp -= 1; shake = 0.15; for (0..3) |_| particles.append(allocator, .{ .x = l.x, .y = l.y, .vx = (rng.float(f32)-0.5)*100, .vy = (rng.float(f32)-0.5)*100, .life = 0.25, .max = 0.25, .col = Color.rgb(255,220,120)}) catch {}; }
            }
        } }
        for (elasers.items) |*l| { if (l.alive) {
            const lr = Rect.init(l.x, l.y, LASER_W, LASER_H);
            if (lr.overlaps(ship_rect) and ship.shield <= 0) { l.alive = false; if (ship.lives > 0) ship.lives -= 1; ship.shield = 1.0; shake = 0.5; for (0..12) |_| particles.append(allocator, .{ .x = ship.x+SHIP_W/2, .y = ship.y+SHIP_H/2, .vx = (rng.float(f32)-0.5)*160, .vy = (rng.float(f32)-0.5)*160, .life = 0.4, .max = 0.4, .col = Color.rgb(100,180,255)}) catch {}; if (ship.lives == 0) {} }
        } }
        for (enemies.items) |*e| { if (e.alive) {
            const er = Rect.init(e.x, e.y, ENEMY_S, ENEMY_S);
            if (er.overlaps(ship_rect) and ship.shield <= 0) { e.alive = false; if (ship.lives > 0) ship.lives -= 1; ship.shield = 1.0; shake = 0.5; }
        } }
        for (meteors.items) |*m| { if (m.alive) {
            const mr = Rect.init(m.x+8, m.y+8, METEOR_S-16, METEOR_S-16);
            if (mr.overlaps(ship_rect) and ship.shield <= 0) { m.alive = false; if (ship.lives > 0) ship.lives -= 1; ship.shield = 1.0; shake = 0.6; }
        }
        for (powerups.items) |*p| { if (p.alive) {
            const pr = Rect.init(p.x, p.y, 20, 20);
            if (pr.overlaps(ship_rect)) {
                p.alive = false;
                if (p.kind == 0) ship.weapon = @min(3, ship.weapon + 1) else if (p.kind == 1) ship.lives = @min(5, ship.lives + 1) else ship.shield = 3.0;
                score += 25;
            } }
        }

        // cull
        { var i: usize = 0; while (i < lasers.items.len) { if (!lasers.items[i].alive) _ = lasers.swapRemove(i) else i += 1; } }
        { var i: usize = 0; while (i < elasers.items.len) { if (!elasers.items[i].alive) _ = elasers.swapRemove(i) else i += 1; } }
        { var i: usize = 0; while (i < enemies.items.len) { if (!enemies.items[i].alive) _ = enemies.swapRemove(i) else i += 1; } }
        { var i: usize = 0; while (i < meteors.items.len) { if (!meteors.items[i].alive) _ = meteors.swapRemove(i) else i += 1; } }
        { var i: usize = 0; while (i < powerups.items.len) { if (!powerups.items[i].alive) _ = powerups.swapRemove(i) else i += 1; } }
        { var i: usize = 0; while (i < particles.items.len) { if (particles.items[i].life <= 0) _ = particles.swapRemove(i) else i += 1; } }

        // title — throttled (was 60 allocs/sec causing lag after 10s)
        if (score != last_score or app.clock.total - last_title > 0.4) {
            var tbuf: [128]u8 = undefined;
            const fps: u32 = if (dt > 0) @as(u32, @intFromFloat(1.0 / dt)) else 60;
            const t = std.fmt.bufPrint(&tbuf, "Star Impact Stage {d} Score {d} Lives {d} Wpn {d} FPS {d}", .{ stage, score, ship.lives, ship.weapon, fps }) catch "Star Impact";
            app.win.setTitle(t);
            last_score = score;
            last_title = app.clock.total;
        }

        // draw — auto forward-scrolling
        const shake_x: f32 = if (shake > 0) (rng.float(f32) - 0.5) * shake * 12 else 0;
        const shake_y: f32 = if (shake > 0) (rng.float(f32) - 0.5) * shake * 12 else 0;
        // camera is just scroll, but we fake with bg offset
        app.cam.pos.x = shake_x;
        app.cam.pos.y = shake_y;
        app.win.setBatchProjection(app.cam.combined());
        app.beginFrame(Color.rgb(6, 8, 18));
        // bg scrolling
        if (bg_tex) |tex| {
            if (app.batchPtr()) |b| {
                var y: f32 = -scroll;
                while (y < WH) : (y += 128) {
                    var x: f32 = - (@mod(scroll * 0.3, 128));
                    while (x < WW) : (x += 128) b.drawTexture(tex, x, y, 128, 128);
                }
            }
        } else app.win.drawRect(0,0,WW,WH,Color.rgb(6,8,18));
        // meteors
        for (meteors.items) |mm| {
            if (meteor_tex) |t| { if (app.batchPtr()) |b| b.drawTexture(t, mm.x, mm.y, METEOR_S, METEOR_S); } else app.win.drawRect(mm.x,mm.y,METEOR_S,METEOR_S,Color.rgb(120,100,90));
        }
        // enemies
        for (enemies.items) |ee| {
            const tex = enemy_tex[ee.kind % 3];
            if (tex) |t| { if (app.batchPtr()) |b| b.drawTexture(t, ee.x, ee.y, ENEMY_S, ENEMY_S); } else app.win.drawRect(ee.x,ee.y,ENEMY_S,ENEMY_S,Color.red);
        }
        // boss
        if (boss) |b| {
            if (boss_tex) |t| { if (app.batchPtr()) |bb| bb.drawTexture(t, b.x, b.y, BOSS_W, BOSS_H); } else app.win.drawRect(b.x,b.y,BOSS_W,BOSS_H,Color.rgb(180,30,30));
            // hp bar
            const w: f32 = 120 * (@as(f32, @floatFromInt(b.hp)) / @as(f32, @floatFromInt(b.max)));
            app.win.drawRect(WW/2 - 60, 28, 120, 8, Color.rgba(0,0,0,120));
            app.win.drawRect(WW/2 - 60, 28, w, 8, Color.red);
        }
        // power-ups
        for (powerups.items) |pp| {
            const tex = power_tex[pp.kind % 3];
            if (tex) |t| { if (app.batchPtr()) |b| b.drawTexture(t, pp.x, pp.y, 20, 20); } else app.win.drawRect(pp.x,pp.y,20,20,Color.white);
        }
        // lasers
        for (lasers.items) |ll| { if (laser_tex) |t| { if (app.batchPtr()) |b| b.drawTexture(t, ll.x, ll.y, LASER_W, LASER_H); } else app.win.drawRect(ll.x,ll.y,LASER_W,LASER_H,Color.green); }
        for (elasers.items) |el| { if (elaser_tex) |t| { if (app.batchPtr()) |b| b.drawTexture(t, el.x, el.y, LASER_W, LASER_H); } else app.win.drawRect(el.x,el.y,LASER_W,LASER_H,Color.red); }
        // ship
        if (ship.lives > 0 and (@mod(ship.shield, 0.2) < 0.1 or ship.shield <= 0)) {
            if (ship_tex) |t| { if (app.batchPtr()) |b| b.drawTexture(t, ship.x, ship.y, SHIP_W, SHIP_H); } else app.win.drawRect(ship.x,ship.y,SHIP_W,SHIP_H,Color.white);
            if (ship.shield > 0) app.win.drawRectOutline(ship.x - 4, ship.y - 4, SHIP_W + 8, SHIP_H + 8, Color.rgb(100,160,255));
        }
        // particles / explosions
        for (particles.items) |ppart| {
            const a: u8 = @intFromFloat(255 * (ppart.life / ppart.max));
            app.win.drawRect(ppart.x, ppart.y, 3, 3, Color.rgba(ppart.col.r, ppart.col.g, ppart.col.b, a));
        }
        // score tilemap
        if (score_board) |sb| { if (app.batchPtr()) |b| sb.draw(b, score); }
        for (0..ship.lives) |i| app.win.drawRect(12 + @as(f32, @floatFromInt(i))*18, 12, 12, 6, Color.white);
        if (ship.lives == 0) {
            app.win.drawRect(WW/2 - 100, WH/2 - 24, 200, 48, Color.rgba(0,0,0,160));
            app.win.drawRectOutline(WW/2 - 100, WH/2 - 24, 200, 48, Color.red);
        }

        app.endFrame();
        app.capFps(dt);
    }
    }
}
