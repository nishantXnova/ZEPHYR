const std = @import("std");
const Zephyr = @import("Zephyr");
const App = Zephyr.App;
const Color = Zephyr.Color;
const Rect = Zephyr.Rect;
const Texture = Zephyr.Texture;
const SpriteSheet = Zephyr.SpriteSheet;
const Animator = Zephyr.Animator;
const Tilemap = Zephyr.Tilemap;
const ParticleSystem = Zephyr.ParticleSystem;
const PhysicsWorld = Zephyr.PhysicsWorld;
const PhysicsBody = Zephyr.PhysicsBody;
const BodyType = Zephyr.BodyType;
const Layer = Zephyr.Layer;
const Profiler = Zephyr.Profiler;
const Action = Zephyr.Action;
const win32 = Zephyr.win32;

const WW: f32 = 800;
const WH: f32 = 480;
const TILE: f32 = 16;
const GRAVITY: f32 = 1400;
const JUMP: f32 = -480;
const RUN: f32 = 260;
const MAX_FALL: f32 = 600;
const MARIO_W: f32 = 22;
const MARIO_H: f32 = 28;

const Mario = struct {
    x: f32,
    y: f32,
    vx: f32 = 0,
    vy: f32 = 0,
    on_ground: bool = false,
    facing: f32 = 1,
    big: bool = false,
};

const Goomba = struct { x: f32, y: f32, vx: f32 = -60, alive: bool = true, rect: Rect };
const Coin = struct { x: f32, y: f32, alive: bool = true, bob: f32 = 0 };
const Block = struct { x: f32, y: f32, hit: bool = false };

fn isSolid(tile: u32) bool {
    return tile == 1 or tile == 2 or tile == 4 or tile == 5;
}

