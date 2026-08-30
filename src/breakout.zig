const std = @import("std");
const Zephyr = @import("Zephyr");
const App = Zephyr.App;
const Color = Zephyr.Color;
const Rect = Zephyr.Rect;
const win32 = Zephyr.win32;
const Texture = Zephyr.Texture;
const ScoreBoard = Zephyr.ScoreBoard;

const WW: f32 = 800;
const WH: f32 = 600;
const PADDLE_W: f32 = 96;
const PADDLE_H: f32 = 18;
const BALL_S: f32 = 16;
const BRICK_W: f32 = 32;
const BRICK_H: f32 = 16;
const BRICK_COLS: u32 = 10;
const BRICK_ROWS: u32 = 6;
const BRICK_OFF_Y: f32 = 80;
const BRICK_OFF_X: f32 = (WW - @as(f32, @floatFromInt(BRICK_COLS)) * BRICK_W) / 2;

const Brick = struct {
    rect: Rect,
    hp: u32 = 1,
    alive: bool = true,
    color_idx: u32 = 0,
};

const GameState = enum { ready, playing, won, lost };

pub fn main(init: std.process.Init) !void {
    _ = init;
    const allocator = std.heap.c_allocator;

    var app = try App.init(.{ .title = "Zephyr Breakout — A/D or LEFT/RIGHT, SPACE launch", .width = @intFromFloat(WW), .height = @intFromFloat(WH) });
    defer app.deinit();

    // --- Textures: paddle skins + ball + bricks + digits (high quality) ---
    var paddle_tex_loaded: ?Texture = null;
    var paddle_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/paddle_wood.png", allocator) catch null) |t| {
        paddle_tex_loaded = t;
        paddle_tex = &paddle_tex_loaded.?;
        std.log.info("paddle_wood 64x90", .{});
    }
    defer if (paddle_tex_loaded) |*t| t.deinit();

    var ball_tex_loaded: ?Texture = null;
    var ball_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/ball.png", allocator) catch null) |t| {
        ball_tex_loaded = t;
        ball_tex = &ball_tex_loaded.?;
    }
    defer if (ball_tex_loaded) |*t| t.deinit();

    var bricks_tex_loaded: ?Texture = null;
    var bricks_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/bricks.png", allocator) catch null) |t| {
        bricks_tex_loaded = t;
        bricks_tex = &bricks_tex_loaded.?;
        std.log.info("bricks 160x16 5 colors", .{});
    }
    defer if (bricks_tex_loaded) |*t| t.deinit();

    var digits_tex_loaded: ?Texture = null;
    var digits_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/digits.png", allocator) catch null) |t| {
        digits_tex_loaded = t;
        digits_tex = &digits_tex_loaded.?;
        std.log.info("digits 192x16", .{});
    }
    defer if (digits_tex_loaded) |*t| t.deinit();

    var bg_tex_loaded: ?Texture = null;
    var bg_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/bg_table.png", allocator) catch null) |t| {
        bg_tex_loaded = t;
        bg_tex = &bg_tex_loaded.?;
    }
    defer if (bg_tex_loaded) |*t| t.deinit();

    const score_board = if (digits_tex) |tex| ScoreBoard{ .tex = tex, .x = WW - 110, .y = 12, .digits = 5 } else null;

    // Game state
    var paddle_x: f32 = WW / 2 - PADDLE_W / 2;
    const paddle_y: f32 = WH - 40;
    var ball_x: f32 = WW / 2 - BALL_S / 2;
    var ball_y: f32 = paddle_y - 28;
    var ball_vx: f32 = 220;
    var ball_vy: f32 = -260;
    var ball_stuck: bool = true;
    var score: u32 = 0;
    var lives: u32 = 3;
    var level: u32 = 1;
    var state: GameState = .ready;
    var bricks: [60]Brick = undefined;
    var brick_count: usize = 0;

    // Audio preloaded (pluggable, silent if no device)
    var audio = Zephyr.AudioEngine{ .engine = undefined };
    audio.init() catch {};
    defer audio.deinit();
    var hit_snd: ?Zephyr.Sound = if (audio.inited) audio.loadSound("assets/hit.wav", allocator) catch null else null;
    var score_snd: ?Zephyr.Sound = if (audio.inited) audio.loadSound("assets/score.wav", allocator) catch null else null;
    defer {
        if (hit_snd) |*s| audio.unload(s);
        if (score_snd) |*s| audio.unload(s);
    }

    const genBricks = struct {
        fn call(bricks_ptr: *[60]Brick, count: *usize, lvl: u32) void {
            count.* = 0;
            for (0..BRICK_ROWS) |r| for (0..BRICK_COLS) |c| {
                // pattern: every other brick empty on even levels for variety
                if (lvl % 2 == 0 and (r + c) % 3 == 0) continue;
                const x: f32 = BRICK_OFF_X + @as(f32, @floatFromInt(c)) * BRICK_W;
                const y: f32 = BRICK_OFF_Y + @as(f32, @floatFromInt(r)) * BRICK_H;
                const hp: u32 = if (r < 2) 2 else 1;
                const col: u32 = @intCast(r % 5);
                bricks_ptr[count.*] = .{ .rect = Rect.init(x, y, BRICK_W - 2, BRICK_H - 2), .hp = hp, .alive = true, .color_idx = col };
                count.* += 1;
            };
        }
    }.call;
    genBricks(&bricks, &brick_count, level);

    std.debug.print("Zephyr Breakout — A/D or LEFT/RIGHT move, SPACE launch, R reset, ESC quit | Paddle skins + Score Tilemap | Level {d}\n", .{level});

    while (!app.shouldClose()) {
        app.poll();
        if (app.win.isKeyDown(win32.VK_ESCAPE)) break;
        if (app.win.isKeyPressed('R')) {
            paddle_x = WW / 2 - PADDLE_W / 2;
            ball_x = WW / 2 - BALL_S / 2;
            ball_y = paddle_y - 28;
            ball_vx = 220; ball_vy = -260;
            ball_stuck = true; score = 0; lives = 3; level = 1; state = .ready;
            genBricks(&bricks, &brick_count, level);
        }

        const dt = app.tick();
        const paddle_speed: f32 = 520;

        // Input — Core2D beats Scratch: no block delay
        var move: f32 = 0;
        if (app.win.isKeyDown('A') or app.win.isKeyDown(0x25)) move -= 1; // A or LEFT
        if (app.win.isKeyDown('D') or app.win.isKeyDown(0x27)) move += 1; // D or RIGHT
        // mouse follow
        const mp = app.win.mousePos();
        const mouse_target = @as(f32, @floatFromInt(mp.x)) - PADDLE_W / 2;
        if (app.win.isMouseDown(0)) {
            // drag with mouse when holding
            paddle_x += (mouse_target - paddle_x) * 0.25;
        } else {
            paddle_x += move * paddle_speed * dt;
        }
        paddle_x = std.math.clamp(paddle_x, 0, WW - PADDLE_W);

        if (app.win.isKeyPressed(win32.VK_SPACE) and ball_stuck and state != .lost and state != .won) {
            ball_stuck = false;
            state = .playing;
            ball_vx = (if (move != 0) move * 120 else 0) + 180;
            ball_vy = -280;
        }

        // update ball
        if (!ball_stuck and state == .playing) {
            ball_x += ball_vx * dt;
            ball_y += ball_vy * dt;
            // walls
            if (ball_x <= 0) { ball_x = 0; ball_vx = @abs(ball_vx); if (hit_snd) |*s| audio.play(s); }
            if (ball_x + BALL_S >= WW) { ball_x = WW - BALL_S; ball_vx = -@abs(ball_vx); if (hit_snd) |*s| audio.play(s); }
            if (ball_y <= 20) { ball_y = 20; ball_vy = @abs(ball_vy); if (hit_snd) |*s| audio.play(s); }
            // paddle
            const paddle_rect = Rect.init(paddle_x, paddle_y, PADDLE_W, PADDLE_H);
            const ball_rect = Rect.init(ball_x, ball_y, BALL_S, BALL_S);
            if (ball_rect.overlaps(paddle_rect) and ball_vy > 0) {
                ball_y = paddle_y - BALL_S - 1;
                const hit = (ball_x + BALL_S / 2) - (paddle_x + PADDLE_W / 2);
                const norm = hit / (PADDLE_W / 2);
                ball_vx = norm * 320 + move * 80;
                ball_vy = -@abs(ball_vy);
                if (ball_vx == 0) ball_vx = 40;
                if (hit_snd) |*s| audio.play(s);
            }
            // bricks — Tilemap ECS-style
            for (bricks[0..brick_count]) |*b| if (b.alive) {
                if (ball_rect.overlaps(b.rect)) {
                    // determine side
                    const overlap_left = (ball_x + BALL_S) - b.rect.x;
                    const overlap_right = (b.rect.x + b.rect.w) - ball_x;
                    const overlap_top = (ball_y + BALL_S) - b.rect.y;
                    const overlap_bottom = (b.rect.y + b.rect.h) - ball_y;
                    const min_x = @min(overlap_left, overlap_right);
                    const min_y = @min(overlap_top, overlap_bottom);
                    if (min_x < min_y) ball_vx = -ball_vx else ball_vy = -ball_vy;
                    if (b.hp > 1) b.hp -= 1 else b.alive = false;
                    score += 10 * level;
                    if (score_snd) |*s| audio.play(s);
                    break; // one brick per frame
                }
            };
            // fall
            if (ball_y > WH + 20) {
                lives -= 1;
                if (lives == 0) state = .lost else {
                    ball_stuck = true;
                    ball_x = paddle_x + PADDLE_W / 2 - BALL_S / 2;
                    ball_y = paddle_y - 28;
                    state = .ready;
                }
            }
            // win level
            var any_alive = false;
            for (bricks[0..brick_count]) |br| {
                if (br.alive) { any_alive = true; break; }
            }
            if (!any_alive) {
                level += 1;
                genBricks(&bricks, &brick_count, level);
                ball_stuck = true;
                ball_x = paddle_x + PADDLE_W / 2 - BALL_S / 2;
                ball_y = paddle_y - 28;
                state = .ready;
            }
        } else if (ball_stuck) {
            ball_x = paddle_x + PADDLE_W / 2 - BALL_S / 2;
            ball_y = paddle_y - 28;
        }

        // title
        {
            var tbuf: [128]u8 = undefined;
            const t = std.fmt.bufPrint(&tbuf, "Zephyr Breakout Lvl {d} Score {d} Lives {d} {s}", .{ level, score, lives, if (ball_stuck) "[SPACE]" else "" }) catch "Zephyr Breakout";
            app.win.setTitle(t);
        }

        // draw
        app.beginFrame(Color.rgb(12, 12, 18));
        // bg tiled
        if (bg_tex) |tex| {
            if (app.batchPtr()) |b| {
                var y: f32 = 0;
                while (y < WH) : (y += 64) {
                    var x: f32 = 0;
                    while (x < WW) : (x += 64) {
                        b.drawTexture(tex, x, y, 64, 64);
                    }
                }
            }
        }
        // bricks via tileset (or color rects fallback)
        for (bricks[0..brick_count]) |br| if (br.alive) {
            if (bricks_tex) |tex| {
                if (app.batchPtr()) |b| {
                    const sx: f32 = @as(f32, @floatFromInt(br.color_idx)) * 32;
                    // hp 2 = brighter, hp1 = normal
                    const tint = if (br.hp == 2) Color.white else Color.rgb(220, 220, 220);
                    b.drawTextureEx(tex, br.rect.x, br.rect.y, br.rect.w, br.rect.h, sx, 0, 32, 16, tint);
                    continue;
                }
            }
            const cols = [_]Color{ Color.rgb(200, 40, 40), Color.rgb(40, 160, 40), Color.rgb(40, 80, 200), Color.rgb(220, 180, 40), Color.rgb(160, 40, 160) };
            app.win.drawRect(br.rect.x, br.rect.y, br.rect.w, br.rect.h, cols[br.color_idx % cols.len]);
            app.win.drawRect(br.rect.x, br.rect.y, br.rect.w, 4, Color.rgba(255, 255, 255, 70));
        };
        // paddle — textured skin
        if (paddle_tex) |tex| {
            if (app.batchPtr()) |b| b.drawTexture(tex, paddle_x, paddle_y, PADDLE_W, PADDLE_H);
        } else app.win.drawRect(paddle_x, paddle_y, PADDLE_W, PADDLE_H, Color.white);
        // ball — textured
        if (ball_tex) |tex| {
            if (app.batchPtr()) |b| b.drawTexture(tex, ball_x, ball_y, BALL_S, BALL_S);
        } else app.win.drawRect(ball_x, ball_y, BALL_S, BALL_S, Color.yellow);

        // score tilemap UI — beats Scratch variable display
        if (score_board) |sb| {
            if (app.batchPtr()) |b| sb.draw(b, score);
            // lives as small paddles
            for (0..lives) |i| {
                const lx: f32 = 12 + @as(f32, @floatFromInt(i)) * 20;
                app.win.drawRect(lx, 14, 14, 6, Color.white);
            }
        } else {
            app.win.drawRect(WW - 100, 12, 80, 20, Color.rgba(0, 0, 0, 90));
        }

        if (state == .ready and ball_stuck) {
            app.win.drawRectOutline(WW / 2 - 90, WH / 2 - 10, 180, 20, Color.white);
        } else if (state == .lost) {
            app.win.drawRect(WW / 2 - 80, WH / 2 - 20, 160, 40, Color.rgba(0, 0, 0, 150));
            app.win.drawRectOutline(WW / 2 - 80, WH / 2 - 20, 160, 40, Color.red);
        }

        app.endFrame();
        app.capFps(dt);
    }
}
