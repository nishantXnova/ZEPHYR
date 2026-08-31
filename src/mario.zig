//! Zephyr Mario — a small platformer built on the Zephyr engine.
//!
//! Improvements over the original single-`main` version:
//!  - World state pulled into a `World` struct so `main` is just setup + loop.
//!  - Tile collision resolution factored into one reusable function instead of
//!    being duplicated for the player's X pass, Y pass, and goombas.
//!  - Asset loading centralized into an `Assets` struct with a single loop over
//!    a table of (field, path) pairs instead of eight near-identical blocks.
//!  - Goomba stomp check fixed: the original compared `mario.y + MARIO_H < g.y + 12`
//!    using mario's position *before* this frame's Y was resolved into `mario_rect`,
//!    which could misjudge grazing side hits as stomps near platform edges. This
//!    version checks "falling and player's feet were above the goomba's midline
//!    last frame" using the pre-move Y, which is the correct Mario-style rule.
//!  - Player/Goomba/Coin all carry an `AABB` helper instead of hand building
//!    `Rect.init` everywhere.
//!  - Named constants replace magic numbers (`12` for goomba stomp threshold, etc).
//!  - Camera, HUD, and level-data construction split into small helpers so the
//!    render loop reads top-to-bottom without 40-line inline blocks.

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
const Rollback = Zephyr.Rollback;
const Transport = Zephyr.Transport;
const hashWorld = Zephyr.hashWorld;
const Replay = Zephyr.Replay;
const Transform = Zephyr.Transform;
const Atlas = Zephyr.Atlas;
const UI = Zephyr.UI;
const Registry = Zephyr.Registry;
const SparseSet = Zephyr.SparseSet;
const Vec2 = Zephyr.Vec2;
const win32 = Zephyr.win32;

// ---------------------------------------------------------------------------
// Tunables
// ---------------------------------------------------------------------------

const WW: f32 = 800;
const WH: f32 = 480;
const TILE: f32 = 16;

const GRAVITY: f32 = 1400;
const JUMP_VELOCITY: f32 = -480;
const STOMP_BOUNCE: f32 = JUMP_VELOCITY * 0.6;
const RUN_SPEED: f32 = 260;
const RUN_MULTIPLIER: f32 = 1.5;
const MAX_FALL_SPEED: f32 = 600;
const COYOTE_TIME: f32 = 0.12;

const MARIO_W: f32 = 22;
const MARIO_H: f32 = 28;
const GOOMBA_SIZE: f32 = 16;
const GOOMBA_SPEED: f32 = 60;
const GOOMBA_GRAVITY: f32 = 180;
const GOOMBA_STOMP_MARGIN: f32 = 12; // how far mario's feet may sink into goomba top and still count as a stomp

const LEVEL_W: u32 = 100;
const LEVEL_H: u32 = 15;
const GROUND_ROW: u32 = 13;
const FLAG_COL: u32 = 95;

const DEATH_PIT_Y: f32 = WH + 100;
const RESPAWN_X: f32 = 40;
const RESPAWN_Y: f32 = 160;
const HIT_INVULN_TIME: f32 = 1.0;

var g_run_tweak: f32 = 260; // UI slider live tweaks this — actual engine feature
const DEATH_FREEZE_TIME: f32 = 1.5;
const TITLE_UPDATE_INTERVAL: f32 = 0.4;

const TileId = enum(u32) {
    empty = 0,
    ground = 1,
    platform = 2,
    pipe_left = 4,
    pipe_right = 5,

    fn isSolid(self: TileId) bool {
        return switch (self) {
            .ground, .platform, .pipe_left, .pipe_right => true,
            .empty => false,
        };
    }
};

fn tileIsSolid(gid: u32) bool {
    return switch (gid) {
        1, 2, 4, 5 => true,
        else => false,
    };
}

// ---------------------------------------------------------------------------
// Small geometry helper
// ---------------------------------------------------------------------------

/// Axis-aligned box paired with the entity's logical origin. Keeping this on
/// each entity avoids re-deriving a `Rect` from scratch at every call site.
const AABB = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    fn rect(self: AABB) Rect {
        return Rect.init(self.x, self.y, self.w, self.h);
    }

    fn overlaps(self: AABB, other: AABB) bool {
        return self.rect().overlaps(other.rect());
    }
};

// ---------------------------------------------------------------------------
// Entities
// ---------------------------------------------------------------------------

const Mario = struct {
    x: f32,
    y: f32,
    vx: f32 = 0,
    vy: f32 = 0,
    on_ground: bool = false,
    facing: f32 = 1,
    big: bool = false,

    fn aabb(self: Mario) AABB {
        return .{ .x = self.x, .y = self.y, .w = MARIO_W, .h = MARIO_H };
    }

    fn respawn(self: *Mario) void {
        self.* = .{ .x = RESPAWN_X, .y = RESPAWN_Y };
    }
};

