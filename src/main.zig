const std = @import("std");
const Zephyr = @import("Zephyr");
const App = Zephyr.App;
const Color = Zephyr.Color;
const Rect = Zephyr.Rect;
const win32 = Zephyr.win32;
const Texture = Zephyr.Texture;
const PipeSystem = Zephyr.PipeSystem;
const AudioEngine = Zephyr.AudioEngine;
const Animator = Zephyr.Animator;
const SpriteSheet = Zephyr.SpriteSheet;
const Tilemap = Zephyr.Tilemap;

const WW: f32 = 480;
const WH: f32 = 640;
const GROUND_H: f32 = 80;
const BIRD_X: f32 = 90;
const BIRD_W: f32 = 34;
const BIRD_H: f32 = 24;
const GRAVITY: f32 = 1200;
const FLAP_VEL: f32 = -380;

const GameState = enum { ready, playing, dead };

const Game = struct {
    bird_y: f32,
    bird_vy: f32,
    pipes: PipeSystem,
    score: u32,
    state: GameState,
    bob_t: f32 = 0,
    animator: ?Animator = null,

    fn init(allocator: std.mem.Allocator, rng: std.Random, animator: ?Animator) Game {
        return .{
            .bird_y = WH / 2 - 40,
            .bird_vy = 0,
            .pipes = PipeSystem.init(allocator, rng, WW, WH),
            .score = 0,
            .state = .ready,
            .animator = animator,
        };
    }
    fn deinit(self: *Game) void {
        if (self.animator) |*a| a.deinit();
        self.pipes.deinit();
    }
    fn reset(self: *Game) void {
        self.bird_y = WH / 2 - 40;
        self.bird_vy = 0;
        self.pipes.reset();
        self.score = 0;
        self.state = .ready;
        if (self.animator) |*a| a.play("flap");
    }
    fn flap(self: *Game) void {
        if (self.state == .dead) {
            self.reset();
            return;
        }
        if (self.state == .ready) self.state = .playing;
        self.bird_vy = FLAP_VEL;
        if (self.animator) |*a| a.play("flap");
    }
    fn update(self: *Game, dt: f32) void {
        if (self.animator) |*a| a.update(dt);
        if (self.state == .dead) return;
        if (self.state == .ready) {
            self.bob_t += dt;
            self.bird_y += @sin(self.bob_t * 4.0) * 0.18;
            return;
        }
        self.bird_vy += GRAVITY * dt;
        self.bird_y += self.bird_vy * dt;
        if (self.bird_y + BIRD_H >= WH - GROUND_H) {
            self.bird_y = WH - GROUND_H - BIRD_H;
            self.state = .dead;
        }
        if (self.bird_y < 0) {
            self.bird_y = 0;
            self.bird_vy = 0;
        }
        self.pipes.update(dt, &self.score);
        const bird_rect = Rect.init(BIRD_X, self.bird_y, BIRD_W, BIRD_H);
        if (self.pipes.checkCollision(bird_rect)) self.state = .dead;
    }

    fn draw(self: *Game, win: anytype, tilemap: ?*Tilemap, tileset_tex: ?*Texture) void {
        // --- Core2D: Tilemap beats Scratch stage ---
        if (tilemap) |tm| {
            if (win.batch) |*b| {
                // tilemap drawn with camera culling — pluggable 2D→3D
                tm.drawCamera(b, 0, 0, WW, WH);
            }
        } else {
            // fallback sky
            // (clear color already sky, but keep for GDI fallback)
        }

        // pipes via ECS
        self.pipes.draw(win);

        // ground over tilemap
        win.drawRect(0, WH - GROUND_H, WW, GROUND_H, Color.ground);
        win.drawRect(0, WH - GROUND_H, WW, 4, Color.rgb(180, 140, 90));

        // bird — Animator (SpriteSheet) beats Scratch costume
        const bx = BIRD_X;
        const by = self.bird_y;
        if (self.animator) |anim| {
            if (win.batch) |*b| {
                // use animator's current frame
                anim.draw(b, bx, by, Color.white);
                return;
            }
        }
        // fallback if no sheet
        _ = tileset_tex;
        win.drawRect(bx + 4, by + BIRD_H - 4, BIRD_W - 8, 6, Color.rgba(0, 0, 0, 60));
        win.drawRect(bx, by, BIRD_W, BIRD_H, Color.yellow);
        win.drawRect(bx + 6, by + 10, 14, 8, Color.rgb(255, 165, 0));
        win.drawRect(bx + 22, by + 6, 8, 8, Color.white);
        win.drawRect(bx + 24, by + 8, 4, 4, Color.black);
        win.drawRect(bx + BIRD_W - 2, by + 10, 8, 6, Color.red);

        // score backdrop — Core2D UI
        win.drawRect(WW / 2 - 44, 8, 88, 26, Color.rgba(0, 0, 0, 90));
        win.drawRectOutline(WW / 2 - 44, 8, 88, 26, Color.white);
        if (self.state == .ready) win.drawRectOutline(WW / 2 - 70, WH / 2 - 60, 140, 34, Color.white)
        else if (self.state == .dead) {
            win.drawRect(WW / 2 - 74, WH / 2 - 44, 148, 52, Color.rgba(0, 0, 0, 140));
            win.drawRectOutline(WW / 2 - 74, WH / 2 - 44, 148, 52, Color.white);
        }
    }
};

