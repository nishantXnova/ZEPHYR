//! Zephyr — lightweight 2D engine, pluggable 2D→3D.

const std = @import("std");

pub const math = @import("core/math.zig");
pub const time = @import("core/time.zig");
pub const color = @import("gfx/color.zig");
pub const gl = @import("gfx/gl.zig");
pub const shader = @import("gfx/shader.zig");
pub const texture = @import("gfx/texture.zig");
pub const batch = @import("gfx/batch.zig");
pub const camera = @import("core/camera.zig");
pub const window = @import("platform/window.zig");
pub const win32 = @import("platform/win32.zig");
pub const ecs = @import("ecs/ecs.zig");
pub const pipe_ecs = @import("ecs/pipe_ecs.zig");
pub const assets = @import("assets/hotreload.zig");
pub const audio = @import("audio/audio.zig");
pub const image = @import("gfx/image.zig");
pub const sprite = @import("gfx/sprite.zig");
pub const tilemap = @import("core/tilemap.zig");

pub const Vec2 = math.Vec2;
pub const Rect = math.Rect;
pub const Mat4 = camera.Mat4;
pub const Camera2D = camera.Camera2D;
pub const Color = color.Color;
pub const Window = window.Window;
pub const WindowConfig = window.WindowConfig;
pub const Clock = time.Clock;
pub const Batch = batch.Batch;
pub const Texture = texture.Texture;
pub const Shader = shader.Shader;
pub const Registry = ecs.Registry;
pub const SparseSet = ecs.SparseSet;
pub const PipeSystem = pipe_ecs.PipeSystem;
pub const Pipe = pipe_ecs.Pipe;
pub const AssetManager = assets.AssetManager;
pub const AudioEngine = audio.AudioEngine;
pub const Sound = audio.Sound;
pub const Image = image.Image;
pub const SpriteSheet = sprite.SpriteSheet;
pub const Animator = sprite.Animator;
pub const Animation = sprite.Animation;
pub const Sprite = sprite.Sprite;
pub const Tilemap = tilemap.Tilemap;
pub const ScoreBoard = @import("core/score_tilemap.zig").ScoreBoard;

pub fn aabbOverlaps(a: Rect, b: Rect) bool {
    return a.overlaps(b);
}

pub const App = struct {
    win: Window,
    clock: Clock,
    assets: AssetManager,
    cam: Camera2D,
    target_fps: f32 = 60,

    pub fn init(cfg: WindowConfig) !App {
        var w = try Window.init(cfg);
        const c = Clock.init();
        const am = AssetManager.init(std.heap.c_allocator);
        var cam = Camera2D.init(@floatFromInt(w.width), @floatFromInt(w.height));
        // set batch projection to camera
        w.setBatchProjection(cam.combined());
        return .{ .win = w, .clock = c, .assets = am, .cam = cam };
    }
    pub fn deinit(self: *App) void {
        self.assets.deinit();
        self.win.deinit();
    }
    pub fn shouldClose(self: *App) bool {
        return self.win.shouldClose();
    }
    pub fn poll(self: *App) void {
        self.win.poll();
        _ = self.assets.poll();
    }
    pub fn tick(self: *App) f32 {
        return self.clock.tick();
    }
    pub fn beginFrame(self: *App, clear_color: Color) void {
        // update camera -> batch proj (pluggable 2D→3D)
        self.win.setBatchProjection(self.cam.combined());
        self.win.beginFrame(clear_color);
    }
    pub fn setCameraPos(self: *App, x: f32, y: f32) void {
        self.cam.pos.x = x;
        self.cam.pos.y = y;
    }
    pub fn endFrame(self: *App) void {
        self.win.endFrame();
    }
    pub fn capFps(self: *App, dt: f32) void {
        const target_dt: f32 = 1.0 / self.target_fps;
        if (dt < target_dt) {
            const ms: f32 = (target_dt - dt) * 1000.0;
            if (ms > 1.5) self.win.sleep(@intFromFloat(ms - 0.5));
        }
    }
    // Expose batch for direct use (pluggable 2D→3D)
    pub fn batchPtr(self: *App) ?*Batch {
        if (self.win.batch) |*b| return b;
        return null;
    }
};