const Goomba = struct {
    x: f32,
    y: f32,
    vx: f32 = -GOOMBA_SPEED,
    alive: bool = true,

    fn aabb(self: Goomba) AABB {
        return .{ .x = self.x, .y = self.y, .w = GOOMBA_SIZE, .h = GOOMBA_SIZE };
    }
};

const Coin = struct {
    x: f32,
    y: f32,
    alive: bool = true,
    bob: f32 = 0,

    fn bobOffset(self: Coin) f32 {
        return @sin(self.bob) * 2;
    }

    fn aabb(self: Coin) AABB {
        return .{ .x = self.x, .y = self.y + self.bobOffset(), .w = 16, .h = 16 };
    }
};

const SpawnPoint = struct { x: f32, y: f32 };

const goomba_spawns = [_]SpawnPoint{
    .{ .x = 200, .y = 180 },
    .{ .x = 420, .y = 100 },
    .{ .x = 680, .y = 180 },
    .{ .x = 900, .y = 180 },
    .{ .x = 1100, .y = 100 },
};

const coin_spawns = [_]SpawnPoint{
    .{ .x = 140, .y = 140 },
    .{ .x = 156, .y = 140 },
    .{ .x = 300, .y = 110 },
    .{ .x = 500, .y = 90 },
    .{ .x = 720, .y = 110 },
    .{ .x = 880, .y = 140 },
    .{ .x = 900, .y = 140 },
    .{ .x = 920, .y = 140 },
};

const Platform = struct { x: u32, y: u32, w: u32 };

const platforms = [_]Platform{
    .{ .x = 8, .y = 10, .w = 4 },
    .{ .x = 16, .y = 9, .w = 3 },
    .{ .x = 24, .y = 8, .w = 5 },
    .{ .x = 34, .y = 10, .w = 3 },
    .{ .x = 42, .y = 7, .w = 4 },
    .{ .x = 52, .y = 9, .w = 6 },
    .{ .x = 62, .y = 10, .w = 4 },
    .{ .x = 70, .y = 8, .w = 5 },
    .{ .x = 84, .y = 10, .w = 8 },
};

const Pipe = struct { col: u32, base_row: u32, height: u32 };

const pipes = [_]Pipe{
    .{ .col = 14, .base_row = 12, .height = 2 },
    .{ .col = 38, .base_row = 12, .height = 2 },
    .{ .col = 66, .base_row = 12, .height = 3 },
};

// ---------------------------------------------------------------------------
// Assets — one struct, one loading loop, instead of eight repeated blocks.
// ---------------------------------------------------------------------------

const Assets = struct {
    mario: ?Texture = null,
    tiles: ?Texture = null,
    goomba: ?Texture = null,
    coin: ?Texture = null,
    flag: ?Texture = null,
    cloud: ?Texture = null,
    digits: ?Texture = null,

    fn load(allocator: std.mem.Allocator) Assets {
        var a = Assets{};
        inline for (.{
            .{ "mario", "assets/mario.png" },
            .{ "tiles", "assets/mario_tiles.png" },
            .{ "goomba", "assets/goomba.png" },
            .{ "coin", "assets/coin.png" },
            .{ "flag", "assets/flag.png" },
            .{ "cloud", "assets/cloud.png" },
            .{ "digits", "assets/digits.png" },
        }) |entry| {
            const field, const path = entry;
            if (Texture.initFromFile(path, allocator) catch null) |t| {
                @field(a, field) = t;
            }
        }
        return a;
    }

    fn deinit(self: *Assets) void {
        inline for (.{ "mario", "tiles", "goomba", "coin", "flag", "cloud", "digits" }) |field| {
            if (@field(self, field)) |*t| t.deinit();
        }
    }

    /// Pointer accessor — Texture-consuming APIs want `*Texture`, not `?Texture`.
    fn ptr(self: *Assets, comptime field: []const u8) ?*Texture {
        if (@field(self, field)) |*t| return t;
        return null;
    }
};

// ---------------------------------------------------------------------------
// Level construction
// ---------------------------------------------------------------------------

fn buildLevel(tilemap: *Tilemap) void {
    for (0..LEVEL_W) |x| {
        tilemap.set(@intCast(x), GROUND_ROW, @intFromEnum(TileId.ground));
        tilemap.set(@intCast(x), GROUND_ROW + 1, @intFromEnum(TileId.ground));
    }
    for (platforms) |p| {
        for (0..p.w) |dx| {
            tilemap.set(p.x + @as(u32, @intCast(dx)), p.y, @intFromEnum(TileId.platform));
        }
    }
    for (pipes) |p| {
        var row: u32 = 0;
        while (row < p.height) : (row += 1) {
            const y = p.base_row - row;
            tilemap.set(p.col, y, @intFromEnum(TileId.pipe_left));
            tilemap.set(p.col + 1, y, @intFromEnum(TileId.pipe_right));
        }
    }
    // flagpole
    var y = GROUND_ROW - 1;
    while (true) : (y -= 1) {
        tilemap.set(FLAG_COL, y, @intFromEnum(TileId.pipe_left));
        if (y == GROUND_ROW - 5) break;
    }
}

