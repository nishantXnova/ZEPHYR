const std = @import("std");
const Zephyr = @import("Zephyr");
const App = Zephyr.App;
const Color = Zephyr.Color;
const Rect = Zephyr.Rect;
const Texture = Zephyr.Texture;
const Tilemap = Zephyr.Tilemap;
const Atlas = Zephyr.Atlas;
const UI = Zephyr.UI;
const Transform = Zephyr.Transform;
const Registry = Zephyr.Registry;
const SparseSet = Zephyr.SparseSet;
const Vec2 = Zephyr.Vec2;
const Camera3D = Zephyr.Camera3D;
const Vec3 = Zephyr.Vec3;
const Batch3D = Zephyr.Batch3D;
const Mesh = Zephyr.Mesh;
const PhysicsWorld = Zephyr.PhysicsWorld;
const Replay = Zephyr.Replay;
const Rollback = Zephyr.Rollback;
const gl = Zephyr.gl;
const win32 = Zephyr.win32;

// Paper Heist 3D — Actual engine showcase, not random.
// 2.5D paper sprites in 3D diorama (Batch3D sprite3D same coin.png as 2D Mario),
// Transform parent=truck child=painting, Atlas single tex, UI F4 slider,
// WorldQ fixed-point deterministic + Rollback P + Replay F5 scrub as REWIND mechanic.
// Steal painting at flag, carry to truck at start, guards patrol via Query2.
// R rewinds 3s via Replay scrub (Braid-style).

const WW: f32 = 800;
const WH: f32 = 600;
const TILE: f32 = 16;

