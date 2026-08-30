//! SpriteBatch — pluggable 2D → 3D. Batches quads, single draw call per flush.
//! Vertex: pos(2) + uv(2) + color(4) normalized. 4 verts + 6 indices per quad.
const std = @import("std");
const gl = @import("gl.zig");
const Shader = @import("shader.zig").Shader;
const Texture = @import("texture.zig").Texture;
const Color = @import("color.zig").Color;
const Mat4 = @import("../core/camera.zig").Mat4;

const Vertex = extern struct {
    x: f32,
    y: f32,
    u: f32,
    v: f32,
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

const MAX_QUADS = 2048;
const MAX_VERTS = MAX_QUADS * 4;
const MAX_INDICES = MAX_QUADS * 6;

pub const Batch = struct {
    vao: gl.GLuint = 0,
    vbo: gl.GLuint = 0,
    ebo: gl.GLuint = 0,
    shader: Shader,
    white: Texture,
    proj: Mat4,
    verts: [MAX_VERTS]Vertex = undefined,
    vert_count: usize = 0,
    index_count: usize = 0,
    drawing: bool = false,
    cur_tex: gl.GLuint = 0, // track bound texture for flush

    pub fn init(proj: Mat4) !Batch {
        const shader = try Shader.init();
        const white = try Texture.initWhite();

        var vao: gl.GLuint = 0;
        var vbo: gl.GLuint = 0;
        var ebo: gl.GLuint = 0;
        gl.GenVertexArrays(1, @ptrCast(&vao));
        gl.GenBuffers(1, @ptrCast(&vbo));
        gl.GenBuffers(1, @ptrCast(&ebo));

        gl.BindVertexArray(vao);
        gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
        gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(Vertex) * MAX_VERTS, null, gl.DYNAMIC_DRAW);

        // indices
        var indices: [MAX_INDICES]u32 = undefined;
        var i: usize = 0;
        var off: u32 = 0;
        while (i < MAX_INDICES) : (i += 6) {
            indices[i + 0] = off + 0;
            indices[i + 1] = off + 1;
            indices[i + 2] = off + 2;
            indices[i + 3] = off + 2;
            indices[i + 4] = off + 3;
            indices[i + 5] = off + 0;
            off += 4;
        }
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);
        gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, @sizeOf(u32) * MAX_INDICES, &indices, gl.STATIC_DRAW);

        // layout: 0 pos, 1 uv, 2 color (normalized)
        gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @ptrFromInt(@offsetOf(Vertex, "x")));
        gl.EnableVertexAttribArray(0);
        gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @ptrFromInt(@offsetOf(Vertex, "u")));
        gl.EnableVertexAttribArray(1);
        gl.VertexAttribPointer(2, 4, gl.UNSIGNED_BYTE, gl.TRUE, @sizeOf(Vertex), @ptrFromInt(@offsetOf(Vertex, "r")));
        gl.EnableVertexAttribArray(2);

        gl.BindVertexArray(0);

        return .{
            .vao = vao,
            .vbo = vbo,
            .ebo = ebo,
            .shader = shader,
            .white = white,
            .proj = proj,
        };
    }

    pub fn deinit(self: *Batch) void {
        gl.DeleteVertexArrays(1, @ptrCast(&self.vao));
        gl.DeleteBuffers(1, @ptrCast(&self.vbo));
        gl.DeleteBuffers(1, @ptrCast(&self.ebo));
        self.shader.deinit();
        self.white.deinit();
    }

    pub fn setProjection(self: *Batch, proj: Mat4) void {
        self.proj = proj;
    }

    pub fn begin(self: *Batch) void {
        self.vert_count = 0;
        self.index_count = 0;
        self.drawing = true;
        self.cur_tex = self.white.id;
        self.white.bind(0);
        self.shader.bind();
        gl.UniformMatrix4fv(self.shader.uProj, 1, gl.FALSE, @ptrCast(&self.proj.m));
        gl.Uniform1i(self.shader.uTex, 0);
        gl.BindVertexArray(self.vao);
    }

    pub fn end(self: *Batch) void {
        if (self.vert_count > 0) self.flush();
        gl.BindVertexArray(0);
        self.shader.unbind();
        self.drawing = false;
    }

    fn flush(self: *Batch) void {
        if (self.vert_count == 0) return;
        // cur_tex already bound
        gl.BindBuffer(gl.ARRAY_BUFFER, self.vbo);
        gl.BufferSubData(gl.ARRAY_BUFFER, 0, @as(gl.GLsizeiptr, @intCast(self.vert_count * @sizeOf(Vertex))), &self.verts);
        gl.DrawElements(gl.TRIANGLES, @intCast(self.index_count), 0x1405, null); // GL_UNSIGNED_INT 0x1405
        self.vert_count = 0;
        self.index_count = 0;
    }
    fn flushWith(self: *Batch, tex_id: gl.GLuint) void {
        if (self.vert_count > 0 and self.cur_tex != tex_id) self.flush();
        if (self.cur_tex != tex_id) {
            gl.ActiveTexture(gl.TEXTURE0);
            gl.BindTexture(gl.TEXTURE_2D, tex_id);
            self.cur_tex = tex_id;
        }
    }

    // --- Draw helpers (2D) ---

    pub fn drawRect(self: *Batch, x: f32, y: f32, w: f32, h: f32, color: Color) void {
        self.drawRectUV(x, y, w, h, 0, 0, 1, 1, color, &self.white);
    }

    pub fn drawRectUV(self: *Batch, x: f32, y: f32, w: f32, h: f32, ux0: f32, vy0: f32, ux1: f32, vy1: f32, color: Color, tex: *Texture) void {
        if (self.vert_count + 4 > MAX_VERTS) self.flush();
        self.flushWith(tex.id);

        const idx = self.vert_count;
        self.verts[idx + 0] = .{ .x = x, .y = y, .u = ux0, .v = vy0, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
        self.verts[idx + 1] = .{ .x = x + w, .y = y, .u = ux1, .v = vy0, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
        self.verts[idx + 2] = .{ .x = x + w, .y = y + h, .u = ux1, .v = vy1, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
        self.verts[idx + 3] = .{ .x = x, .y = y + h, .u = ux0, .v = vy1, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
        self.vert_count += 4;
        self.index_count += 6;
    }

    pub fn drawTexture(self: *Batch, tex: *Texture, x: f32, y: f32, w: f32, h: f32) void {
        self.drawRectUV(x, y, w, h, 0, 0, 1, 1, Color.white, tex);
    }

    pub fn drawTextureEx(self: *Batch, tex: *Texture, x: f32, y: f32, w: f32, h: f32, src_x: f32, src_y: f32, src_w: f32, src_h: f32, tint: Color) void {
        const uu0 = src_x / @as(f32, @floatFromInt(tex.w));
        const vv0 = src_y / @as(f32, @floatFromInt(tex.h));
        const uu1 = (src_x + src_w) / @as(f32, @floatFromInt(tex.w));
        const vv1 = (src_y + src_h) / @as(f32, @floatFromInt(tex.h));
        self.drawRectUV(x, y, w, h, uu0, vv0, uu1, vv1, tint, tex);
    }

    // 3D-ready: drawQuad with 4 arbitrary points (for rotation)
    pub fn drawQuad(self: *Batch, p0: [2]f32, p1: [2]f32, p2: [2]f32, p3: [2]f32, color: Color) void {
        if (self.vert_count + 4 > MAX_VERTS) self.flush();
        const idx = self.vert_count;
        self.verts[idx + 0] = .{ .x = p0[0], .y = p0[1], .u = 0, .v = 0, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
        self.verts[idx + 1] = .{ .x = p1[0], .y = p1[1], .u = 1, .v = 0, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
        self.verts[idx + 2] = .{ .x = p2[0], .y = p2[1], .u = 1, .v = 1, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
        self.verts[idx + 3] = .{ .x = p3[0], .y = p3[1], .u = 0, .v = 1, .r = color.r, .g = color.g, .b = color.b, .a = color.a };
        self.vert_count += 4;
        self.index_count += 6;
    }
};