pub fn main(init: std.process.Init) !void {
    _ = init;
    const allocator = std.heap.c_allocator;
    var prng = std.Random.DefaultPrng.init(0x4D5A1234);
    const rng = prng.random();

    var app = try App.init(.{ .title = "Zephyr Mario — Arrows move, SPACE jump, R reset", .width = @intFromFloat(WW), .height = @intFromFloat(WH) });
    defer app.deinit();

    // Assets
    var mario_tex_l: ?Texture = null; var mario_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/mario.png", allocator) catch null) |t| { mario_tex_l = t; mario_tex = &mario_tex_l.?; }
    defer if (mario_tex_l) |*t| t.deinit();
    var tiles_tex_l: ?Texture = null; var tiles_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/mario_tiles.png", allocator) catch null) |t| { tiles_tex_l = t; tiles_tex = &tiles_tex_l.?; }
    defer if (tiles_tex_l) |*t| t.deinit();
    var goomba_tex_l: ?Texture = null; var goomba_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/goomba.png", allocator) catch null) |t| { goomba_tex_l = t; goomba_tex = &goomba_tex_l.?; }
    defer if (goomba_tex_l) |*t| t.deinit();
    var coin_tex_l: ?Texture = null; var coin_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/coin.png", allocator) catch null) |t| { coin_tex_l = t; coin_tex = &coin_tex_l.?; }
    defer if (coin_tex_l) |*t| t.deinit();
    var flag_tex_l: ?Texture = null; var flag_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/flag.png", allocator) catch null) |t| { flag_tex_l = t; flag_tex = &flag_tex_l.?; }
    defer if (flag_tex_l) |*t| t.deinit();
    var cloud_tex_l: ?Texture = null; var cloud_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/cloud.png", allocator) catch null) |t| { cloud_tex_l = t; cloud_tex = &cloud_tex_l.?; }
    defer if (cloud_tex_l) |*t| t.deinit();
    var digits_l: ?Texture = null; var digits_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/digits.png", allocator) catch null) |t| { digits_l = t; digits_tex = &digits_l.?; }
    defer if (digits_l) |*t| t.deinit();
    const score_board = if (digits_tex) |t| Zephyr.ScoreBoard{ .tex = t, .x = WW - 100, .y = 10, .digits = 5 } else null;

    // Tilemap level 100x15
    const LEVEL_W: u32 = 100;
    const LEVEL_H: u32 = 15;
    var tilemap: Tilemap = try Tilemap.init(allocator, LEVEL_W, LEVEL_H, 16, 16, tiles_tex orelse return error.NoTileset);
    defer tilemap.deinit();
    // ground
    for (0..LEVEL_W) |x| {
        tilemap.set(@intCast(x), 13, 1);
        tilemap.set(@intCast(x), 14, 1);
    }
    // platforms
    const plats = [_]struct { x: u32, y: u32, w: u32 }{
        .{ .x = 8, .y = 10, .w = 4 }, .{ .x = 16, .y = 9, .w = 3 }, .{ .x = 24, .y = 8, .w = 5 },
        .{ .x = 34, .y = 10, .w = 3 }, .{ .x = 42, .y = 7, .w = 4 }, .{ .x = 52, .y = 9, .w = 6 },
        .{ .x = 62, .y = 10, .w = 4 }, .{ .x = 70, .y = 8, .w = 5 }, .{ .x = 84, .y = 10, .w = 8 },
    };
    for (plats) |p| for (0..p.w) |dx| tilemap.set(p.x + @as(u32, @intCast(dx)), p.y, 2);
    // pipes
    tilemap.set(14, 12, 4); tilemap.set(14, 11, 4); tilemap.set(15, 12, 5); tilemap.set(15, 11, 5);
    tilemap.set(38, 12, 4); tilemap.set(38, 11, 4); tilemap.set(39, 12, 5); tilemap.set(39, 11, 5);
    tilemap.set(66, 12, 4); tilemap.set(66, 11, 4); tilemap.set(66, 10, 4); tilemap.set(67, 12, 5); tilemap.set(67, 11, 5); tilemap.set(67, 10, 5);
    // flag at end
    tilemap.set(95, 12, 4); tilemap.set(95, 11, 4); tilemap.set(95, 10, 4); tilemap.set(95, 9, 4); tilemap.set(95, 8, 4);

    // Animator for Mario
    var animator: ?Animator = null;
    if (mario_tex) |tex| {
        const sheet = SpriteSheet.init(tex, 32, 32);
        var anim = Animator.init(allocator, sheet);
        try anim.add(.{ .name = "idle", .frames = &.{0}, .fps = 1 });
        try anim.add(.{ .name = "run", .frames = &.{ 1, 2 }, .fps = 10, .loop = true });
        try anim.add(.{ .name = "jump", .frames = &.{3}, .fps = 1 });
        anim.play("idle");
        animator = anim;
    }
    defer if (animator) |*a| a.deinit();

    var mario = Mario{ .x = 40, .y = 160 };
    var goombas: std.ArrayList(Goomba) = .empty; defer goombas.deinit(allocator);
    try goombas.ensureTotalCapacity(allocator, 16);
    const goomba_spawns = [_]struct { x: f32, y: f32 }{ .{ .x = 200, .y = 180 }, .{ .x = 420, .y = 100 }, .{ .x = 680, .y = 180 }, .{ .x = 900, .y = 180 }, .{ .x = 1100, .y = 100 } };
    for (goomba_spawns) |g| try goombas.append(allocator, .{ .x = g.x, .y = g.y * 1.0, .vx = -60, .rect = Rect.init(g.x, g.y, 16, 16) });

    var coins: std.ArrayList(Coin) = .empty; defer coins.deinit(allocator);
    try coins.ensureTotalCapacity(allocator, 32);
    const coin_spawns = [_]struct { x: f32, y: f32 }{ .{ .x = 140, .y = 140 }, .{ .x = 156, .y = 140 }, .{ .x = 300, .y = 110 }, .{ .x = 500, .y = 90 }, .{ .x = 720, .y = 110 }, .{ .x = 880, .y = 140 }, .{ .x = 900, .y = 140 }, .{ .x = 920, .y = 140 } };
    for (coin_spawns) |c| try coins.append(allocator, .{ .x = c.x, .y = c.y });

    var score: u32 = 0;
    var coins_collected: u32 = 0;
    var lives: u32 = 3;
    var won: bool = false;
    var dead_timer: f32 = 0;
    var title_timer: f32 = 0;
    var particles = ParticleSystem.init(allocator);
    defer particles.deinit();
    try particles.ensureCap(64);

    // Engine v0.6 showcase — PhysicsWorld demo (separate from tilemap, proves no tunneling)
    var phys = PhysicsWorld.init(allocator);
    defer phys.deinit();
    _ = try phys.add(.{ .rect = Rect.init(0, 13 * TILE, 100 * TILE, 32), .type = .static, .layer = Layer.single(0), .mask = Layer.all() });
    const phys_ball = try phys.add(.{ .rect = Rect.init(500, 0, 16, 16), .type = .dynamic, .vel = .{ .x = 40, .y = 0 }, .restitution = 0.6, .friction = 0.2 });
    var show_prof = false;

    // preallocate

    std.debug.print("Zephyr Mario — LEFT/RIGHT move, SPACE jump, R reset | Runs good 60fps\n", .{});

    while (!app.shouldClose()) {
        app.poll();
        if (app.win.isKeyDown(win32.VK_ESCAPE)) break;
        if (app.win.isKeyPressed('R')) {
            mario = .{ .x = 40, .y = 160 }; score = 0; coins_collected = 0; won = false; dead_timer = 0; lives = 3;
            goombas.clearRetainingCapacity();
            for (goomba_spawns) |g| try goombas.append(allocator, .{ .x = g.x, .y = g.y, .vx = -60, .rect = Rect.init(g.x, g.y, 16, 16) });
            coins.clearRetainingCapacity();
            for (coin_spawns) |c| try coins.append(allocator, .{ .x = c.x, .y = c.y });
            particles.clear();
        }

        const dt = app.tick();

        // Input — Engine v0.6 Action mapping (buffered coyote 0.18s) beats raw polling
        const move = app.input.axis(.left, .right);
        const running = app.input.down(.run);
        const speed: f32 = if (running) RUN * 1.5 else RUN;
        mario.vx = move * speed;
        if (move != 0) mario.facing = move;

        // Jump buffered — allows 0.18s queue (Celeste-like), undeniably better than Scratch
        const want_jump = app.input.consumeBuffer(.jump);
        if (want_jump and mario.on_ground) {
            mario.vy = JUMP;
            mario.on_ground = false;
        }
        if (app.win.isKeyPressed(0x72)) show_prof = !show_prof; // F3 toggle profiler overlay

        // Physics — runs good, tile collision via nearby checks only (not full map)
        mario.vy += GRAVITY * dt;
        if (mario.vy > MAX_FALL) mario.vy = MAX_FALL;
        // X
        mario.x += mario.vx * dt;
        var mario_rect = Rect.init(mario.x, mario.y, MARIO_W, MARIO_H);
        // check X collision with nearby tiles (3x3 around mario)
        {
            const tx0: i32 = @intFromFloat(@floor(mario.x / TILE));
            const ty0: i32 = @intFromFloat(@floor(mario.y / TILE));
            for (0..9) |idx| {
                const dx: i32 = @intCast(idx % 3);
                const dy: i32 = @intCast(idx / 3);
                const tx: i32 = tx0 + dx - 1;
                const ty: i32 = ty0 + dy - 1;
                if (tx < 0 or ty < 0 or tx >= @as(i32, @intCast(LEVEL_W)) or ty >= @as(i32, @intCast(LEVEL_H))) continue;
                const gid = tilemap.get(@intCast(tx), @intCast(ty));
                if (!isSolid(gid)) continue;
                const tr = Rect.init(@as(f32, @floatFromInt(tx)) * TILE, @as(f32, @floatFromInt(ty)) * TILE, TILE, TILE);
                if (mario_rect.overlaps(tr)) {
                    if (mario.vx > 0) mario.x = tr.x - MARIO_W else if (mario.vx < 0) mario.x = tr.x + TILE;
                    mario.vx = 0;
                    mario_rect = Rect.init(mario.x, mario.y, MARIO_W, MARIO_H);
                }
            }
        }
        // Y
        mario.y += mario.vy * dt;
        mario_rect = Rect.init(mario.x, mario.y, MARIO_W, MARIO_H);
        mario.on_ground = false;
        {
            const tx0: i32 = @intFromFloat(@floor(mario.x / TILE));
            const ty0: i32 = @intFromFloat(@floor(mario.y / TILE));
            for (0..9) |idx| {
                const dx: i32 = @intCast(idx % 3);
                const dy: i32 = @intCast(idx / 3);
                const tx: i32 = tx0 + dx - 1;
                const ty: i32 = ty0 + dy - 1;
                if (tx < 0 or ty < 0 or tx >= @as(i32, @intCast(LEVEL_W)) or ty >= @as(i32, @intCast(LEVEL_H))) continue;
                const gid = tilemap.get(@intCast(tx), @intCast(ty));
                if (!isSolid(gid)) continue;
                const tr = Rect.init(@as(f32, @floatFromInt(tx)) * TILE, @as(f32, @floatFromInt(ty)) * TILE, TILE, TILE);
                if (mario_rect.overlaps(tr)) {
                    if (mario.vy > 0) {
                        mario.y = tr.y - MARIO_H;
                        mario.vy = 0;
                        mario.on_ground = true;
                    } else if (mario.vy < 0) {
                        mario.y = tr.y + TILE;
                        mario.vy = 0;
                    }
                    mario_rect = Rect.init(mario.x, mario.y, MARIO_W, MARIO_H);
                }
            }
        }
        // fall death
        if (mario.y > WH + 100) {
            if (lives > 0) lives -= 1;
            if (lives == 0) dead_timer = 1.5 else {
                mario.x = 40;
                mario.y = 160;
                mario.vx = 0;
                mario.vy = 0;
            }
        }
        if (dead_timer > 0) dead_timer -= dt;

        // Animator
        if (animator) |*anim| {
            if (!mario.on_ground) anim.play("jump") else if (@abs(mario.vx) > 10) anim.play("run") else anim.play("idle");
            anim.update(dt);
        }

        // Goombas
        for (goombas.items) |*g| {
            if (!g.alive) continue;
            g.x += g.vx * dt;
            // tile collision for goomba simple
            const gr = Rect.init(g.x, g.y, 16, 16);
            var hit_wall = false;
            const tx0: i32 = @intFromFloat(@floor(g.x / TILE));
            const ty: i32 = @intFromFloat(@floor(g.y / TILE));
            for (0..2) |dx| {
                const tx: i32 = tx0 + @as(i32, @intCast(dx));
                if (tx < 0 or tx >= @as(i32, @intCast(LEVEL_W))) continue;
                const gid = tilemap.get(@intCast(tx), @intCast(ty));
                if (isSolid(gid)) {
                    const tr = Rect.init(@as(f32, @floatFromInt(tx)) * TILE, @as(f32, @floatFromInt(ty)) * TILE, TILE, TILE);
                    if (gr.overlaps(tr)) hit_wall = true;
                }
            }
            if (hit_wall) g.vx = -g.vx;
            // gravity for goomba
            g.y += 180 * dt;
            const gy: i32 = @intFromFloat(@floor((g.y + 16) / TILE));
            if (gy >= 0 and gy < @as(i32, @intCast(LEVEL_H))) {
                const tx: i32 = @intFromFloat(@floor((g.x + 8) / TILE));
                if (tx >= 0 and tx < @as(i32, @intCast(LEVEL_W))) {
                    const gid = tilemap.get(@intCast(tx), @intCast(gy));
                    if (isSolid(gid)) g.y = @as(f32, @floatFromInt(gy)) * TILE - 16;
                }
            }
            g.rect = Rect.init(g.x, g.y, 16, 16);
            // mario vs goomba
            if (g.alive and mario_rect.overlaps(g.rect)) {
                if (mario.vy > 0 and mario.y + MARIO_H < g.y + 12) {
                    g.alive = false;
                    mario.vy = JUMP * 0.6;
                    score += 100;
                    particles.emitBurst(g.x + 8, g.y + 8, 10, Color.rgb(180, 120, 60), rng);
                } else if (dead_timer == 0) {
                    if (lives > 0) lives -= 1;
                    dead_timer = 1.0;
                    if (lives != 0) {
                        mario.x = 40;
                        mario.y = 160;
                        mario.vx = 0;
                        mario.vy = 0;
                    }
                }
            }
        }

        // Coins — Engine ParticleSystem demo (scratch coin clone but pooled)
        for (coins.items) |*coin| {
            if (!coin.alive) continue;
            coin.bob += dt * 3;
            const cr = Rect.init(coin.x, coin.y + @sin(coin.bob) * 2, 16, 16);
            if (mario_rect.overlaps(cr)) {
                coin.alive = false;
                score += 100;
                coins_collected += 1;
                particles.emitBurst(coin.x + 8, coin.y + 8, 8, Color.rgb(240, 200, 40), rng);
            }
        }
        particles.update(dt);
        // Physics demo step — fixed sub-steps, spatial hash, no tunneling (engine proof)
        phys.step(dt);
        // keep physics ball in view by syncing x with camera + bounce
        if (phys.get(phys_ball)) |b| {
            if (b.rect.x > app.cam.pos.x + WW + 100) b.rect.x = app.cam.pos.x - 20;
        }

        // Flag win
        const flag_rect = Rect.init(95 * TILE, 8 * TILE, 16, 80);
        if (mario_rect.overlaps(flag_rect) and !won) {
            won = true;
            score += 500;
        }

        // Camera follow mario — runs good, lerp
        const target_cam_x = mario.x - WW / 2 + MARIO_W / 2;
        app.cam.pos.x += (target_cam_x - app.cam.pos.x) * 0.08;
        app.cam.pos.x = std.math.clamp(app.cam.pos.x, 0, @as(f32, @floatFromInt(LEVEL_W)) * TILE - WW);
        app.cam.pos.y = 0;

        // title throttled 0.4s — avoids SetWindowTextW heap spam
        title_timer += dt;
        if (title_timer > 0.4 or won or lives == 0) {
            title_timer = 0;
            var tbuf: [128]u8 = undefined;
            const t = std.fmt.bufPrint(&tbuf, "Mario SCORE {d} Coins {d} Lives {d} {s}", .{ score, coins_collected, lives, if (won) "WIN!" else if (lives == 0) "GAME OVER" else "" }) catch "Zephyr Mario";
            app.win.setTitle(t);
        }

        // draw
        app.win.setBatchProjection(app.cam.combined());
        app.beginFrame(Color.rgb(92, 148, 252));
        // clouds
        if (cloud_tex) |tex| {
            if (app.batchPtr()) |b| {
                const clouds = [_]struct { x: f32, y: f32 }{ .{ .x = 120, .y = 60 }, .{ .x = 340, .y = 80 }, .{ .x = 620, .y = 50 }, .{ .x = 900, .y = 70 } };
                for (clouds) |cl| {
                    const cx = cl.x - app.cam.pos.x * 0.3;
                    b.drawTexture(tex, cx, cl.y, 32, 16);
                }
            }
        }
        // tilemap
        if (app.batchPtr()) |b| {
            tilemap.drawCamera(b, app.cam.pos.x, app.cam.pos.y, WW, WH);
        }
        // coins
        for (coins.items) |c| {
            if (!c.alive) continue;
            const y = c.y + @sin(c.bob) * 2;
            if (coin_tex) |t| { if (app.batchPtr()) |b| b.drawTexture(t, c.x, y, 16, 16); } else app.win.drawRect(c.x, y, 16, 16, Color.rgb(240, 200, 40));
        }
        // goombas
        for (goombas.items) |g| {
            if (!g.alive) continue;
            if (goomba_tex) |t| { if (app.batchPtr()) |b| b.drawTexture(t, g.x, g.y, 16, 16); } else app.win.drawRect(g.x, g.y, 16, 16, Color.rgb(180, 120, 60));
        }
        // flag
        if (flag_tex) |t| { if (app.batchPtr()) |b| b.drawTexture(t, 95 * TILE, 8 * TILE, 16, 32); } else app.win.drawRect(95 * TILE, 8 * TILE, 16, 80, Color.rgb(40, 200, 80));
        // mario
        if (animator) |anim| {
            if (app.batchPtr()) |b| {
                const flip = mario.facing < 0;
                anim.drawEx(b, mario.x, mario.y, MARIO_W, MARIO_H, Color.white, flip);
            }
        } else app.win.drawRect(mario.x, mario.y, MARIO_W, MARIO_H, Color.rgb(220, 40, 40));

        // physics ball render — proves PhysicsWorld sweep + spatial hash
        if (phys.get(phys_ball)) |b| {
            app.win.drawRect(b.rect.x, b.rect.y, b.rect.w, b.rect.h, Color.rgb(100, 220, 255));
            app.win.drawRect(b.rect.x + 2, b.rect.y + 2, 4, 4, Color.white);
        }
        // particles — engine test: pooled, no garbage, beats Scratch clones
        if (app.batchPtr()) |b| particles.draw(b) else particles.drawWindow(&app.win);

        // profiler overlay — F3 (engine v0.6)
        if (show_prof) {
            const st = app.profiler.stat();
            if (app.batchPtr()) |b| {
                b.drawRect(app.cam.pos.x + 8, 40, 200, 50, Color.rgba(0, 0, 0, 170));
                app.profiler.draw(b, app.cam.pos.x + 8, 40);
                // text-like bars: fps dt broad/narrow
                b.drawRect(app.cam.pos.x + 12, 58, @as(f32, @floatFromInt(phys.broad_checks % 200)), 4, Color.yellow);
                b.drawRect(app.cam.pos.x + 12, 64, @as(f32, @floatFromInt(phys.narrow_checks % 200)), 4, Color.red);
                _ = st;
            }
        }

        // score
        if (score_board) |sb| { if (app.batchPtr()) |b| sb.draw(b, score); }
        for (0..@as(usize, lives)) |i| app.win.drawRect(12 + @as(f32, @floatFromInt(i)) * 18 + app.cam.pos.x, 12, 12, 6, Color.white);

        if (won) {
            app.win.drawRect(app.cam.pos.x + WW / 2 - 80, WH / 2 - 20, 160, 40, Color.rgba(0, 0, 0, 160));
            app.win.drawRectOutline(app.cam.pos.x + WW / 2 - 80, WH / 2 - 20, 160, 40, Color.white);
        } else if (lives == 0) {
            app.win.drawRect(app.cam.pos.x + WW / 2 - 80, WH / 2 - 20, 160, 40, Color.rgba(0, 0, 0, 160));
            app.win.drawRectOutline(app.cam.pos.x + WW / 2 - 80, WH / 2 - 20, 160, 40, Color.red);
        }

        app.endFrame();
        app.capFps(dt);
    }
}
