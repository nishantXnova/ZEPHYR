const std = @import("std");
const Zephyr = @import("Zephyr");
const App = Zephyr.App;
const Color = Zephyr.Color;
const Camera3D = Zephyr.Camera3D;
const Vec3 = Zephyr.Vec3;
const Batch3D = Zephyr.Batch3D;
const Mesh = Zephyr.Mesh;
const Texture = Zephyr.Texture;
const gl = Zephyr.gl;
const win32 = Zephyr.win32;

pub fn main(init: std.process.Init) !void {
    _ = init;
    const allocator = std.heap.c_allocator;
    var app = try App.init(.{ .title = "Zephyr 3D — WASD orbit, Q/E zoom, R reset | Batch3D hybrid", .width = 800, .height = 600 });
    defer app.deinit();

    var tex_l: ?Texture = null;
    var tex: ?*Texture = null;
    if (Texture.initFromFile("assets/coin.png", allocator) catch null) |t| { tex_l = t; tex = &tex_l.?; }
    defer if (tex_l) |*t| t.deinit();
    var white_l: ?Texture = null;
    if (tex == null) { white_l = try Texture.initWhite(); tex = &white_l.?; }
    defer if (white_l) |*t| t.deinit();

    var cam = Camera3D.init(800, 600, 60);
    cam.pos = Vec3.init(4, 3, 6);
    cam.target = Vec3.init(0, 0, 0);
    var batch3d = try Batch3D.init(cam.combined());
    defer batch3d.deinit();

    var yaw: f32 = 0.6;
    var pitch: f32 = 0.3;
    var dist: f32 = 6;

    std.debug.print("Zephyr 3D — Hybrid Batch3D 800x600 | WASD orbit Q/E zoom R reset\n", .{});

    while (!app.shouldClose()) {
        app.poll();
        if (app.win.isKeyDown(0x1B)) break;
        if (app.win.isKeyPressed('R')) { yaw = 0.6; pitch = 0.3; dist = 6; }

        const dt = app.tick();
        if (app.win.isKeyDown('A') or app.win.isKeyDown(0x25)) yaw -= 1.2 * dt;
        if (app.win.isKeyDown('D') or app.win.isKeyDown(0x27)) yaw += 1.2 * dt;
        if (app.win.isKeyDown('W') or app.win.isKeyDown(0x26)) pitch += 1.0 * dt;
        if (app.win.isKeyDown('S') or app.win.isKeyDown(0x28)) pitch -= 1.0 * dt;
        pitch = std.math.clamp(pitch, -1.3, 1.3);
        if (app.win.isKeyDown('Q')) dist += 3 * dt;
        if (app.win.isKeyDown('E')) dist -= 3 * dt;
        dist = std.math.clamp(dist, 2, 12);
        cam.orbit(yaw, pitch, dist);
        cam.aspect = 800.0 / 600.0;
        batch3d.setProjection(cam.combined());

        gl.ClearColor(0.53, 0.81, 0.92, 1.0);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        batch3d.begin();
        if (tex) |t| Mesh.plane(&batch3d, t, 10, 10, Color.rgb(40, 80, 40));
        if (tex) |t| Mesh.cube(&batch3d, t, 1.5, Color.white);
        if (tex) |t| batch3d.drawSprite3D(t, -2, 1, 0, 1, 1);
        if (tex) |t| batch3d.drawSprite3D(t, 2, 1, 0, 1, 1);
        batch3d.end();
        _ = win32.SwapBuffers(app.win.hdc);
        app.capFps(dt);
    }
}
