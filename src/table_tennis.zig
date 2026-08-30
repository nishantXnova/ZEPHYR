const std = @import("std");
const Zephyr = @import("Zephyr");
const App = Zephyr.App;
const Color = Zephyr.Color;
const Rect = Zephyr.Rect;
const win32 = Zephyr.win32;

const WW: f32 = 800;
const WH: f32 = 600;
const PADDLE_W: f32 = 14;
const PADDLE_H: f32 = 90;
const BALL_S: f32 = 14;
const TABLE_H: f32 = 520; // green play area
const NET_W: f32 = 4;
const PADDLE_SPEED: f32 = 420;
const BALL_BASE: f32 = 260;

const Score = struct { left: u32 = 0, right: u32 = 0 };

const Paddle = struct {
    x: f32,
    y: f32,
    vy: f32 = 0,
    rect: Rect,
    fn init(x: f32, y: f32) Paddle {
        return .{ .x = x, .y = y, .rect = Rect.init(x, y, PADDLE_W, PADDLE_H) };
    }
    fn update(self: *Paddle, dt: f32) void {
        self.y += self.vy * dt;
        self.y = std.math.clamp(self.y, 20, TABLE_H - PADDLE_H - 10);
        self.rect = Rect.init(self.x, self.y, PADDLE_W, PADDLE_H);
    }
};

const Ball = struct {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    rect: Rect,
    fn init() Ball {
        return .{ .x = WW / 2 - BALL_S / 2, .y = WH / 2 - BALL_S / 2, .vx = BALL_BASE, .vy = BALL_BASE * 0.7, .rect = Rect.init(WW / 2, WH / 2, BALL_S, BALL_S) };
    }
    fn reset(self: *Ball, dir: f32) void {
        self.x = WW / 2 - BALL_S / 2;
        // simple random y offset without time API (Zig 0.16 has no nanoTimestamp)
        var prng = std.Random.DefaultPrng.init(@as(u64, @intFromFloat(self.x * 1000 + self.y)));
        const off = prng.random().float(f32) * 60 - 30;
        self.y = WH / 2 - BALL_S / 2 + off;
        const angle = prng.random().float(f32) * 0.6 - 0.3;
        self.vx = dir * BALL_BASE;
        self.vy = BALL_BASE * angle + if (dir > 0) @as(f32, 80) else @as(f32, -80);
        self.rect = Rect.init(self.x, self.y, BALL_S, BALL_S);
    }
    fn update(self: *Ball, dt: f32) void {
        self.x += self.vx * dt;
        self.y += self.vy * dt;
        self.rect = Rect.init(self.x, self.y, BALL_S, BALL_S);
        // top/bottom wall
        if (self.y <= 20) {
            self.y = 20;
            self.vy = @abs(self.vy);
        } else if (self.y + BALL_S >= TABLE_H - 10) {
            self.y = TABLE_H - 10 - BALL_S;
            self.vy = -@abs(self.vy);
        }
    }
};

fn paddleBounce(ball: *Ball, paddle: Paddle) void {
    // spin based on where ball hits paddle (Scratch-like, but precise)
    const hit = (ball.y + BALL_S / 2) - (paddle.y + PADDLE_H / 2);
    const norm = hit / (PADDLE_H / 2); // -1..1
    const speed = @sqrt(ball.vx * ball.vx + ball.vy * ball.vy) * 1.04;
    const angle = norm * 0.9; // max ~ 0.9 rad
    const dir: f32 = if (ball.vx < 0) 1 else -1;
    ball.vx = dir * @abs(@cos(angle) * speed);
    ball.vy = @sin(angle) * speed + paddle.vy * 0.3;
    // clamp
    if (@abs(ball.vx) < 180) ball.vx = if (ball.vx > 0) 180 else -180;
    if (@abs(ball.vx) > 520) ball.vx = if (ball.vx > 0) 520 else -520;
}

