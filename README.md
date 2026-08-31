# Zephyr — Lightweight 2D Engine in Zig

> **Extremely capable, zero bloat. From-scratch 2D engine in Zig 0.16.0 — Win32 + OpenGL 3.3, SpriteBatch, Tilemap, ECS, hot-reload. Ships Flappy Bird on day 1, any 2D game on day 30, beats Scratch in power while staying simpler than Unity.**

[![Zig 0.16.0](https://img.shields.io/badge/Zig-0.16.0-orange?logo=zig)](https://ziglang.org)
[![Platform](https://img.shields.io/badge/Platform-Windows%20x64-blue)](https://github.com/nishantXnova/ZEPHYR)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![Build](https://img.shields.io/badge/Build-zig%20build-brightgreen)](https://github.com/nishantXnova/ZEPHYR)

**Status:** `v0.5` — 6 shippable games, `OpenGL 3.3` `SpriteBatch` `Tilemap` `ParticleSystem` `Scene JSON` `Camera2D` `ECS` `Audio` `stb_image` — `zig build` ✅ `8-9 MB` exes, `60fps` stable. Full control, ultra lightweight, better than Scratch.

```
Flappy ─┐
Pong    ├─→ Zephyr (src/engine.zig:1) ─→ Platform (Win32 WGL) ─→ GFX (GL 3.3 + Batch + Particles)
Breakout┤         │          ├─ Core (math, time, color, camera, Scene JSON)
SpaceWar├─→ Games │          ├─ ECS (sparse-set) + Assets (hot-reload) + Audio (miniaudio)
Impact  │         └─→ GFX (Texture via stb_image, Shader, Tilemap, ScoreBoard)
Mario  ─┘
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

* **Lightweight:** `< 9K LOC` core, no hidden allocs, `Arena`/`GPA`, `60fps` on any laptop. `zig-out/bin/*.exe` `8 MB` Debug, `~600 KB` Release. Full control — you see `user32/gdi32/opengl32` `build.zig:29`.
* **Capable:** `SpriteBatch` (2048 quads, `drawTexture`/`drawQuad`), `ParticleSystem` (256 pooled `emitBurst/update/draw` `src/gfx/particle.zig:1`), `Scene JSON` (`Scene.loadJson` `src/core/scene.zig:38` + `Tilemap` culling), `Camera2D` (`Mat4.ortho`), `Tilemap` (Tiled JSON), `Texture` (`stb_image` PNG), `Shader` (`#version 330`), `ECS` (sparse-set), `AssetManager` (hot-reload), `AudioEngine` (`miniaudio`).
* **Zig-native:** `comptime` types, explicit `Allocator`, `callconv(.winapi)` `wndProc` `src/platform/window.zig:17` — you see the Win32.
* **Better than Scratch:** same `when flag clicked` simplicity (`App.init/poll/tick/beginFrame/endFrame`) but `Batch` `Animator` `Tilemap` `Particles` `Scene` — no clone spam, no GC, `O(1) swapRemove`.
* **Pluggable 2D→3D:** `Batch.drawQuad` `src/gfx/batch.zig:169` + `Mat4` `src/core/camera.zig:1` already 3D-ready.

**Philosophy:** Full control > black-box. Ultra lightweight > 3GB install. Scratch-simple API > Unity complexity.

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
| | `ScoreBoard` | `src/core/score_tilemap.zig:1` | `digits.png` `16×16` `draw(score)` via `Batch.drawTextureEx` |
| | `Sprite` | `src/gfx/sprite.zig:1` | `SpriteSheet {frame}` `Animation {frames,fps,loop}` `Animator {add,play,update,draw}` `Sprite` |
| | `Particles` | `src/gfx/particle.zig:1` | `ParticleSystem {emit,emitBurst,update,draw,cap 256 swapRemove}` `SpriteBatch` pooled |
| | `time` | `src/core/time.zig:1` | `Clock {QueryPerformanceCounter, tick() dt 0.001..0.033 EMA}` |
| **ECS** | `ecs` | `src/ecs/ecs.zig:1` | `Registry {create,destroy}`, `SparseSet(T) {add,get,has,remove}` `Position/Velocity` |
| | `pipe_ecs` | `src/ecs/pipe_ecs.zig:1` | `Pipe {x,gap_y}` `PipeSystem {update,checkCollision,draw}` |
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

### 6. Mario — `src/mario.zig:1` `Platformer + Engine Particles Demo`

`800×480` `GRAVITY 1400` `JUMP -480` `RUN 260` `src/mario.zig:15` `TILE 16` `100×15` `Tilemap 80×16 5 tiles` `src/mario.zig:73`. `mario.png 128×32 4 frames @10fps` `src/mario.zig:99` `SpriteSheet 32×32` `Animator idle/run/jump` + `ParticleSystem` `emitBurst 8 coin / 10 goomba` `src/mario.zig:271,289` `Engine v0.5`. `Camera2D` lerp `0.08` `src/mario.zig:304` pipes `src/mario.zig:91` flag `95*TILE`.

**Controls:** `LEFT/RIGHT A/D` move, `SHIFT` run `1.5×`, `SPACE/W/UP` jump, `R` reset, `ESC` quit. `zig build mario`.

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
    ├── root.zig           # re-exports engine (Scene/ParticleSystem NEW)
    ├── engine.zig         # App {win,clock,assets,cam,capFps,batchPtr} + Particle/Scene
    ├── main.zig           # Flappy + Animator + Tilemap
    ├── table_tennis.zig   # Pong + AI
    ├── breakout.zig       # Breakout + skins
    ├── spacewar.zig       # Space War 3D stars
    ├── starimpact.zig     # Star Impact auto-scroll
    ├── mario.zig          # Mario platformer + ParticleSystem demo NEW
    ├── core/
    │   ├── math.zig       # Vec2/Rect
    │   ├── camera.zig     # Mat4 + Camera2D
    │   ├── tilemap.zig    # Tilemap
    │   ├── scene.zig      # Scene JSON NEW
    │   ├── score_tilemap.zig # ScoreBoard
    │   └── time.zig       # Clock
    ├── gfx/
    │   ├── gl.zig         # loader
    │   ├── shader.zig     # vs/fs #330
    │   ├── texture.zig    # Texture
    │   ├── image.zig      # stbi_load
    │   ├── batch.zig      # Batch 2048 quads
    │   ├── sprite.zig     # SpriteSheet/Animator
    │   ├── particle.zig   # ParticleSystem NEW
    │   ├── color.zig      # Color
    │   ├── stb_image_impl.c
    │   └── ...
    ├── platform/
    │   ├── win32.zig      # bindings + WGL/PFD
    │   └── window.zig     # Window + Batch + WGL
    ├── ecs/
    │   ├── ecs.zig        # Registry/SparseSet
    │   └── pipe_ecs.zig   # PipeSystem
    ├── audio/
    │   ├── audio.zig      # AudioEngine
    │   └── miniaudio_impl.c
    └── assets/
        └── hotreload.zig  # AssetManager
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

// Camera
app.cam.pos.x = ship.x - WW/2; app.cam.zoom = 1.2; // auto in beginFrame
```

---

## Assets

Generate via `python` `PIL` (see `assets/`):

* `bird.png` `34×24`, `bird_sheet.png` `102×24` `3 frames`, `tileset.png` `64×16`, `level.json` `30×40`, `paddle_*.png` `64×90`, `digits.png` `192×16`, `bricks.png` `160×16`, `bg_table.png` `64×64`, `si_*.png` `ship 48` `meteor 64` `boss 128×96` `si_bg 128×128`, `*.wav` `laser/flap` `22050Hz`.

Add your own: `Texture.initFromFile("assets/my.png", alloc)` `src/gfx/texture.zig:28` handles `stb_image` `RGBA` `LINEAR`.

---

## Performance & Why Zig

* `swapRemove` not `orderedRemove` `src/starimpact.zig:268` `O(1)` + caps `particles>120` + `asteroids>30` — no lag after `10s` (was `Ship.lives` underflow panic `src/starimpact.zig:256` + `SetWindowTextW` `60/sec` heap `toWideZ` → throttled `0.4s` `src/starimpact.zig:275` + stack `buf[256]u16` `src/platform/window.zig:195`).
* `Clock` `EMA` `src/core/time.zig:27` + `capFps` `Sleep(ms-0.5)` `src/engine.zig:95`.
* `comptime` `Vec2/Rect`, explicit `Allocator` `Game.pipes` `src/main.zig:45`, no hidden `malloc`.

---

## Roadmap

* `v0.1` Flappy ✅ `v0.2` GL+Batch ✅ `v0.3` Tilemap/Sprite/Audio ✅ `v0.4` Core2D+5 games ✅
* `v0.5` Particles `src/gfx/particle.zig:1` ✅ + Scene JSON `src/core/scene.zig:1` ✅ + Mario `src/mario.zig:1` ✅ (Engine focus: full control, lightweight, better than Scratch)
* `v0.6` `3D` `Mesh` `drawQuad` `src/gfx/batch.zig:169` → `Mesh`, Editor `src/ui/panel.zig`, `WASM`

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
git commit -m "Zephyr v0.5: Engine ParticleSystem + Scene JSON + Mario — full control, ultra lightweight, better than Scratch"
git remote add origin https://github.com/nishantXnova/ZEPHYR.git
git branch -M main
git push -u origin main
```

`https://github.com/nishantXnova/ZEPHYR`

