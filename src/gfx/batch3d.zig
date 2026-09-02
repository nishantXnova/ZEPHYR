const std = @import("std");
const gl = @import("gl.zig");
const Shader3D = @import("shader3d.zig").Shader3D;
const Texture = @import("texture.zig").Texture;
const Color = @import("color.zig").Color;
const Mat4 = @import("../core/camera.zig").Mat4;

// Zephyr Batch3D v2.0 — Novel hybrid, pluggable. Same Batch idea but pos(3).
// One VAO/VBO/EBO, 2048 tris, single shader3d, depth test, no second engine.
// 2D Batch is pos(2) ortho, Batch3D is pos(3) perspective — same App loop, just different cam.
// Proves "pluggable 2D→3D" claim: swap cam.combined() from ortho to perspective, keep draw calls.

const Vertex3 = extern struct { x: f32, y: f32, z: f32, u: f32, v: f32, r: u8, g: u8, b: u8, a: u8 };
const MAX_TRIS = 2048;
const MAX_VERTS = MAX_TRIS * 3;
const MAX_INDICES = MAX_TRIS * 3;

pub const Batch3D = struct {
    vao: gl.GLuint = 0,
    vbo: gl.GLuint = 0,
    ebo: gl.GLuint = 0,
    shader: Shader3D,
    white: Texture,
    proj: Mat4,
    verts: [MAX_VERTS]Vertex3 = undefined,
    vert_count: usize = 0,
    index_count: usize = 0,
    cur_tex: gl.GLuint = 0,

    pub fn init(proj: Mat4) !Batch3D {
        const shader = try Shader3D.init();
        const white = try Texture.initWhite();
        var vao: gl.GLuint = 0; var vbo: gl.GLuint = 0; var ebo: gl.GLuint = 0;
        gl.GenVertexArrays(1, @ptrCast(&vao));
        gl.GenBuffers(1, @ptrCast(&vbo));
        gl.GenBuffers(1, @ptrCast(&ebo));
        gl.BindVertexArray(vao);
        gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
        gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(Vertex3) * MAX_VERTS, null, gl.DYNAMIC_DRAW);
        // indices filled on flush as sequential tris (no EBO reuse needed, but create)
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);
        var indices: [MAX_INDICES]u32 = undefined;
        for (0..MAX_INDICES) |i| indices[i] = @intCast(i);
        gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, @sizeOf(u32) * MAX_INDICES, &indices, gl.STATIC_DRAW);
        gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, @sizeOf(Vertex3), @ptrFromInt(@offsetOf(Vertex3, "x")));
        gl.EnableVertexAttribArray(0);
        gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, @sizeOf(Vertex3), @ptrFromInt(@offsetOf(Vertex3, "u")));
        gl.EnableVertexAttribArray(1);
        gl.VertexAttribPointer(2, 4, gl.UNSIGNED_BYTE, gl.TRUE, @sizeOf(Vertex3), @ptrFromInt(@offsetOf(Vertex3, "r")));
        gl.EnableVertexAttribArray(2);
        gl.BindVertexArray(0);
        return .{ .vao = vao, .vbo = vbo, .ebo = ebo, .shader = shader, .white = white, .proj = proj };
    }
    pub fn deinit(self: *Batch3D) void {
        gl.DeleteVertexArrays(1, @ptrCast(&self.vao));
        gl.DeleteBuffers(1, @ptrCast(&self.vbo));
        gl.DeleteBuffers(1, @ptrCast(&self.ebo));
        self.shader.deinit();
        self.white.deinit();
    }
    pub fn setProjection(self: *Batch3D, proj: Mat4) void { self.proj = proj; }
    pub fn begin(self: *Batch3D) void {
        self.vert_count = 0;
        self.index_count = 0;
        self.cur_tex = self.white.id;
        self.white.bind(0);
        self.shader.bind();
        gl.UniformMatrix4fv(self.shader.uProj, 1, gl.FALSE, @ptrCast(&self.proj.m));
        gl.Uniform1i(self.shader.uTex, 0);
        gl.BindVertexArray(self.vao);
        gl.Enable(gl.DEPTH_TEST);
        gl.Clear(gl.DEPTH_BUFFER_BIT);
    }
    pub fn end(self: *Batch3D) void {
        if (self.vert_count > 0) self.flush();
        gl.BindVertexArray(0);
        self.shader.unbind();
        gl.Disable(gl.DEPTH_TEST);
    }
    fn flush(self: *Batch3D) void {
        if (self.vert_count == 0) return;
        gl.BindBuffer(gl.ARRAY_BUFFER, self.vbo);
        gl.BufferSubData(gl.ARRAY_BUFFER, 0, @as(gl.GLsizeiptr, @intCast(self.vert_count * @sizeOf(Vertex3))), &self.verts);
        gl.DrawElements(gl.TRIANGLES, @intCast(self.index_count), 0x1405, null);
        self.vert_count = 0;
        self.index_count = 0;
    }
    fn flushWith(self: *Batch3D, tex_id: gl.GLuint) void {
        if (self.vert_count + 3 > MAX_VERTS) self.flush();
        if (self.cur_tex != tex_id) {
            if (self.vert_count > 0) self.flush();
            gl.ActiveTexture(gl.TEXTURE0);
            gl.BindTexture(gl.TEXTURE_2D, tex_id);
            self.cur_tex = tex_id;
        }
    }
    pub fn drawTri(self: *Batch3D, p0: [3]f32, p1: [3]f32, p2: [3]f32, uv0: [2]f32, uv1: [2]f32, uv2: [2]f32, col: Color, tex: *Texture) void {
        self.flushWith(tex.id);
        const idx = self.vert_count;
        self.verts[idx + 0] = .{ .x = p0[0], .y = p0[1], .z = p0[2], .u = uv0[0], .v = uv0[1], .r = col.r, .g = col.g, .b = col.b, .a = col.a };
        self.verts[idx + 1] = .{ .x = p1[0], .y = p1[1], .z = p1[2], .u = uv1[0], .v = uv1[1], .r = col.r, .g = col.g, .b = col.b, .a = col.a };
        self.verts[idx + 2] = .{ .x = p2[0], .y = p2[1], .z = p2[2], .u = uv2[0], .v = uv2[1], .r = col.r, .g = col.g, .b = col.b, .a = col.a };
        self.vert_count += 3;
        self.index_count += 3;
    }
    // Sprite in 3D: same API as 2D drawTexture but with z
    pub fn drawSprite3D(self: *Batch3D, tex: *Texture, x: f32, y: f32, z: f32, w: f32, h: f32) void {
        // quad as two tris in XZ plane? Use billboard: quad facing camera at (x,y,z)
        // For hybrid 2.5D, we draw as quad in XY plane at z depth (like 2D but with depth)
        const p0 = [_]f32{ x, y, z };
        const p1 = [_]f32{ x + w, y, z };
        const p2 = [_]f32{ x + w, y + h, z };
        const p3 = [_]f32{ x, y + h, z };
        self.drawTri(p0, p1, p2, .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, Color.white, tex);
        self.drawTri(p0, p2, p3, .{ 0, 0 }, .{ 1, 1 }, .{ 0, 1 }, Color.white, tex);
    }
};