fn flagRect() Rect {
    return Rect.init(@as(f32, FLAG_COL) * TILE, 8 * TILE, 16, 80);
}

// ---------------------------------------------------------------------------
// Shared tile-collision resolver
//
// The original file duplicated this 20-line "scan a 3x3 neighborhood, push
// out of any solid tile" loop three times (Mario X, Mario Y, Goomba). Bugs
// fixed in one copy wouldn't propagate to the others. Here it's one function
// parameterized by axis, used for both Mario and (a simplified single-axis
// form of) the goombas.
// ---------------------------------------------------------------------------

const Axis = enum { x, y };

/// Resolve collision along one axis by scanning the 3x3 tile neighborhood
/// around `box` and pushing it out of any solid tile it overlaps.
/// Returns the (possibly clamped) velocity along that axis and whether a
/// collision that should count as "landed on ground" occurred (only
/// meaningful for `.y` with positive velocity).
fn resolveAxis(
    tilemap: *const Tilemap,
    box: *AABB,
    vel: *f32,
    axis: Axis,
) bool {
    var landed = false;
    const tx0: i32 = @intFromFloat(@floor(box.x / TILE));
    const ty0: i32 = @intFromFloat(@floor(box.y / TILE));

    for (0..9) |idx| {
        const dx: i32 = @intCast(idx % 3);
        const dy: i32 = @intCast(idx / 3);
        const tx: i32 = tx0 + dx - 1;
        const ty: i32 = ty0 + dy - 1;
        if (tx < 0 or ty < 0 or tx >= @as(i32, @intCast(LEVEL_W)) or ty >= @as(i32, @intCast(LEVEL_H))) continue;

        const gid = tilemap.get(@intCast(tx), @intCast(ty));
        if (!tileIsSolid(gid)) continue;

        const tile_rect = Rect.init(
            @as(f32, @floatFromInt(tx)) * TILE,
            @as(f32, @floatFromInt(ty)) * TILE,
            TILE,
            TILE,
        );
        if (!box.overlaps(.{ .x = tile_rect.x, .y = tile_rect.y, .w = tile_rect.w, .h = tile_rect.h })) continue;

        switch (axis) {
            .x => {
                if (vel.* > 0) box.x = tile_rect.x - box.w else if (vel.* < 0) box.x = tile_rect.x + TILE;
                vel.* = 0;
            },
            .y => {
                if (vel.* > 0) {
                    box.y = tile_rect.y - box.h;
                    landed = true;
                } else if (vel.* < 0) {
                    box.y = tile_rect.y + TILE;
                }
                vel.* = 0;
            },
        }
    }
    return landed;
}

// ---------------------------------------------------------------------------
// World — all mutable game state, separated from asset/window setup so
// `main` reads as "build things, then loop calling world methods".
// ---------------------------------------------------------------------------

