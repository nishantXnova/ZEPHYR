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
pub const particle = @import("gfx/particle.zig");
pub const scene = @import("core/scene.zig");
pub const input = @import("core/input.zig");
pub const physics = @import("physics/world.zig");
pub const handle = @import("assets/handle.zig");
pub const profiler = @import("core/profiler.zig");
pub const rollback = @import("net/rollback.zig");
pub const transport = @import("net/transport.zig");
pub const hash = @import("net/hash.zig");
pub const replay = @import("core/replay.zig");
pub const transform = @import("core/transform.zig");
pub const atlas = @import("gfx/atlas.zig");
pub const ui = @import("ui/ui.zig");
pub const camera3d = @import("core/camera3d.zig");
pub const batch3d = @import("gfx/batch3d.zig");
pub const mesh = @import("gfx/mesh.zig");
pub const fixed = @import("physics/fixed.zig");
pub const world_fixed = @import("physics/world_fixed.zig");
pub const editor = @import("editor/editor.zig");

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
pub const Scene = scene.Scene;
pub const Spawn = scene.Spawn;
pub const Particle = particle.Particle;
pub const ParticleSystem = particle.ParticleSystem;
pub const Input = input.Input;
pub const Action = input.Action;
pub const Binding = input.Binding;
pub const PhysicsWorld = physics.World;
pub const PhysicsBody = physics.Body;
pub const BodyType = physics.BodyType;
pub const Layer = physics.Layer;
pub const Profiler = profiler.Profiler;
pub const Handle = handle.Handle;
pub const Cache = handle.Cache;
pub const Rollback = rollback.Rollback;
pub const Transport = transport.Transport;
pub const Packet = transport.Packet;
pub const hashWorld = hash.hashWorld;
pub const Replay = replay.Replay;
pub const Transform = transform.Transform;
pub const propagate = transform.propagate;
pub const Atlas = atlas.Atlas;
pub const UI = ui.UI;
pub const Editor = editor.Editor;
pub const Inspector = editor.Inspector;
pub const Camera3D = camera3d.Camera3D;
pub const Vec3 = camera3d.Vec3;
pub const Batch3D = batch3d.Batch3D;
pub const Mesh = mesh.Mesh;
pub const Q16 = fixed.Q16;
pub const VecQ = fixed.VecQ;
pub const RectQ = fixed.RectQ;
pub const WorldQ = world_fixed.WorldQ;
pub const Query2 = ecs.Query2;
pub const Snapshot = ecs.Snapshot;
pub const ScoreBoard = @import("core/score_tilemap.zig").ScoreBoard;

pub fn aabbOverlaps(a: Rect, b: Rect) bool {
    return a.overlaps(b);
}

pub const App = struct {
    win: Window,
    clock: Clock,
    assets: AssetManager,
    cam: Camera2D,
    input: Input,
    physics: PhysicsWorld,
    profiler: Profiler,
    target_fps: f32 = 60,

    pub fn init(cfg: WindowConfig) !App {
        var w = try Window.init(cfg);
        const c = Clock.init();
        const am = AssetManager.init(std.heap.c_allocator);
        var cam = Camera2D.init(@floatFromInt(w.width), @floatFromInt(w.height));
        const inp = Input.init(std.heap.c_allocator);
        const phys = PhysicsWorld.init(std.heap.c_allocator);
        const prof = Profiler.init();
        // set batch projection to camera
        w.setBatchProjection(cam.combined());
        return .{ .win = w, .clock = c, .assets = am, .cam = cam, .input = inp, .physics = phys, .profiler = prof };
    }
    pub fn deinit(self: *App) void {
        self.input.deinit();
        self.physics.deinit();
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
        const dt = self.clock.tick();
        self.input.updateWindow(&self.win, dt);
        self.profiler.tick(dt);
        return dt;
    }
    pub fn beginFrame(self: *App, clear_color: Color) void {
        // update camera -> batch proj (pluggable 2D→3D)
        self.profiler.beginFrame();
        self.win.setBatchProjection(self.cam.combined());
        self.win.beginFrame(clear_color);
    }
    pub fn setCameraPos(self: *App, x: f32, y: f32) void {
        self.cam.pos.x = x;
        self.cam.pos.y = y;
    }
    pub fn endFrame(self: *App) void {
        self.profiler.endFrame();
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
