# Zephyr — Lightweight 2D Engine in Zig

> **Undeniably good. Far beyond indie — extremely clever, robust engineering. From-scratch 2D engine in Zig 0.16.0 — Win32 + OpenGL 3.3, SpriteBatch, swept physics + spatial hash + snapshot, action input + buffering, generational handles, profiler, rollback 120f ring, UDP+Wyhash netcode. Full control, ultra lightweight, better than Scratch, better than indie.**

[![Zig 0.16.0](https://img.shields.io/badge/Zig-0.16.0-orange?logo=zig)](https://ziglang.org)
[![Platform](https://img.shields.io/badge/Platform-Windows%20x64-blue)](https://github.com/nishantXnova/ZEPHYR)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![Build](https://img.shields.io/badge/Build-zig%20build-brightgreen)](https://github.com/nishantXnova/ZEPHYR)

**Status:** `v0.8 NETCODE` — 6 shippable games, `OpenGL 3.3` `SpriteBatch` `PhysicsWorld snapshot` `Input 120f` `Handle generations` `Profiler` `ECS Query2` `Rollback 120f` `UDP Transport seq/ack/hash` `Wyhash desync` `ParticleSystem` `Scene JSON` — `zig build` ✅ `8-9 MB` exes, `60fps`, `--port/--peer/--loss/--latency`, `P rewind 8` localhost 2-window.

```
Flappy ─┐
Pong    ├─→ Zephyr (src/engine.zig:1) ─→ Platform (Win32 WGL) ─→ GFX (GL 3.3 + Batch + Particles)
Breakout┤         │          ├─ Core (math, time, color, camera, Scene JSON, Input 120f, Profiler)
SpaceWar├─→ Games │          ├─ Physics (swept 4× + hash CELL 64 + snapshot Wyhash) + Net (Rollback 120f + UDP seq/ack/hash)
Impact  │         ├─→ Engine ├─ ECS (sparse-set 4096 gen + Query2 + Snapshot) + Assets (Handle slab) + ws2_32
Mario  ─┘         │          └─ GFX/Audio (Texture stbi, Shader 330, Tilemap, ScoreBoard, miniaudio)
                 └─→ Undeniably Good ◄─ real UDP localhost 2-window, extremely clever
```

---

## Table of Contents

1. [What Is Zephyr?](#what-is-zephyr)
2. [Features](#features)
3. [Games — 5 Demos](#games)
4. [Quick Start](#quick-start)
5. [Architecture](#architecture)
6. [Engine API](#engine-api)
7. [Assets](#assets)
8. [Performance & Why Zig](#performance)
9. [Roadmap](#roadmap)
10. [Troubleshooting](#troubleshooting)
11. [Contributing](#contributing)
12. [License](#license)

---

## What Is Zephyr?

Not a wrapper around SDL. A **real engine** with its own window, renderer, math, and loop — all Zig, no C++.

* **Lightweight:** `< 11K LOC` core, no hidden allocs, `Arena`/`GPA`/`Cache(Handle)`, `60fps` on any laptop. `zig-out/bin/*.exe` `8 MB` Debug, `~600 KB` Release. Full control — you see `user32/gdi32/opengl32` `build.zig:29`.
* **Undeniably Good — Physics:** `PhysicsWorld` `src/physics/world.zig:1` swept AABB + 4× fixed sub-steps `dt/4` + spatial hash `CELL 64` `broadChecks/narrowChecks` — no tunneling at `600 fall`, `O(N) broadphase` not `O(N²)`, restitution/friction/layers.
* **Undeniably Good — Input:** `Input` `src/core/input.zig:1` action mapping `left/right/jump/run` → many bindings, `0.18s` buffer (coyote/jump queue Celeste-like), `axis/chord/sequence`, `120 frame history` replay, `held_time` — beats raw `isKeyDown`.
* **Undeniably Good — Handles:** `Cache(T)` `src/assets/handle.zig:1` generational slab `Handle(T){idx,gen}` — prevents use-after-free `gen bump`, `O(1) get`, typed `Handle(Texture)!=Handle(Sound)`.
* **Undeniably Good — Profiler:** `Profiler` `src/core/profiler.zig:1` `beginFrame/endFrame` `begin(name)/end` `QPC EMA`, `draw(batch)` `fps + scope bars` `F3` toggle — you SEE cost.
* **Capable:** `SpriteBatch` (2048 quads), `ParticleSystem` (256 pooled `src/gfx/particle.zig:1`), `Scene JSON` (`src/core/scene.zig:38`), `Camera2D`, `Tilemap`, `Texture` `stb_image`, `Shader` `330`, `ECS` `Query2 archetype` `Snapshot` `src/ecs/ecs.zig:142` `sparse-set 4096 gen`, `AssetManager` hot-reload, `Net Rollback 120f` `src/net/rollback.zig:1`, `AudioEngine` `miniaudio`.
* **Zig-native:** `comptime` types, explicit `Allocator`, `callconv(.winapi)` `wndProc` `src/platform/window.zig:17` — you see the Win32.
* **Better than Scratch & Indie:** same `when flag clicked` simplicity (`App.init/poll/tick/beginFrame/endFrame`) but `Batch` `Animator` `Tilemap` `Particles` `Scene` `Physics` `Input` `Profiler` — no clone spam, no GC, `O(1) swapRemove`, `no tunneling`.

**Philosophy:** Full control > black-box. Ultra lightweight > 3GB install. Extremely clever > naive. Robust > fragile. Scratch-simple API > Unity complexity.

---

## Features

| Layer | Module | File | What It Does |
|-------|--------|------|--------------|
| **Platform** | `Window` | `src/platform/window.zig:1` | `RegisterClassExW` `CreateWindowExW` `WGL` (`ChoosePixelFormat`/`wglCreateContext`/`SwapBuffers`) `src/platform/win32.zig:122`, `PeekMessageW`, `WM_KEYDOWN`/`WM_MOUSEMOVE`/`WM_MOUSEWHEEL`, `Batch` fallback to `GDI` `CreateCompatibleDC` |
| **Gfx** | `gl` | `src/gfx/gl.zig:1` | `wglGetProcAddress` loader for `3.3` core (`GenVertexArrays`, `CreateShader`, `TexImage2D`, `DrawElements`) |
| | `Shader` | `src/gfx/shader.zig:1` | `vs`/`fs` `#330` `uProj` `uTex`, `checkShader` logs |
| | `Texture` | `src/gfx/texture.zig:1` | `initWhite` `initFromRGBA` `initFromFile` via `Image` `src/gfx/image.zig:1` (`stbi_load` `vendor/stb_image.h:1`) |
| | `Batch` | `src/gfx/batch.zig:1` | `MAX_QUADS 2048` `VAO/VBO/EBO`, `begin`/`drawRect`/`drawTexture`/`drawTextureEx`/`drawQuad`/`flush` with `cur_tex` tracking, `proj` `Mat4` |
| | `Color` | `src/gfx/color.zig:1` | `rgb` `toBGR` `sky/pipe/yellow/ground` `white/black` |
| **Core** | `math` | `src/core/math.zig:1` | `Vec2 {add,sub,scale,length}`, `Rect {overlaps,contains}`, `Mat4`, `Camera2D` |
| | `Camera2D` | `src/core/camera.zig:1` | `Mat4.ortho` `translate` `scale` `mul`, `Camera2D {pos,zoom,combined}` |
| | `Tilemap` | `src/core/tilemap.zig:1` | `Tilemap {w,h,tile_w,tiles:GIDs,drawCamera(culling)}` `loadJson` |
| | `Scene` | `src/core/scene.zig:1` | `Scene {tilemap,spawns,bg,loadJson/parseJson}` `demo_scene.json` `20×10` spawns `kind 0..3` |
| | `Input` | `src/core/input.zig:1` | `Input {bind,update,axis,buffered,consumeBuffer,chord,sequence,120 frame history}` `buffer 0.18s` `combo 0.45s` |
| | `Profiler` | `src/core/profiler.zig:1` | `Profiler {beginFrame/endFrame,begin/end,scope,draw,stat fps/dt_ms}` `QPC EMA` `F3` overlay |
| | `ScoreBoard` | `src/core/score_tilemap.zig:1` | `digits.png` `16×16` `draw(score)` via `Batch.drawTextureEx` |
| | `Sprite` | `src/gfx/sprite.zig:1` | `SpriteSheet {frame}` `Animation {frames,fps,loop}` `Animator {add,play,update,draw}` `Sprite` |
| | `Particles` | `src/gfx/particle.zig:1` | `ParticleSystem {emit,emitBurst,update,draw,cap 256 swapRemove}` `SpriteBatch` pooled |
| | `time` | `src/core/time.zig:1` | `Clock {QueryPerformanceCounter, tick() dt 0.001..0.033 EMA}` |
| | `Physics` | `src/physics/world.zig:1` | `World {bodies,hits,step(dt) 4x,swept,hash CELL 64,snapshot/restore,snap deterministic}` `Body {rect,vel,type,layer,restitution}` |
| | `Handles` | `src/assets/handle.zig:1` | `Handle(T){idx,gen}` `Cache(T){insert/get/remove,isAlive,slab+free list}` `TextureHandle/SoundHandle` |
| | `Net` | `src/net/transport.zig:1` + `src/net/hash.zig:1` | `Transport {seq/ack/input/hash,loss/latency,Packet 18B LE}` `hashWorld Wyhash` per-frame desync detection `ws2_32` |
| **ECS** | `ecs` | `src/ecs/ecs.zig:1` | `Registry {create,destroy}`, `SparseSet(T) {add,get,has,remove}` `Query2(A,B) archetype` `Snapshot(T) capture/restore` `Position/Velocity` |
| | `pipe_ecs` | `src/ecs/pipe_ecs.zig:1` | `Pipe {x,gap_y}` `PipeSystem {update,checkCollision,draw}` |
| | `net` | `src/net/rollback.zig:1` | `Rollback {frames 120, save(world,input,dt), rewindAndResim(n,corrected,resimFn)}` `Physics Snap` `Input history` — nobody else has this |
| **Assets** | `hotreload` | `src/assets/hotreload.zig:1` | `AssetManager {load,isDirty,poll}` throttled `30` frames |
| **Audio** | `audio` | `src/audio/audio.zig:1` | `AudioEngine {ma_engine_init,loadSound,play,playOneShot}` `vendor/miniaudio.h:1` |

---

## Games

All `src/*.zig` `App.init` `Window` `Clock` `Batch` `60fps` `capFps`. Run via `zig build <name>`.

### 1. Flappy Bird — `src/main.zig:1` `Zephyr v0.5`

`480×640` `GRAVITY 1200` `FLAP -380` `src/main.zig:18` `PIPE 64×145` `SPEED 165` `src/ecs/pipe_ecs.zig:1` `ECS pipes`. `Animator` `bird_sheet.png` `102×24` `3 frames @12fps` `src/main.zig:170` `Tilemap 30×40` `tileset.png` `src/main.zig:190`. `Camera2D` pan `Arrows` zoom `Wheel` `src/main.zig:260`.

**Controls:** `SPACE/W/UP` flap, `R` reset, `ESC` quit. Title `Score`. `zig build run`.

### 2. Table Tennis — `src/table_tennis.zig:1`

`800×600` `PADDLE 14×90` `BALL 14` `src/table_tennis.zig:18` `PADDLE_SPEED 420` `BALL_BASE 260`. `PaddleBounce` `norm*0.9` `src/table_tennis.zig:70`. **AI** `right.vy = clamp(diff*7)` `src/table_tennis.zig:133` deadzone `4` (was broken duplicate `if (!ai)` `src/table_tennis.zig:125` fixed). Table `30,80,40` net dashed.

**Controls:** `W/S` left, `AI` right (default), `UP/DOWN` when `A` toggle `2P`, `SPACE` serve, `R` reset. `zig build pong`.

### 3. Breakout — `src/breakout.zig:1` `Paddle skins + Score Tilemap`

`800×600` `PADDLE 96×18` `BALL 16` `BRICK 32×16` `10×6` `src/breakout.zig:18`. `paddle_wood.png` `64×90` `assets/paddle_wood.png:1` `bricks.png` `160×16` `5 colors` `ball.png` `digits.png` `192×16` `ScoreBoard` `src/breakout.zig:82`. `Paddle` `A/D`/`LEFT/RIGHT`/mouse `src/breakout.zig:130` `ball.vx = norm*320` `src/breakout.zig:70`.

**Controls:** `A/D` `SPACE` launch. `zig build breakout`.

### 4. Space War — `src/spacewar.zig:1` `3D starfield forward`

`960×600` `SHIP 48` `ASTEROID 48` `src/spacewar.zig:18`. `150` stars `Star {x,y,z}` `src/spacewar.zig:116` perspective `fov 420 scale=fov/z` `src/spacewar.zig:333` `z -= (280+wave*12+thrust?120)*dt` recycle — whole dimension moving forward, streak `1.8×` when thrusting. `Ship {vx,vy,angle}` thrust `520` drag `0.995` `src/spacewar.zig:150` `lasers 8×20` `src/spacewar.zig:27` `explosion.png` `256×32` `8 frames` `src/spacewar.zig:384`.

**Controls:** `WASD` thrust/rotate, `SPACE` laser `0.13s`, `R` reset. `zig build spacewar`.

### 5. Star Impact — `src/starimpact.zig:1` `Auto forward-scrolling shooter`

`640×720` vertical `src/starimpact.zig:18` `SHIP 48` `ENEMY 32` `METEOR 64` `BOSS 128×96` `src/starimpact.zig:20`. Auto-scroll `scroll_speed 90+stage*12` `src/starimpact.zig:114` `bg` tiled `si_bg.png` `128×128` `src/starimpact.zig:283`. Fleets `V/line/diamond` `src/starimpact.zig:55` `meteors` `src/starimpact.zig:64` `boss hp 80+stage*30` `src/starimpact.zig:65` `power-ups` `weapon/health/shield` `src/starimpact.zig:21` `si_*.png` `assets/si_*.png:1`. `ScoreBoard` `src/starimpact.zig:97`.

**Controls:** `Arrows/WASD` move vertically + fire `SPACE` (weapon `1: single 0.18` `2: double 0.12` `3: triple 0.09` `src/starimpact.zig:135`), `R` reset. `zig build starimpact`. **Star Impact like:** auto-scroll, fleets, meteors, boss `hp bar`, upgrades.

### 6. Mario — `src/mario.zig:1` `Platformer + Engine v0.8 Netcode Demo`

`800×480` `GRAVITY 1400` `JUMP -480` `RUN 260` `src/mario.zig:15` `TILE 16` `100×15` `Tilemap 80×16` `mario.png 128×32 4 frames` `SpriteSheet 32×32` `Animator idle/run/jump` + `ParticleSystem` `Input buffered 0.18s + coyote 0.12s` `src/mario.zig:171` `PhysicsWorld ball snapshot` `Rollback P 8` `src/mario.zig:732` `Transport --port/--peer/--loss/--latency` + `hashWorld desync` `src/mario.zig:756` `Profiler F3`. Fix `73f008a` jump.

**Controls:** `LEFT/RIGHT A/D` `axis`, `SHIFT` run, `SPACE/W/UP` jump `buffered+coyote`, `P` rollback `8`, `F3` profiler, `R` reset, `ESC` quit. **Net 2-window:** `Mario.exe --port 9000 --peer 9001` + `Mario.exe --port 9001 --peer 9000 --loss 0.1 --latency 3` `UDP seq/ack/hash` `ws2_32` `src/net/transport.zig:1` `src/net/hash.zig:1`. `zig build mario -- --port 9000 --peer 9001`.

---

## Quick Start

```bat
# Requirements
winget install zig.zig --version 0.16.0
zig version  # 0.16.0

cd GAMEENGINE

# Flappy (default)
zig build run
# or
zig-out\bin\Zephyr.exe

# All games (6)
zig build pong        # Table Tennis 800x600
zig build breakout    # Breakout 800x600
zig build spacewar    # Space War 960x600
zig build starimpact  # Star Impact 640x720
zig build mario       # Mario 800x480 — NEW Engine ParticleSystem demo

# Tests + Release
zig build test
zig build -Doptimize=ReleaseFast  # ~600 KB
```

**First run note:** `info: Zephyr GL: 4.6.0 NVIDIA` `src/platform/window.zig:147` + `Loaded assets/bird.png` expected. `warning: audio init failed` is fine (no device in CI).

---

## Architecture

```
GAMEENGINE/
├── build.zig              # Zephyr + GAMEENGINE alias, links user32/gdi32/opengl32/winmm/ole32, vendor/, C files
├── build.zig.zon          # .name = .Zephyr, fingerprint
├── vendor/                # stb_image.h:1 (283K) + miniaudio.h:1 (4.1M)
├── assets/                # bird*.png, tileset.png, mario*.png, goomba/coin/cloud/flag.png, paddle_*.png, digits.png, si_*.png, demo_scene.json, *.wav
└── src/
    ├── root.zig           # re-exports engine (+Query2/Snapshot/Rollback NEW v0.7)
    ├── engine.zig         # App {win,clock,assets,cam,input,physics,profiler} + all modules
    ├── main.zig           # Flappy + Animator + Tilemap
    ├── table_tennis.zig   # Pong + AI
    ├── breakout.zig       # Breakout + skins
    ├── spacewar.zig       # Space War 3D stars
    ├── starimpact.zig     # Star Impact auto-scroll
    ├── mario.zig          # Mario + Physics/Input/Rollback/Profiler FIX jump buffered+coyote v0.7
    ├── core/
    │   ├── math.zig       # Vec2/Rect
    │   ├── camera.zig     # Mat4 + Camera2D
    │   ├── tilemap.zig    # Tilemap
    │   ├── scene.zig      # Scene JSON v0.5
    │   ├── input.zig      # Input buffered 120f v0.6
    │   ├── profiler.zig   # Profiler v0.6
    │   ├── score_tilemap.zig # ScoreBoard
    │   └── time.zig       # Clock
    ├── gfx/
    │   ├── gl.zig         # loader
    │   ├── shader.zig     # vs/fs #330
    │   ├── texture.zig    # Texture
    │   ├── image.zig      # stbi_load
    │   ├── batch.zig      # Batch 2048 quads
    │   ├── sprite.zig     # SpriteSheet/Animator
    │   ├── particle.zig   # ParticleSystem v0.5
    │   ├── color.zig      # Color
    │   ├── stb_image_impl.c
    │   └── ...
    ├── physics/
    │   └── world.zig      # PhysicsWorld swept+hash+snapshot v0.6/v0.7
    ├── platform/
    │   ├── win32.zig      # bindings + WGL/PFD
    │   └── window.zig     # Window + Batch + WGL
    ├── ecs/
    │   ├── ecs.zig        # Registry/SparseSet + Query2/Snapshot v0.7
    │   └── pipe_ecs.zig   # PipeSystem
    ├── net/
    │   └── rollback.zig   # Rollback 120f ring NEW v0.7
    ├── audio/
    │   ├── audio.zig      # AudioEngine
    │   └── miniaudio_impl.c
    └── assets/
        ├── hotreload.zig  # AssetManager
        └── handle.zig     # Cache(Handle) v0.6
```

**Key files:**
- `Window` `src/platform/window.zig:1` `wndProc` `initGL` `beginFrame` (GL `ClearColor`/`Batch.begin`) `endFrame` (`Batch.end`+`SwapBuffers`) `drawRect` `setTitle` stack `buf[256]u16`
- `Batch` `src/gfx/batch.zig:1` `VAO/VBO/EBO` `flushWith(cur_tex)` `drawRectUV`
- `Camera2D` `src/core/camera.zig:1` `ortho` `combined`
- `PipeSystem` `src/ecs/pipe_ecs.zig:1` `update` `checkCollision`
- `Clock` `src/core/time.zig:1` `EMA dt*0.9+0.016*0.1` clamp `0.001..0.033`

---

## Engine API

```zig
const Zephyr = @import("Zephyr");
const App = Zephyr.App;
const Color = Zephyr.Color;

// Window + loop
var app = try App.init(.{ .title = "Hello", .width = 800, .height = 600 });
defer app.deinit();
while (!app.shouldClose()) {
    app.poll();
    const dt = app.tick();
    app.beginFrame(Color.sky); // sets cam.proj
    app.win.drawRect(10,10,64,64, Color.red); // via Batch
    if (app.batchPtr()) |b| b.drawTexture(&tex, 10,10,64,64);
    app.endFrame();
    app.capFps(dt);
}

// Input
if (app.win.isKeyDown('W')) {}
if (app.win.isKeyPressed(win32.VK_SPACE)) {}
app.win.mousePos() // {x,y}
app.win.wheelDelta()

// Math
const r = Rect.init(x,y,w,h);
if (r.overlaps(other)) {}

// Sprite
var sheet = SpriteSheet.init(&tex, 34, 24);
var anim = Animator.init(alloc, sheet);
try anim.add(.{.name="flap", .frames=&.{0,1,2,1}, .fps=12});
anim.play("flap"); anim.update(dt); anim.draw(batch, x,y, Color.white);

// Tilemap
var tm = try Tilemap.init(alloc, 30,40,16,16, &tileset);
tm.set(x,y, gid); tm.drawCamera(batch, cam.x, cam.y, WW, WH);

// ECS
var reg = Registry.init(alloc);
var pos = SparseSet(Position).init(alloc);
const e = reg.create(); try pos.add(e, .{.x=10});

// Score
const sb = ScoreBoard{ .tex = &digits_tex, .x = WW-110, .y=12, .digits=5 };
sb.draw(batch, score);

// Particles — Engine v0.5 pooled, beats Scratch clones
var ps = ParticleSystem.init(alloc);
try ps.ensureCap(64);
ps.emitBurst(x, y, 8, Color.yellow, rng);
ps.update(dt); ps.draw(batch);

// Scene JSON — one file = one level
var scene = try Scene.loadJson(alloc, "assets/demo_scene.json", &tileset);
defer scene.deinit();
scene.draw(batch, cam.x, cam.y, WW, WH);

// Physics — Engine v0.6 swept + hash, no tunneling (indie-killer)
var phys = PhysicsWorld.init(alloc);
defer phys.deinit();
const ground = try phys.add(.{ .rect = Rect.init(0,400,800,32), .type = .static });
const ball = try phys.add(.{ .rect = Rect.init(100,0,16,16), .type = .dynamic, .vel = Vec2.init(80,0), .restitution = 0.6 });
phys.step(dt); // 4× sub-steps + spatial hash CELL 64
if (phys.get(ball)) |b| batch.drawRect(b.rect.x, b.rect.y, b.rect.w, b.rect.h, Color.blue);

// Input — Engine v0.6 buffered + coyote (fix 73f008a)
var input = Input.init(alloc);
defer input.deinit();
input.updateWindow(&app.win, dt);
if (input.buffered(.jump) and (grounded or coyote>0)) { _ = input.consumeBuffer(.jump); vel.y = JUMP; }
const move = input.axis(.left, .right); // -1..1
if (input.chord(.run, .jump)) { /* dash */ }

// ECS Query2 archetype — cache-friendly, picks smaller dense
var pos = SparseSet(Position).init(alloc);
var vel = SparseSet(Velocity).init(alloc);
var q = Query2(Position,Velocity).init(&pos,&vel);
while (q.next()) |e| e.a.x += e.b.x * dt;

// Rollback — 120f ring, P rewind 8
var rb = Rollback.init(alloc);
defer rb.deinit();
try rb.save(phys, input, dt);
if (isKeyPressed('P')) _ = try rb.rewindAndResim(&phys, 8, corrected, &resimFn);

// Handles — generational slab, no use-after-free
var cache = Cache(Texture).init(alloc);
const h = try cache.insert(tex);
if (cache.get(h)) |t| batch.drawTexture(t, 0,0,32,32);
_ = cache.remove(h); // gen bump — stale h rejected

// Profiler — F3 overlay, QPC EMA
var prof = Profiler.init();
prof.beginFrame(); const s = prof.begin("update"); /* ... */ prof.end(s); prof.endFrame();
prof.draw(batch, 8, 40);

// Camera
app.cam.pos.x = ship.x - WW/2; app.cam.zoom = 1.2; // auto in beginFrame
```

---

## Assets

Generate via `python` `PIL` (see `assets/`):

* `bird.png` `34×24`, `bird_sheet.png` `102×24` `3 frames`, `tileset.png` `64×16`, `level.json` `30×40`, `paddle_*.png` `64×90`, `digits.png` `192×16`, `bricks.png` `160×16`, `bg_table.png` `64×64`, `si_*.png` `ship 48` `meteor 64` `boss 128×96` `si_bg 128×128`, `*.wav` `laser/flap` `22050Hz`.

Add your own: `Texture.initFromFile("assets/my.png", alloc)` `src/gfx/texture.zig:28` handles `stb_image` `RGBA` `LINEAR`.

---

## Performance & Why Zig — Undeniably Good

* `PhysicsWorld` `src/physics/world.zig:1` 4× sub-steps `dt/4` + spatial hash `CELL 64` `snapshot/restore` deterministic `src/physics/world.zig:76` — no tunneling at `MAX_FALL 600` `src/mario.zig:18`, `O(N)` broadphase; test `physics no tunneling` + `snapshot deterministic` ✅
* `Rollback` `src/net/rollback.zig:1` `RING 120` `save` `rewindAndResim N` `P` `src/mario.zig:732` — fixed `dt` order, no alloc hot loop; test `save and rewind deterministic` ✅
* `Transport` `src/net/transport.zig:1` `UDP seq/ack/hash 18B LE` `ws2_32` `loss/latency` injection `pending` queue `confirmed watermark` never resim past it; test `packet roundtrip` ✅
* `hashWorld` `src/net/hash.zig:1` `Wyhash` over `bodies rect/vel` `per-frame desync detection` `stress 1000 same inputs` ✅ — first divergence flagged, trust vs demo
* `Query2` `src/ecs/ecs.zig:142` archetype picks smaller `dense` set `has` only — `Count 2/3` filtered cache-friendly vs naive all-entities scan
* `Input` `src/core/input.zig:1` `0.18s` buffer `combo 0.45s` `120 frame history` — Celeste coyote, deterministic replay — beats raw `isKeyDown`.
* `Cache(Handle)` `src/assets/handle.zig:1` generational slab `idx+gen` — stale `Handle` rejected, `O(1) get`, typed — no use-after-free `src/assets/handle.zig:100`.
* `Profiler` `src/core/profiler.zig:1` `QPC` `EMA 0.9/0.1` `begin/end` scopes `draw` `F3` — you SEE `broadChecks` `narrowChecks` `fps` `dt_ms` `src/mario.zig:356`.
* `ParticleSystem` `cap 256` `swapRemove` `src/gfx/particle.zig:1` + `StarImpact` caps `particles>120` `src/starimpact.zig:191` — no lag after `10s`.
* `swapRemove` not `orderedRemove` `src/starimpact.zig:268` `O(1)` + `Ship.lives` underflow fix `src/starimpact.zig:256` + `SetWindowTextW` throttled `0.4s` `src/starimpact.zig:275` `buf[256]u16` `src/platform/window.zig:229`.
* `Clock` `EMA` `src/core/time.zig:27` + `capFps` `Sleep(ms-0.5)` `src/engine.zig:101`.
* `comptime` `Vec2/Rect`, explicit `Allocator` `Game.pipes` `src/main.zig:45`, no hidden `malloc` — full control, ultra lightweight.

---

## Roadmap — Pushed to Limits

* `v0.1` Flappy ✅ `v0.2` GL+Batch ✅ `v0.3` Tilemap/Sprite/Audio ✅ `v0.4` Core2D+5 games ✅
* `v0.5` Particles `src/gfx/particle.zig:1` ✅ + Scene JSON `src/core/scene.zig:1` ✅ + Mario `src/mario.zig:1` ✅ (Engine: full control, lightweight, better than Scratch)
* `v0.6 INDIE-KILLER` ✅ Physics `src/physics/world.zig:1` swept+hash+snapshot ✅ + Input `src/core/input.zig:1` buffered ✅ + Handle `src/assets/handle.zig:1` generations ✅ + Profiler `src/core/profiler.zig:1` ✅ — **extremely clever, robust**
* `v0.7 ROLLBACK` ✅ Query2 `src/ecs/ecs.zig:142` ✅ + Snapshot `src/ecs/ecs.zig:190` ✅ + Rollback `src/net/rollback.zig:1` `120f` ✅ + Mario `P rewind 8` + jump fix `73f008a` ✅ — **nobody else has this**
* `v0.8 NETCODE` ✅ Transport `src/net/transport.zig:1` `UDP seq/ack/hash ws2_32` ✅ + hashWorld `src/net/hash.zig:1` `Wyhash desync` + `stress 1000` ✅ + Mario `--port/--peer/--loss/--latency` 2-window ✅ — **closes loop: local half → real netcode scaffold**
* `v0.9` `i32.16 fixed-point Physics`, Archetype chunk storage, Editor `F3` live tweak, Atlas `MSDF` — then `WASM`

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `zig: command not found` | Reopen shell after `winget`, `PATH` restart |
| `GetModuleHandleW not marked pub` | `pub extern` `src/platform/win32.zig:86` ✅ |
| `ArrayList init` | `.empty` + `append(alloc,item)` `src/main.zig:45` |
| `milliTimestamp` | Zig 0.16 removed — use `Clock` `src/core/time.zig:1` |
| `u0 shadows primitive` | Rename `u0` → `ux0` `src/gfx/batch.zig:133` |
| `file exists in modules` | Don't `@import("core/...")` in `src/*.zig` root — use `Zephyr.ScoreBoard` |
| `integer overflow lives` | `if (lives>0) lives-=1` `src/starimpact.zig:256` |

---

## Contributing

```bat
zig build test
zig fmt src/
# keep src/platform/window.zig:1 platform-abstracted
```

---

## License & Credits

* **Zephyr** `MIT` — `src/*.zig` `C:\Users\paude\OneDrive\Documents\QBASIC\GAMEENGINE` `fingerprint 0x20089aa4913ac215` `src/build.zig.zon:1`
* **Zig** `0.16.0` `ziglang.org`
* **Win32** `user32/gdi32/opengl32/winmm` OS
* **stb_image** `nothings/stb` `vendor/stb_image.h:1` `v2.30`
* **miniaudio** `mackron/miniaudio` `vendor/miniaudio.h:1` `v0.11.25`

> **Star Impact like:** `Arrows/WASD` vertical + `SPACE` fire, auto-scroll, fleets, meteors, boss `hp bar`, power-ups `weapon/health/shield` — all `src/starimpact.zig:1`.

---

## Push

```bat
cd GAMEENGINE
git init
git add .
git commit -m "Zephyr v0.7 ROLLBACK: Query2 + Snapshot + Rollback 120f + Mario P rewind 8 + jump fix — nobody else has this"
git remote add origin https://github.com/nishantXnova/ZEPHYR.git
git branch -M main
git push -u origin main
```

`https://github.com/nishantXnova/ZEPHYR`