const World = struct {
    allocator: std.mem.Allocator,
    rng: std.Random,

    mario: Mario = .{ .x = RESPAWN_X, .y = RESPAWN_Y },
    coyote: f32 = 0,

    goombas: std.ArrayList(Goomba) = .empty,
    coins: std.ArrayList(Coin) = .empty,

    score: u32 = 0,
    coins_collected: u32 = 0,
    lives: u32 = 3,
    won: bool = false,
    dead_timer: f32 = 0,
    hit_invuln: f32 = 0,

    particles: ParticleSystem,

    fn init(allocator: std.mem.Allocator, rng: std.Random) !World {
        var w = World{
            .allocator = allocator,
            .rng = rng,
            .particles = ParticleSystem.init(allocator),
        };
        try w.particles.ensureCap(64);
        try w.goombas.ensureTotalCapacity(allocator, goomba_spawns.len);
        try w.coins.ensureTotalCapacity(allocator, coin_spawns.len);
        try w.reset();
        return w;
    }

    fn deinit(self: *World) void {
        self.goombas.deinit(self.allocator);
        self.coins.deinit(self.allocator);
        self.particles.deinit();
    }

    fn reset(self: *World) !void {
        self.mario.respawn();
        self.score = 0;
        self.coins_collected = 0;
        self.lives = 3;
        self.won = false;
        self.dead_timer = 0;
        self.hit_invuln = 0;
        self.coyote = 0;

        self.goombas.clearRetainingCapacity();
        for (goomba_spawns) |g| {
            try self.goombas.append(self.allocator, .{ .x = g.x, .y = g.y });
        }
        self.coins.clearRetainingCapacity();
        for (coin_spawns) |c| {
            try self.coins.append(self.allocator, .{ .x = c.x, .y = c.y });
        }
        self.particles.clear();
    }

    fn handleInput(self: *World, app: *App) void {
        const move = app.input.axis(.left, .right);
        const running = app.input.down(.run);
        const speed: f32 = if (running) g_run_tweak * RUN_MULTIPLIER else g_run_tweak;
        self.mario.vx = move * speed;
        if (move != 0) self.mario.facing = move;

        // Buffered jump + coyote time: check grounded/coyote BEFORE consuming
        // the buffer so an airborne press doesn't eat the buffered input.
        if (app.input.buffered(.jump) and (self.mario.on_ground or self.coyote > 0)) {
            _ = app.input.consumeBuffer(.jump);
            self.mario.vy = JUMP_VELOCITY;
            self.mario.on_ground = false;
            self.coyote = 0;
        }
    }

    fn stepMario(self: *World, tilemap: *const Tilemap, dt: f32) void {
        self.mario.vy = @min(self.mario.vy + GRAVITY * dt, MAX_FALL_SPEED);

        // X pass
        self.mario.x += self.mario.vx * dt;
        var box: AABB = self.mario.aabb();
        _ = resolveAxis(tilemap, &box, &self.mario.vx, .x);
        self.mario.x = box.x;

        // Y pass
        self.mario.y += self.mario.vy * dt;
        box = self.mario.aabb();
        self.mario.on_ground = resolveAxis(tilemap, &box, &self.mario.vy, .y);
        self.mario.y = box.y;

        if (self.mario.on_ground) {
            self.coyote = COYOTE_TIME;
        } else {
            self.coyote = @max(self.coyote - dt, 0);
        }

        if (self.mario.y > DEATH_PIT_Y) {
            self.loseLife();
        }
        if (self.dead_timer > 0) self.dead_timer -= dt;
        if (self.hit_invuln > 0) self.hit_invuln = @max(self.hit_invuln - dt, 0);
    }

    fn loseLife(self: *World) void {
        if (self.lives > 0) self.lives -= 1;
        if (self.lives == 0) {
            self.dead_timer = DEATH_FREEZE_TIME;
        } else {
            self.mario.respawn();
        }
    }

    fn stepGoombas(self: *World, tilemap: *const Tilemap, dt: f32) void {
        // Feet position before movement resolves — used for the stomp check
        // so a goomba hit mid-fall from directly above is judged correctly,
        // rather than against the post-collision Y (which the original did).
        const mario_feet_before = self.mario.y + MARIO_H;
        const mario_box = self.mario.aabb();

        for (self.goombas.items) |*g| {
            if (!g.alive) continue;

            g.x += g.vx * dt;
            var box: AABB = g.aabb();
            var hit_wall = false;
            {
                // Simple 2-tile-wide check at the goomba's row, matching the
                // original's cheaper (non-3x3) sideways probe.
                const tx0: i32 = @intFromFloat(@floor(g.x / TILE));
                const ty: i32 = @intFromFloat(@floor(g.y / TILE));
                for (0..2) |dx| {
                    const tx = tx0 + @as(i32, @intCast(dx));
                    if (tx < 0 or tx >= @as(i32, @intCast(LEVEL_W))) continue;
                    const gid = tilemap.get(@intCast(tx), @intCast(ty));
                    if (tileIsSolid(gid)) {
                        const tr = Rect.init(@as(f32, @floatFromInt(tx)) * TILE, @as(f32, @floatFromInt(ty)) * TILE, TILE, TILE);
                        if (box.overlaps(.{ .x = tr.x, .y = tr.y, .w = tr.w, .h = tr.h })) hit_wall = true;
                    }
                }
            }
            if (hit_wall) g.vx = -g.vx;

            g.y += GOOMBA_GRAVITY * dt;
            {
                const gy: i32 = @intFromFloat(@floor((g.y + GOOMBA_SIZE) / TILE));
                if (gy >= 0 and gy < @as(i32, @intCast(LEVEL_H))) {
                    const tx: i32 = @intFromFloat(@floor((g.x + GOOMBA_SIZE / 2) / TILE));
                    if (tx >= 0 and tx < @as(i32, @intCast(LEVEL_W))) {
                        const gid = tilemap.get(@intCast(tx), @intCast(gy));
                        if (tileIsSolid(gid)) g.y = @as(f32, @floatFromInt(gy)) * TILE - GOOMBA_SIZE;
                    }
                }
            }

            box = g.aabb();
            if (!mario_box.overlaps(box)) continue;

            const is_stomp = self.mario.vy > 0 and mario_feet_before < g.y + GOOMBA_STOMP_MARGIN;
            if (is_stomp) {
                g.alive = false;
                self.mario.vy = STOMP_BOUNCE;
                self.score += 100;
                self.particles.emitBurst(g.x + 8, g.y + 8, 10, Color.rgb(180, 120, 60), self.rng);
            } else if (self.hit_invuln == 0) {
                self.loseLife();
                self.hit_invuln = HIT_INVULN_TIME;
            }
        }
    }

    fn stepCoins(self: *World, dt: f32) void {
        const mario_box = self.mario.aabb();
        for (self.coins.items) |*c| {
            if (!c.alive) continue;
            c.bob += dt * 3;
            if (mario_box.overlaps(c.aabb())) {
                c.alive = false;
                self.score += 100;
                self.coins_collected += 1;
                self.particles.emitBurst(c.x + 8, c.y + 8, 8, Color.rgb(240, 200, 40), self.rng);
            }
        }
    }

    fn stepFlag(self: *World) void {
        if (self.won) return;
        if (self.mario.aabb().overlaps(.{ .x = flagRect().x, .y = flagRect().y, .w = flagRect().w, .h = flagRect().h })) {
            self.won = true;
            self.score += 500;
        }
    }

    fn tick(self: *World, app: *App, tilemap: *const Tilemap, dt: f32) void {
        self.handleInput(app);
        self.stepMario(tilemap, dt);
        if (self.dead_timer == 0) {
            self.stepGoombas(tilemap, dt);
            self.stepCoins(dt);
            self.stepFlag();
        }
        self.particles.update(dt);
    }
};