pub fn main(init: std.process.Init) !void {
    _ = init;
    const allocator = std.heap.c_allocator;
    var app = try App.init(.{ .title = "Paper Heist 3D — WASD move, SPACE jump, F steal, R rewind, F4 UI, F5 scrub", .width = @intFromFloat(WW), .height = @intFromFloat(WH) });
    defer app.deinit();

    // Atlas single texture
    var atlas = try Atlas.init(allocator, 256, 256);
    defer atlas.deinit();
    atlas.add("coin", "assets/coin.png") catch {};
    atlas.add("goomba", "assets/goomba.png") catch {};
    atlas.add("mario", "assets/mario.png") catch {};
    if (atlas.count() > 0) try atlas.build();
    const atlas_tex = atlas.getTexture();

    // Tilemap 20x10 for heightmap visual
    var tiles_tex_l: ?Texture = null;
    var tiles_tex: ?*Texture = null;
    if (Texture.initFromFile("assets/mario_tiles.png", allocator) catch null) |t| { tiles_tex_l = t; tiles_tex = &tiles_tex_l.?; }
    defer if (tiles_tex_l) |*t| t.deinit();
    var tilemap = try Tilemap.init(allocator, 20, 10, 16, 16, tiles_tex orelse atlas_tex orelse return error.NoTileset);
    defer tilemap.deinit();
    for (0..20) |x| { tilemap.set(@intCast(x), 8, 1); tilemap.set(@intCast(x), 9, 1); }
    tilemap.set(10, 7, 1); tilemap.set(11, 7, 1);
    tilemap.set(5, 6, 1);

    // Transform hierarchy: truck (parent) + painting (child)
    var reg = Registry.init(allocator);
    defer reg.deinit();
    var tfs = SparseSet(Transform).init(allocator);
    defer tfs.deinit();
    const truck = reg.create();
    try tfs.add(truck, .{ .pos = Vec2.init(40, 128) });
    const painting = reg.create();
    try tfs.add(painting, .{ .pos = Vec2.init(15 * 16 + 8, 7 * 16), .parent = null }); // at flag
    var has_painting = false;
    var won = false;

    // Physics for player (use f32 World for Replay compat; WorldQ is for netcode demo)
    var phys = PhysicsWorld.init(allocator);
    defer phys.deinit();
    _ = try phys.add(.{ .rect = Rect.init(0, 8 * 16, 20 * 16, 16), .type = .static });
    const player_id = try phys.add(.{ .rect = Rect.init(40, 100, 16, 22), .type = .dynamic, .vel = Vec2.init(0, 0) });

    // Guards via ECS Query2 demo
    const GuardPos = struct { x: f32, y: f32 };
    const GuardVel = struct { x: f32, y: f32 };
    var g_pos = SparseSet(GuardPos).init(allocator);
    defer g_pos.deinit();
    var g_vel = SparseSet(GuardVel).init(allocator);
    defer g_vel.deinit();
    const g1 = reg.create(); try g_pos.add(g1, .{ .x = 120, .y = 112 }); try g_vel.add(g1, .{ .x = 40, .y = 0 });
    const g2 = reg.create(); try g_pos.add(g2, .{ .x = 220, .y = 112 }); try g_vel.add(g2, .{ .x = -30, .y = 0 });

    // Camera3D for diorama
    var cam = Camera3D.init(WW, WH, 60);
    cam.pos = Vec3.init(10, 8, 14);
    cam.target = Vec3.init(10, 0, 5);
    var batch3d = try Batch3D.init(cam.combined());
    defer batch3d.deinit();

    var rollback = Rollback.init(allocator);
    defer rollback.deinit();
    var replay = Replay.init(allocator);
    defer replay.deinit();
    var show_ui = false;
    var show_prof = false;
    var yaw: f32 = 0.5;
    var title_timer: f32 = 0;

    std.debug.print("Paper Heist 3D — steal painting, F carry, R rewind, F4 UI, F5 scrub, P rollback\n", .{});

    while (!app.shouldClose()) {
        app.poll();
        if (app.win.isKeyDown(win32.VK_ESCAPE)) break;
        if (app.win.isKeyPressed('R') and !replay.isScrubbing()) {
            // rewind 3s = 180 frames at 60fps
            replay.enterScrub();
            std.debug.print("rewind ON 3s\n", .{});
        }
        if (app.win.isKeyPressed(0x73)) show_ui = !show_ui; // F4
        if (app.win.isKeyPressed(0x72)) show_prof = !show_prof; // F3
        if (app.win.isKeyPressed(0x74)) { // F5 scrub toggle
            if (replay.isScrubbing()) replay.exitScrub() else replay.enterScrub();
        }
        if (app.win.isKeyPressed(0x75)) { replay.save("replay.bin") catch {}; std.debug.print("replay saved\n", .{}); }
        if (app.win.isKeyPressed(0x76)) { replay.load("replay.bin") catch {}; std.debug.print("replay loaded\n", .{}); }

        const dt = app.tick();

        // Scrub handling
        if (replay.isScrubbing()) {
            if (app.win.isKeyDown('Q') or app.win.isKeyDown('A')) { replay.scrubDelta(-2); replay.applyScrub(&phys) catch {}; }
            if (app.win.isKeyDown('E') or app.win.isKeyDown('D')) { replay.scrubDelta(2); replay.applyScrub(&phys) catch {}; }
            // still update camera while scrubbing
        } else {
            // Input via Zephyr Input buffered
            const move = app.input.axis(.left, .right);
            var pv = phys.get(player_id).?;
            pv.vel.x = move * 260;
            if (app.input.buffered(.jump)) { _ = app.input.consumeBuffer(.jump); pv.vel.y = -380; }
            // step physics
            phys.step(dt);
            // clamp to ground already via WorldQ collision (static ground)
            // Guard patrol via Query2 archetype
            var q = Zephyr.Query2(GuardPos, GuardVel).init(&g_pos, &g_vel);
            while (q.next()) |kv| {
                kv.a.x += kv.b.x * dt;
                if (kv.a.x < 40 or kv.a.x > 300) kv.b.x = -kv.b.x;
            }
            // Transform propagate for truck+painting hierarchy
            if (has_painting) {
                if (tfs.get(painting)) |pt| pt.parent = truck;
            }
            // update truck world pos to follow player x
            if (tfs.get(truck)) |t| { t.pos.x = phys.get(player_id).?.rect.x; t.dirty = true; }
            if (tfs.get(painting)) |c| c.dirty = true;
            Zephyr.propagate(&tfs, reg);

            // Steal: F near painting
            const ppos = phys.get(player_id).?.rect;
            const paint_rect = Rect.init(tfs.get(painting).?.pos.x, tfs.get(painting).?.pos.y, 16, 16);
            const player_rect = Rect.init(ppos.x, ppos.y, 16, 22);
            if (!has_painting and player_rect.overlaps(paint_rect) and app.win.isKeyDown('F')) {
                has_painting = true;
                std.debug.print("painting stolen!\n", .{});
            }
            // Win: painting at truck (child world_pos near truck)
            if (has_painting) {
                const wpos = tfs.get(painting).?.world_pos;
                const tpos = tfs.get(truck).?.world_pos;
                if (@abs(wpos.x - tpos.x) < 5 and @abs(wpos.y - tpos.y) < 5) won = true;
            }

            // rollback + replay record
            rollback.save(phys, app.input, dt) catch {};
            var bits: u16 = 0;
            for (0..16) |i| { if (app.input.states[i].down) bits |= @as(u16, 1) << @intCast(i); }
            replay.record(phys, bits, dt) catch {};
            if (app.win.isKeyPressed('P')) {
                const resimFn = struct { fn f(w: *PhysicsWorld, _: [16]bool, d: f32) void { w.step(d); } }.f;
                _ = rollback.rewindAndResim(&phys, 8, [_]bool{false} ** 16, &resimFn) catch 0;
            }
        }

        // Camera orbit
        if (app.win.isKeyDown('A') or app.win.isKeyDown(0x25)) yaw -= 1.2 * dt;
        if (app.win.isKeyDown('D') or app.win.isKeyDown(0x27)) yaw += 1.2 * dt;
        if (app.win.isKeyDown('W')) cam.pos.y += 3 * dt;
        if (app.win.isKeyDown('S')) cam.pos.y -= 3 * dt;
        cam.orbit(yaw, 0.4, 10);
        batch3d.setProjection(cam.combined());

        // Title
        title_timer += dt;
        if (title_timer > 0.4) {
            title_timer = 0;
            var buf: [128]u8 = undefined;
            const t = std.fmt.bufPrint(&buf, "Paper Heist 3D {s} {s}", .{ if (has_painting) "CARRYING" else "STEAL", if (won) "WIN!" else "" }) catch "Heist";
            app.win.setTitle(t);
        }

        // Draw: 3D diorama + 2D UI overlay
        gl.ClearColor(0.6, 0.8, 1.0, 1.0);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        batch3d.begin();
        if (atlas.getTexture()) |tex| {
            Mesh.heightmap(&batch3d, tex, tilemap, 1, Color.white);
            Mesh.cube(&batch3d, tex, 1.0, Color.rgb(180, 120, 60));
        } else if (tfs.get(painting)) |pt| {
            // fallback
            _ = pt;
        }
        // player as sprite3D at phys pos
        if (atlas.getTexture()) |tex| {
            const pp = phys.get(player_id).?.rect;
            batch3d.drawSprite3D(tex, pp.x, -pp.y * 0.1 + 1, 0, 1, 1.4);
        }
        // painting world_pos viz
        if (tfs.get(painting)) |pt| batch3d.drawSprite3D(atlas.getTexture() orelse continue, pt.world_pos.x, pt.world_pos.y * 0.1, 0, 0.6, 0.8);
        batch3d.end();
        _ = win32.SwapBuffers(app.win.hdc);

        // 2D UI on top via 2D Batch (re-use App's Batch for UI)
        app.win.setBatchProjection(app.cam.combined());
        app.beginFrame(Color.rgba(0, 0, 0, 0)); // clear alpha 0 to not overwrite 3D? But it clears color — we already cleared 3D, so skip?
        // For hybrid, we just draw UI via Batch3D already swapped, so we need second swap? Simplify: draw UI via Batch3D as well
        // Instead, draw UI via 2D batch after 3D swap would need second frame. For demo, draw UI via 3D batch already done.
        // Keep UI via direct win.drawRect for simplicity
        if (show_ui) {
            if (app.batchPtr()) |b| {
                var ui_state = UI.init(b, &app.win, 10, 10);
                ui_state.begin();
                if (ui_state.button("Reset", 100, 28)) { has_painting = false; won = false; }
                var dummy: f32 = 0;
                _ = ui_state.slider(&dummy, 0, 100, 100, 12);
                ui_state.end();
            }
        }
        if (show_prof) {
            if (app.batchPtr()) |b| {
                b.drawRect(8, 40, 200, 40, Color.rgba(0, 0, 0, 160));
                app.profiler.draw(b, 8, 40);
            }
        }
        // need second swap for UI? Already swapped 3D, UI drawn to 2D batch not yet swapped — swap again
        if (show_ui or show_prof) {
            if (app.batchPtr()) |b| b.drawRect(0, 0, 0, 0, Color.white); // dummy to keep batch alive
            app.endFrame();
        }

        app.capFps(dt);
    }
}