pub fn main(init: std.process.Init) !void {
    _ = init;
    const allocator = std.heap.c_allocator;
    var prng = std.Random.DefaultPrng.init(0xDEADBEEF_CAFE1234);
    const rng = prng.random();

    var app = try App.init(.{ .title = "Zephyr Core2D - Flappy + Tilemap + Sprites", .width = @intFromFloat(WW), .height = @intFromFloat(WH) });
    defer app.deinit();

    var audio = AudioEngine{ .engine = undefined };
    audio.init() catch |e| std.log.warn("audio init failed: {}", .{e});
    defer audio.deinit();
    var flap_snd: ?Zephyr.Sound = null;
    var hit_snd: ?Zephyr.Sound = null;
    var score_snd: ?Zephyr.Sound = null;
    if (audio.inited) {
        flap_snd = audio.loadSound("assets/flap.wav", allocator) catch null;
        hit_snd = audio.loadSound("assets/hit.wav", allocator) catch null;
        score_snd = audio.loadSound("assets/score.wav", allocator) catch null;
    }
    defer {
        if (flap_snd) |*s| audio.unload(s);
        if (hit_snd) |*s| audio.unload(s);
        if (score_snd) |*s| audio.unload(s);
    }

    // --- Core2D: SpriteSheet + Animator (Scratch costumes, but Zig) ---
    var sheet_tex: ?Texture = null;
    var sheet_tex_loaded: ?Texture = null;
    var animator: ?Animator = null;
    if (Texture.initFromFile("assets/bird_sheet.png", allocator)) |t| {
        sheet_tex_loaded = t;
        sheet_tex = sheet_tex_loaded;
        const sheet = SpriteSheet.init(&sheet_tex_loaded.?, 34, 24);
        var anim = Animator.init(allocator, sheet);
        try anim.add(.{ .name = "flap", .frames = &.{ 0, 1, 2, 1 }, .fps = 12, .loop = true });
        try anim.add(.{ .name = "idle", .frames = &.{0}, .fps = 1 });
        anim.play("flap");
        animator = anim;
        std.log.info("Animator: bird_sheet 102x24 3 frames @12fps", .{});
    } else |_| {
        // fallback to single bird.png
        if (Texture.initFromFile("assets/bird.png", allocator) catch null) |t| {
            sheet_tex_loaded = t;
            sheet_tex = sheet_tex_loaded;
            std.log.info("Loaded bird.png fallback", .{});
        } else std.log.info("No bird_sheet.png — using rect bird", .{});
    }
    defer {
        if (animator) |*a| a.deinit();
        if (sheet_tex_loaded) |*t| t.deinit();
    }

        // --- Core2D: Tilemap (beats Scratch stage) ---
    var tileset_tex: ?*Texture = null;
    var tileset_loaded: ?Texture = null;
    var tilemap: ?*Tilemap = null;
    var tilemap_loaded: ?Tilemap = null;
    if (Texture.initFromFile("assets/tileset.png", allocator)) |t| {
        tileset_loaded = t;
        tileset_tex = &tileset_loaded.?;
        const tm_try: ?Tilemap = Tilemap.init(allocator, 30, 40, 16, 16, &tileset_loaded.?) catch null;
        if (tm_try) |m| {
            var mm = m;
            for (0..40) |y| {
                for (0..30) |x| {
                    var gid: u32 = 4;
                    if (y >= 37) gid = 2 else if (y == 36) gid = 1 else if (y == 20 and x > 5 and x < 25 and x % 4 == 0) gid = 3 else if ((x + y) % 7 == 0) gid = 0;
                    mm.set(@intCast(x), @intCast(y), gid);
                }
            }
            tilemap_loaded = mm;
            tilemap = &tilemap_loaded.?;
            std.log.info("Tilemap 30x40 tiles 16px — tileset 64x16", .{});
        }
    } else |_| std.log.info("No tileset.png — sky fallback", .{});
    defer {
        if (tilemap_loaded) |*m| m.deinit();
        if (tileset_loaded) |*t| t.deinit();
    }

    // Demo ECS direct API retained
    var demo_reg = Zephyr.Registry.init(allocator);
    defer demo_reg.deinit();
    var demo_pos = Zephyr.SparseSet(Zephyr.ecs.Position).init(allocator);
    defer demo_pos.deinit();
    const demo_e = demo_reg.create();
    try demo_pos.add(demo_e, .{ .x = 10, .y = 20 });
    _ = try app.assets.load("assets/score.txt");

    var game = Game.init(allocator, rng, animator);
    defer game.deinit();
    // prevent double-free of animator (moved into game)
    animator = null;

    std.debug.print("Zephyr Core2D — Flappy + Animator + Tilemap + Camera (beat Scratch) | Controls: SPACE flap, R reset, Wheel zoom, Arrows pan\n", .{});

    while (!app.shouldClose()) {
        app.poll();
        if (app.win.isKeyDown(win32.VK_ESCAPE)) break;
        if (app.win.isKeyPressed(win32.VK_SPACE) or app.win.isKeyPressed(win32.VK_W) or app.win.isKeyPressed(win32.VK_UP)) {
            const was_dead = game.state == .dead;
            game.flap();
            if (!was_dead and flap_snd != null) audio.play(&flap_snd.?);
        }
        if (app.win.isKeyPressed(win32.VK_R)) game.reset();

        // Camera2D — Core2D beats Scratch: pan + zoom
        const wheel = app.win.wheelDelta();
        if (wheel != 0) {
            app.cam.zoom += @as(f32, @floatFromInt(wheel)) * 0.001;
            app.cam.zoom = std.math.clamp(app.cam.zoom, 0.5, 2.0);
        }
        if (app.win.isKeyDown(0x25)) app.cam.pos.x -= 2; // LEFT
        if (app.win.isKeyDown(0x27)) app.cam.pos.x += 2; // RIGHT
        if (app.win.isKeyDown(0x26)) app.cam.pos.y -= 2; // UP
        if (app.win.isKeyDown(0x28)) app.cam.pos.y += 2; // DOWN
        // uncomment to follow bird: app.cam.pos.y = game.bird_y - WH/2;

        const prev_score = game.score;
        const prev_state = game.state;
        const dt = app.tick();
        game.update(dt);
        if (game.score > prev_score and score_snd != null) audio.play(&score_snd.?);
        if (prev_state != .dead and game.state == .dead and hit_snd != null) audio.play(&hit_snd.?);

        {
            var tbuf: [128]u8 = undefined;
            const title = switch (game.state) {
                .ready => std.fmt.bufPrint(&tbuf, "Zephyr Core2D READY - Score {d} - cam {d:.1},{d:.1} zoom {d:.2}", .{ game.score, app.cam.pos.x, app.cam.pos.y, app.cam.zoom }) catch "Zephyr",
                .playing => std.fmt.bufPrint(&tbuf, "Zephyr Core2D Score {d} ECS:{d} cam zoom {d:.2}", .{ game.score, game.pipes.pipes.count(), app.cam.zoom }) catch "Zephyr",
                .dead => std.fmt.bufPrint(&tbuf, "Zephyr Core2D GAME OVER {d} - R/SPACE", .{game.score}) catch "Zephyr",
            };
            app.win.setTitle(title);
        }

        app.beginFrame(Color.sky);
        game.draw(&app.win, tilemap, tileset_tex);
        // Scratch-like direct API still works:
        // if (app.batchPtr()) |b| b.drawTexture(&tileset_loaded.?, 10, 10, 16, 16);
        app.endFrame();
        app.capFps(dt);
    }
}