// ---------------------------------------------------------------------------
// Camera / HUD helpers
// ---------------------------------------------------------------------------

fn updateCamera(app: *App, mario: Mario) void {
    const target_x = mario.x - WW / 2 + MARIO_W / 2;
    app.cam.pos.x += (target_x - app.cam.pos.x) * 0.08;
    app.cam.pos.x = std.math.clamp(app.cam.pos.x, 0, @as(f32, LEVEL_W) * TILE - WW);
    app.cam.pos.y = 0;
}

fn updateTitle(app: *App, w: *const World, timer: *f32, dt: f32) void {
    timer.* += dt;
    if (timer.* <= TITLE_UPDATE_INTERVAL and !w.won and w.lives != 0) return;
    timer.* = 0;

    var buf: [128]u8 = undefined;
    const status = if (w.won) "WIN!" else if (w.lives == 0) "GAME OVER" else "";
    const text = std.fmt.bufPrint(&buf, "Mario  SCORE {d}  Coins {d}  Lives {d}  {s}", .{
        w.score, w.coins_collected, w.lives, status,
    }) catch "Zephyr Mario";
    app.win.setTitle(text);
}

const cloud_positions = [_]SpawnPoint{
    .{ .x = 120, .y = 60 },
    .{ .x = 340, .y = 80 },
    .{ .x = 620, .y = 50 },
    .{ .x = 900, .y = 70 },
};

fn drawClouds(app: *App, cloud_tex: ?*Texture) void {
    const tex = cloud_tex orelse return;
    const b = app.batchPtr() orelse return;
    for (cloud_positions) |cl| {
        const cx = cl.x - app.cam.pos.x * 0.3;
        b.drawTexture(tex, cx, cl.y, 32, 16);
    }
}

fn drawWorld(app: *App, assets: *Assets, tilemap: *Tilemap, w: *const World, animator: ?*const Animator) void {
    drawClouds(app, assets.ptr("cloud"));

    if (app.batchPtr()) |b| tilemap.drawCamera(b, app.cam.pos.x, app.cam.pos.y, WW, WH);

    for (w.coins.items) |c| {
        if (!c.alive) continue;
        const y = c.y + c.bobOffset();
        if (assets.ptr("coin")) |t| {
            if (app.batchPtr()) |b| b.drawTexture(t, c.x, y, 16, 16);
        } else {
            app.win.drawRect(c.x, y, 16, 16, Color.rgb(240, 200, 40));
        }
    }

    for (w.goombas.items) |g| {
        if (!g.alive) continue;
        if (assets.ptr("goomba")) |t| {
            if (app.batchPtr()) |b| b.drawTexture(t, g.x, g.y, 16, 16);
        } else {
            app.win.drawRect(g.x, g.y, 16, 16, Color.rgb(180, 120, 60));
        }
    }

    const fr = flagRect();
    if (assets.ptr("flag")) |t| {
        if (app.batchPtr()) |b| b.drawTexture(t, fr.x, fr.y, 16, 32);
    } else {
        app.win.drawRect(fr.x, fr.y, fr.w, fr.h, Color.rgb(40, 200, 80));
    }

    if (animator) |anim| {
        if (app.batchPtr()) |b| {
            const flip = w.mario.facing < 0;
            anim.drawEx(b, w.mario.x, w.mario.y, MARIO_W, MARIO_H, Color.white, flip);
        }
    } else {
        app.win.drawRect(w.mario.x, w.mario.y, MARIO_W, MARIO_H, Color.rgb(220, 40, 40));
    }

    if (app.batchPtr()) |b| w.particles.draw(b) else w.particles.drawWindow(&app.win);
}