pub fn main(init: std.process.Init) !void {
    _ = init;
    const allocator = std.heap.c_allocator;
    _ = allocator;

    var app = try App.init(.{ .title = "Zephyr Table Tennis — W/S vs UP/DOWN, SPACE serve", .width = @intFromFloat(WW), .height = @intFromFloat(WH) });
    defer app.deinit();

    // Core2D: camera can follow ball slightly
    app.cam.zoom = 1.0;

    var left = Paddle.init(32, WH / 2 - PADDLE_H / 2);
    var right = Paddle.init(WW - 32 - PADDLE_W, WH / 2 - PADDLE_H / 2);
    var ball = Ball.init();
    var score = Score{};
    var serving: bool = true;
    var serve_dir: f32 = 1;
    var ai: bool = true; // right paddle AI when no input

    std.debug.print("Zephyr Table Tennis — W/S left, UP/DOWN right, SPACE serve, A toggle AI, R reset, ESC quit\n", .{});

    while (!app.shouldClose()) {
        app.poll();
        if (app.win.isKeyDown(win32.VK_ESCAPE)) break;
        if (app.win.isKeyPressed('R')) {
            score = .{};
            left.y = WH / 2 - PADDLE_H / 2;
            right.y = WH / 2 - PADDLE_H / 2;
            serving = true;
            ball.reset(serve_dir);
        }
        if (app.win.isKeyPressed('A')) ai = !ai;

        const dt = app.tick();

        // Controls — clean AI (fixed)
        left.vy = 0;
        if (app.win.isKeyDown('W')) left.vy = -PADDLE_SPEED;
        if (app.win.isKeyDown('S')) left.vy = PADDLE_SPEED;

        if (ai) {
            // AI right — aggressive when ball incoming, return to center when away
            if (serving) {
                const center = WH / 2 - PADDLE_H / 2;
                const diff = center - right.y;
                right.vy = std.math.clamp(diff * 4.0, -PADDLE_SPEED * 0.7, PADDLE_SPEED * 0.7);
            } else if (ball.vx > 0) {
                const target = ball.y + BALL_S / 2 - PADDLE_H / 2;
                const diff = target - right.y;
                // deadzone to avoid jitter
                if (@abs(diff) < 4) right.vy = 0 else right.vy = std.math.clamp(diff * 7.0, -PADDLE_SPEED, PADDLE_SPEED);
            } else {
                const center = WH / 2 - PADDLE_H / 2;
                const diff = center - right.y;
                right.vy = std.math.clamp(diff * 2.5, -PADDLE_SPEED * 0.6, PADDLE_SPEED * 0.6);
            }
        } else {
            right.vy = 0;
            if (app.win.isKeyDown(win32.VK_UP)) right.vy = -PADDLE_SPEED;
            if (app.win.isKeyDown(0x28)) right.vy = PADDLE_SPEED;
        }

        if (app.win.isKeyPressed(win32.VK_SPACE) and serving) {
            serving = false;
            ball.reset(serve_dir);
        }

        left.update(dt);
        right.update(dt);
        if (!serving) ball.update(dt);

        // scoring
        if (!serving) {
            if (ball.x + BALL_S < 0) {
                score.right += 1;
                serving = true;
                serve_dir = 1;
                ball.x = WW / 2 - BALL_S / 2;
                ball.y = WH / 2 - BALL_S / 2;
            } else if (ball.x > WW) {
                score.left += 1;
                serving = true;
                serve_dir = -1;
                ball.x = WW / 2 - BALL_S / 2;
                ball.y = WH / 2 - BALL_S / 2;
            }
        }

        // collisions — ECS-like AABB with spin
        if (!serving) {
            if (ball.rect.overlaps(left.rect) and ball.vx < 0) {
                ball.x = left.x + PADDLE_W + 1;
                paddleBounce(&ball, left);
            } else if (ball.rect.overlaps(right.rect) and ball.vx > 0) {
                ball.x = right.x - BALL_S - 1;
                paddleBounce(&ball, right);
            }
        }

        // camera: subtle follow ball
        // app.cam.pos.x = (ball.x - WW/2)*0.05;
        // app.win.setBatchProjection(app.cam.combined());

        // title
        {
            var tbuf: [128]u8 = undefined;
            const t = std.fmt.bufPrint(&tbuf, "Zephyr Table Tennis {d}-{d} {s} Ball {d:.0},{d:.0} {s}", .{ score.left, score.right, if (serving) "[SPACE]" else "", ball.x, ball.y, if (ai) "AI" else "2P" }) catch "Zephyr Pong";
            app.win.setTitle(t);
        }

        // draw — Core2D Batch
        app.beginFrame(Color.rgb(18, 18, 22));
        // table
        app.win.drawRect(0, 10, WW, TABLE_H - 10, Color.rgb(30, 80, 40));
        app.win.drawRect(0, 18, WW, 4, Color.white);
        app.win.drawRect(0, TABLE_H - 18, WW, 4, Color.white);
        // net dashed
        var ny: f32 = 22;
        while (ny < TABLE_H - 22) : (ny += 18) {
            app.win.drawRect(WW / 2 - NET_W / 2, ny, NET_W, 10, Color.white);
        }
        // paddles — Sprite-like but rect (pluggable to Texture)
        app.win.drawRect(left.x, left.y, PADDLE_W, PADDLE_H, Color.white);
        app.win.drawRect(left.x + 2, left.y + 2, PADDLE_W - 4, PADDLE_H - 4, Color.rgb(220, 220, 220));
        app.win.drawRect(right.x, right.y, PADDLE_W, PADDLE_H, Color.white);
        app.win.drawRect(right.x + 2, right.y + 2, PADDLE_W - 4, PADDLE_H - 4, Color.rgb(220, 220, 220));
        // ball
        if (serving) {
            // show ball at serve pos
            app.win.drawRect(ball.x - 1, ball.y - 1, BALL_S + 2, BALL_S + 2, Color.rgb(0, 0, 0));
        }
        app.win.drawRect(ball.x, ball.y, BALL_S, BALL_S, Color.yellow);
        app.win.drawRect(ball.x + 3, ball.y + 3, 4, 4, Color.white); // highlight
        // scores — rect backdrop
        app.win.drawRect(WW / 2 - 60, 30, 44, 28, Color.rgba(0, 0, 0, 90));
        app.win.drawRect(WW / 2 + 16, 30, 44, 28, Color.rgba(0, 0, 0, 90));
        app.win.drawRectOutline(WW / 2 - 60, 30, 44, 28, Color.white);
        app.win.drawRectOutline(WW / 2 + 16, 30, 44, 28, Color.white);
        // leg labels (just rects, no text — title shows score)
        // serve hint
        if (serving) {
            app.win.drawRectOutline(WW / 2 - 70, WH / 2 - 12, 140, 24, Color.white);
        }

        app.endFrame();
        app.capFps(dt);
    }
}
