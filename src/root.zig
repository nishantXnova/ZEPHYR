//! Zephyr root — re-exports engine for @import("Zephyr") and @import("GAMEENGINE") compat
const std = @import("std");

pub const engine = @import("engine.zig");
pub const math = engine.math;
pub const color = engine.color;
pub const window = engine.window;
pub const win32 = engine.win32;
pub const time = engine.time;
pub const gl = engine.gl;
pub const batch = engine.batch;
pub const texture = engine.texture;
pub const shader = engine.shader;
pub const camera = engine.camera;
pub const ecs = engine.ecs;
pub const assets = engine.assets;
pub const audio = engine.audio;

pub const Vec2 = engine.Vec2;
pub const Rect = engine.Rect;
pub const Mat4 = engine.Mat4;
pub const Camera2D = engine.Camera2D;
pub const SpriteSheet = engine.SpriteSheet;
pub const Animator = engine.Animator;
pub const Tilemap = engine.Tilemap;
pub const Color = engine.Color;
pub const Window = engine.Window;
pub const WindowConfig = engine.WindowConfig;
pub const Clock = engine.Clock;
pub const Batch = engine.Batch;
pub const Texture = engine.Texture;
pub const Shader = engine.Shader;
pub const Registry = engine.Registry;
pub const SparseSet = engine.SparseSet;
pub const PipeSystem = engine.PipeSystem;
pub const Pipe = engine.Pipe;
pub const AssetManager = engine.AssetManager;
pub const AudioEngine = engine.AudioEngine;
pub const Sound = engine.Sound;
pub const Image = engine.Image;
pub const ScoreBoard = engine.ScoreBoard;
pub const Scene = engine.Scene;
pub const Spawn = engine.Spawn;
pub const Particle = engine.Particle;
pub const ParticleSystem = engine.ParticleSystem;
pub const Input = engine.Input;
pub const Action = engine.Action;
pub const Binding = engine.Binding;
pub const PhysicsWorld = engine.PhysicsWorld;
pub const PhysicsBody = engine.PhysicsBody;
pub const BodyType = engine.BodyType;
pub const Layer = engine.Layer;
pub const Profiler = engine.Profiler;
pub const Handle = engine.Handle;
pub const Cache = engine.Cache;
pub const Rollback = engine.Rollback;
pub const Transport = engine.Transport;
pub const Packet = engine.Packet;
pub const hashWorld = engine.hashWorld;
pub const Query2 = engine.Query2;
pub const Snapshot = engine.Snapshot;
pub const App = engine.App;

pub fn printAnotherMessage(writer: anytype) !void {
    try writer.print("Zephyr v0.2 — OpenGL + SpriteBatch + ECS + Hot-reload\n", .{});
}