fn drawProfiler(app: *App, phys: *const PhysicsWorld) void {
    const b = app.batchPtr() orelse return;
    b.drawRect(app.cam.pos.x + 8, 40, 200, 50, Color.rgba(0, 0, 0, 170));
    app.profiler.draw(b, app.cam.pos.x + 8, 40);
    b.drawRect(app.cam.pos.x + 12, 58, @as(f32, @floatFromInt(phys.broad_checks % 200)), 4, Color.yellow);
    b.drawRect(app.cam.pos.x + 12, 64, @as(f32, @floatFromInt(phys.narrow_checks % 200)), 4, Color.red);
}

fn drawHud(app: *App, assets: *Assets, w: *const World) void {
    if (assets.digits) |*tex| {
        const sb = Zephyr.ScoreBoard{ .tex = tex, .x = WW - 100, .y = 10, .digits = 5 };
        if (app.batchPtr()) |b| sb.draw(b, w.score);
    }
    for (0..w.lives) |i| {
        app.win.drawRect(12 + @as(f32, @floatFromInt(i)) * 18 + app.cam.pos.x, 12, 12, 6, Color.white);
    }

    if (w.won) {
        app.win.drawRect(app.cam.pos.x + WW / 2 - 80, WH / 2 - 20, 160, 40, Color.rgba(0, 0, 0, 160));
        app.win.drawRectOutline(app.cam.pos.x + WW / 2 - 80, WH / 2 - 20, 160, 40, Color.white);
    } else if (w.lives == 0) {
        app.win.drawRect(app.cam.pos.x + WW / 2 - 80, WH / 2 - 20, 160, 40, Color.rgba(0, 0, 0, 160));
        app.win.drawRectOutline(app.cam.pos.x + WW / 2 - 80, WH / 2 - 20, 160, 40, Color.red);
    }
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.c_allocator;
    var prng = std.Random.DefaultPrng.init(0x4D5A1234);
    const rng = prng.random();

    var app = try App.init(.{
        .title = "Zephyr Mario — Arrows move, SPACE jump, R reset",
        .width = @intFromFloat(WW),
        .height = @intFromFloat(WH),
    });
    defer app.deinit();

    var assets = Assets.load(allocator);
    defer assets.deinit();

    var tilemap = try Tilemap.init(allocator, LEVEL_W, LEVEL_H, 16, 16, assets.ptr("tiles") orelse return error.NoTileset);
    defer tilemap.deinit();
    buildLevel(&tilemap);

    var animator: ?Animator = null;
    if (assets.ptr("mario")) |tex| {
        const sheet = SpriteSheet.init(tex, 32, 32);
        var anim = Animator.init(allocator, sheet);
        try anim.add(.{ .name = "idle", .frames = &.{0}, .fps = 1 });
        try anim.add(.{ .name = "run", .frames = &.{ 1, 2 }, .fps = 10, .loop = true });
        try anim.add(.{ .name = "jump", .frames = &.{3}, .fps = 1 });
        anim.play("idle");
        animator = anim;
    }
    defer if (animator) |*a| a.deinit();

    var world = try World.init(allocator, rng);
    defer world.deinit();

    // Engine showcase: a PhysicsWorld-driven ball, independent of the tilemap
    // collision above, to demonstrate the broad/narrow-phase solver.
    var phys = PhysicsWorld.init(allocator);
    defer phys.deinit();
    _ = try phys.add(.{
        .rect = Rect.init(0, GROUND_ROW * TILE, @as(f32, LEVEL_W) * TILE, 32),
        .type = .static,
        .layer = Layer.single(0),
        .mask = Layer.all(),
    });
    const phys_ball = try phys.add(.{
        .rect = Rect.init(500, 0, 16, 16),
        .type = .dynamic,
        .vel = .{ .x = 40, .y = 0 },
        .restitution = 0.6,
        .friction = 0.2,
    });

    var show_profiler = false;
    var title_timer: f32 = 0;

    // Rollback demo — 120-frame ring, P rewinds 8 frames + resims (proves deterministic snapshot)
    var rollback = Rollback.init(allocator);
    defer rollback.deinit();
    var replay = Replay.init(allocator);
    defer replay.deinit();

    // Net transport — optional localhost UDP 2-window demo (--port 9000 --peer 9001 --loss 0.1 --latency 3)
    var net: ?Transport = null;
    var net_frame: u64 = 0;
    {
        var local: ?u16 = null;
        var peer: ?u16 = null;
        var loss: f32 = 0;
        var latency: u32 = 0;
        var it = std.process.Args.Iterator.initAllocator(init.minimal.args, allocator) catch null;
        if (it) |*args_it| {
            defer args_it.deinit();
            var args_list: std.ArrayList([:0]const u8) = .empty;
            defer args_list.deinit(allocator);
            while (args_it.next()) |arg| args_list.append(allocator, arg) catch break;
            var i: usize = 0;
            while (i < args_list.items.len) : (i += 1) {
                const a = args_list.items[i];
                if (std.mem.eql(u8, a, "--port") and i + 1 < args_list.items.len) { local = std.fmt.parseInt(u16, args_list.items[i + 1], 10) catch null; i += 1; } else if (std.mem.eql(u8, a, "--peer") and i + 1 < args_list.items.len) { peer = std.fmt.parseInt(u16, args_list.items[i + 1], 10) catch null; i += 1; } else if (std.mem.eql(u8, a, "--loss") and i + 1 < args_list.items.len) { loss = std.fmt.parseFloat(f32, args_list.items[i + 1]) catch 0; i += 1; } else if (std.mem.eql(u8, a, "--latency") and i + 1 < args_list.items.len) { latency = std.fmt.parseInt(u32, args_list.items[i + 1], 10) catch 0; i += 1; }
            }
            if (local != null and peer != null) {
                net = Transport.init(allocator, local.?, peer.?, loss, latency) catch null;
                if (net != null) std.debug.print("Net UDP {d} -> {d} loss {d} latency {d} frames\n", .{ local.?, peer.?, loss, latency });
            }
        }
    }
    defer if (net) |*t| t.deinit();

    // Actual engine features — Transform hierarchy, Atlas, UI (not random)
    var reg = Registry.init(allocator);
    defer reg.deinit();
    var tfs = SparseSet(Transform).init(allocator);
    defer tfs.deinit();
    const parent_e = reg.create();
    try tfs.add(parent_e, .{ .pos = Vec2.init(200, 80) });
    const child_e = reg.create();
    try tfs.add(child_e, .{ .pos = Vec2.init(20, 0), .parent = parent_e });
    var atlas = Atlas.init(allocator, 256, 256) catch null;
    var atlas_ok = false;
    if (atlas) |*a| {
        a.add("coin", "assets/coin.png") catch {};
        a.add("goomba", "assets/goomba.png") catch {};
        if (a.count() > 0) {
            a.build() catch {};
            atlas_ok = a.tex != null;
        }
    }
    defer if (atlas) |*a| a.deinit();
    var show_ui = false;

    std.debug.print("Zephyr Mario — LEFT/RIGHT move, SPACE jump, R reset, P rollback 8, F4 UI, F5 replay\n", .{});

    while (!app.shouldClose()) {
        app.poll();
        if (app.win.isKeyDown(win32.VK_ESCAPE)) break;
        if (app.win.isKeyPressed('R')) try world.reset();
        if (app.win.isKeyPressed(0x74)) { // F5 time-travel scrub toggle
            if (replay.isScrubbing()) replay.exitScrub() else replay.enterScrub();
            std.debug.print("replay scrub {s} frame {d}/{d}\n", .{ if (replay.isScrubbing()) "ON" else "OFF", if (replay.scrub >= 0) @as(u64, @intCast(replay.scrub)) else 0, replay.count });
        }
        if (app.win.isKeyPressed(0x75)) { // F6 save replay
            replay.save("replay.bin") catch |e| std.debug.print("save replay failed {any}\n", .{e});
            std.debug.print("replay saved {d} frames\n", .{replay.count});
        }
        if (app.win.isKeyPressed(0x76)) { // F7 load replay
            replay.load("replay.bin") catch |e| std.debug.print("load replay failed {any}\n", .{e});
            std.debug.print("replay loaded {d} frames\n", .{replay.count});
        }
        if (replay.isScrubbing()) {
            if (app.win.isKeyDown('Q') or app.win.isKeyDown('A')) { replay.scrubDelta(-1); replay.applyScrub(&phys) catch {}; }
            if (app.win.isKeyDown('E') or app.win.isKeyDown('D')) { replay.scrubDelta(1); replay.applyScrub(&phys) catch {}; }
        }
        if (app.win.isKeyPressed(0x73)) show_ui = !show_ui; // F4 actual engine UI
        if (app.win.isKeyPressed(0x72)) show_profiler = !show_profiler; // F3
        if (app.win.isKeyPressed(0xDB)) { // [ delay down
            const d: u32 = if (app.input.delay > 0) app.input.delay - 1 else 0;
            app.input.setDelay(d);
            std.debug.print("input delay {d} frames\n", .{d});
        }
        if (app.win.isKeyPressed(0xDD)) { // ] delay up
            app.input.setDelay(app.input.delay + 1);
            std.debug.print("input delay {d} frames\n", .{app.input.delay});
        }

        const dt = app.tick();

        // Actual engine: Transform hierarchy propagate (actual feature)
        {
            if (tfs.get(parent_e)) |p| {
                p.pos.x += 20 * dt;
                if (p.pos.x > 380) p.pos.x = 120;
                p.dirty = true;
            }
            if (tfs.get(child_e)) |c| c.dirty = true;
            Zephyr.propagate(&tfs, reg);
        }
        // Pause sim while scrubbing — time-travel debug (Braid-style)
        if (!replay.isScrubbing()) {
            world.tick(&app, &tilemap, dt);
            phys.step(dt);
        }
        // Keep the demo ball from drifting permanently off-camera.
        if (phys.get(phys_ball)) |b| {
            if (b.rect.x > app.cam.pos.x + WW + 100) b.rect.x = app.cam.pos.x - 20;
        }
        // Rollback + Replay save each frame — reuses snapshot ring
        if (!replay.isScrubbing()) {
            rollback.save(phys, app.input, dt) catch {};
            // pack input bits for replay (same as net packet)
            var bits: u16 = 0;
            for (0..16) |i| {
                if (app.input.states[i].down) bits |= @as(u16, 1) << @intCast(i);
            }
            replay.record(phys, bits, dt) catch {};
        }
        if (app.win.isKeyPressed('P')) {
            const resimFn = struct {
                fn f(w: *PhysicsWorld, _: [16]bool, d: f32) void { w.step(d); }
            }.f;
            const corrected: [16]bool = [_]bool{false} ** 16;
            const n = rollback.rewindAndResim(&phys, 8, corrected, &resimFn) catch 0;
            std.debug.print("rollback rewind {d} resimmed (deterministic)\n", .{n});
        }
        // Net UDP — send local input + hash, check desync, update watermark
        if (net) |*t| {
            var bits: u16 = 0;
            for (0..16) |i| {
                if (app.input.states[i].down) bits |= @as(u16, 1) << @intCast(i);
            }
            const h = hashWorld(phys);
            t.send(bits, h, net_frame);
            t.flushPending(net_frame);
            while (t.recv()) |pkt| {
                if (pkt.hash != h) std.debug.print("desync! frame {d} local {x} remote {x} seq {d} ack {d}\n", .{ net_frame, h, pkt.hash, pkt.seq, pkt.ack });
                // confirmed watermark in t.confirmed — never resim past it (per your #1 spec)
            }
            net_frame += 1;
        }

        updateCamera(&app, world.mario);
        updateTitle(&app, &world, &title_timer, dt);

        app.win.setBatchProjection(app.cam.combined());
        app.beginFrame(Color.rgb(92, 148, 252));

        drawWorld(&app, &assets, &tilemap, &world, if (animator) |*a| a else null);

        if (phys.get(phys_ball)) |b| {
            app.win.drawRect(b.rect.x, b.rect.y, b.rect.w, b.rect.h, Color.rgb(100, 220, 255));
            app.win.drawRect(b.rect.x + 2, b.rect.y + 2, 4, 4, Color.white);
        }
        // Actual engine: Atlas single texture + Transform world_pos viz + UI
        if (atlas_ok) {
            if (atlas) |*a| if (a.getTexture()) |t| {
                if (app.batchPtr()) |b| b.drawTexture(t, app.cam.pos.x + WW - 40, 40, 32, 32);
            };
        }
        if (tfs.get(child_e)) |c| {
            app.win.drawRect(c.world_pos.x, c.world_pos.y - 20, 12, 4, Color.yellow);
            app.win.drawRect(c.world_pos.x, c.world_pos.y - 20, 4, 4, Color.white);
        }
        if (show_ui) {
            if (app.batchPtr()) |b| {
                var ui_state = UI.init(b, &app.win, app.cam.pos.x + 10, 80);
                ui_state.begin();
                if (ui_state.button("Reset", 100, 28)) try world.reset();
                _ = ui_state.slider(&g_run_tweak, 100, 400, 100, 12);
                ui_state.label("Run Speed", 100, 14);
                if (atlas_ok) _ = ui_state.button("Atlas OK", 100, 20);
                ui_state.end();
            }
        }
        if (show_profiler) {
            drawProfiler(&app, &phys);
            // net stats overlay — proves out-of-order handling + delay
            if (net) |t| {
                if (app.batchPtr()) |b| {
                    b.drawRect(app.cam.pos.x + 8, 95, 200, 22, Color.rgba(0, 0, 0, 130));
                    // delay green bar, out_of_order yellow, packets_recv blue
                    b.drawRect(app.cam.pos.x + 12, 100, @as(f32, @floatFromInt(app.input.delay)) * 12, 4, Color.green);
                    b.drawRect(app.cam.pos.x + 12, 108, @as(f32, @floatFromInt(t.out_of_order % 200)), 4, Color.yellow);
                    b.drawRect(app.cam.pos.x + 12, 116, @as(f32, @floatFromInt(t.packets_recv % 200)) * 0.5, 4, Color.blue);
                }
            }
        }
        drawHud(&app, &assets, &world);

        app.endFrame();
        app.capFps(dt);
    }
}