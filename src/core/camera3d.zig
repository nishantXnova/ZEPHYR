const std = @import("std");
const Mat4 = @import("camera.zig").Mat4;

// Zephyr Camera3D v2.0 — Novel hybrid, pluggable with Batch3D. Not traditional scene graph.
// One Camera3D + one Batch3D = 60fps 3D with same App loop as 2D Camera2D. Lightweight ~80 LOC.
// Uses Mat4.perspective reusing same Batch shader uniform uProj — 2D ortho and 3D perspective
// are just different Mat4s, proving pluggable 2D→3D claim from day 1.

pub const Vec3 = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    pub fn init(x: f32, y: f32, z: f32) Vec3 { return .{ .x = x, .y = y, .z = z }; }
    pub fn add(a: Vec3, b: Vec3) Vec3 { return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z }; }
    pub fn sub(a: Vec3, b: Vec3) Vec3 { return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z }; }
    pub fn scale(v: Vec3, s: f32) Vec3 { return .{ .x = v.x * s, .y = v.y * s, .z = v.z * s }; }
    pub fn dot(a: Vec3, b: Vec3) f32 { return a.x * b.x + a.y * b.y + a.z * b.z; }
    pub fn cross(a: Vec3, b: Vec3) Vec3 { return .{ .x = a.y * b.z - a.z * b.y, .y = a.z * b.x - a.x * b.z, .z = a.x * b.y - a.y * b.x }; }
    pub fn length(v: Vec3) f32 { return @sqrt(v.x * v.x + v.y * v.y + v.z * v.z); }
    pub fn normalize(v: Vec3) Vec3 { const l = v.length(); return if (l > 0) v.scale(1 / l) else v; }
};

pub const Camera3D = struct {
    pos: Vec3 = Vec3.init(0, 2, 5),
    target: Vec3 = Vec3.init(0, 0, 0),
    up: Vec3 = Vec3.init(0, 1, 0),
    fov: f32 = 60 * std.math.pi / 180.0,
    aspect: f32 = 1.6,
    near: f32 = 0.1,
    far: f32 = 100,

    pub fn init(w: f32, h: f32, fov_deg: f32) Camera3D {
        return .{ .aspect = w / h, .fov = fov_deg * std.math.pi / 180.0 };
    }
    pub fn lookAt(eye: Vec3, center: Vec3, up: Vec3) Mat4 {
        const f = center.sub(eye).normalize();
        const s = f.cross(up).normalize();
        const u = s.cross(f);
        var r = Mat4.identity();
        r.m[0] = s.x; r.m[1] = u.x; r.m[2] = -f.x;
        r.m[4] = s.y; r.m[5] = u.y; r.m[6] = -f.y;
        r.m[8] = s.z; r.m[9] = u.z; r.m[10] = -f.z;
        r.m[12] = -s.dot(eye);
        r.m[13] = -u.dot(eye);
        r.m[14] = f.dot(eye);
        return r;
    }
    pub fn perspective(fov: f32, aspect: f32, near: f32, far: f32) Mat4 {
        const f = 1.0 / @tan(fov * 0.5);
        var r: Mat4 = .{ .m = [_]f32{0} ** 16 };
        r.m[0] = f / aspect;
        r.m[5] = f;
        r.m[10] = (far + near) / (near - far);
        r.m[11] = -1;
        r.m[14] = (2 * far * near) / (near - far);
        return r;
    }
    pub fn view(self: Camera3D) Mat4 { return Camera3D.lookAt(self.pos, self.target, self.up); }
    pub fn projection(self: Camera3D) Mat4 { return Camera3D.perspective(self.fov, self.aspect, self.near, self.far); }
    pub fn combined(self: Camera3D) Mat4 { return self.projection().mul(self.view()); }
    pub fn orbit(self: *Camera3D, yaw: f32, pitch: f32, dist: f32) void {
        const x = dist * @cos(pitch) * @sin(yaw);
        const y = dist * @sin(pitch);
        const z = dist * @cos(pitch) * @cos(yaw);
        self.pos = Vec3.init(x, y, z).add(self.target);
    }
};

test "camera3d perspective" {
    const cam = Camera3D.init(800, 600, 60);
    const proj = cam.projection();
    try std.testing.expect(proj.m[0] > 0);
    const view = cam.view();
    try std.testing.expect(view.m[15] == 1);
}
