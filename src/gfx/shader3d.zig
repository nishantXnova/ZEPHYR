const std = @import("std");
const gl = @import("gl.zig");

const vs_src: [*:0]const u8 =
    \\#version 330 core
    \\layout(location=0) in vec3 aPos;
    \\layout(location=1) in vec2 aUV;
    \\layout(location=2) in vec4 aColor;
    \\uniform mat4 uProj;
    \\out vec2 vUV;
    \\out vec4 vColor;
    \\void main(){
    \\  gl_Position = uProj * vec4(aPos, 1.0);
    \\  vUV = aUV;
    \\  vColor = aColor;
    \\}
;

const fs_src: [*:0]const u8 =
    \\#version 330 core
    \\in vec2 vUV;
    \\in vec4 vColor;
    \\uniform sampler2D uTex;
    \\out vec4 FragColor;
    \\void main(){
    \\  vec4 t = texture(uTex, vUV);
    \\  FragColor = vColor * t;
    \\}
;

pub const Shader3D = struct {
    id: gl.GLuint,
    uProj: gl.GLint,
    uTex: gl.GLint,

    pub fn init() !Shader3D {
        const vert = gl.CreateShader(gl.VERTEX_SHADER);
        var vs = vs_src;
        gl.ShaderSource(vert, 1, @ptrCast(&vs), null);
        gl.CompileShader(vert);
        try checkShader(vert, "vertex3d");

        const frag = gl.CreateShader(gl.FRAGMENT_SHADER);
        var fs = fs_src;
        gl.ShaderSource(frag, 1, @ptrCast(&fs), null);
        gl.CompileShader(frag);
        try checkShader(frag, "fragment3d");

        const prog = gl.CreateProgram();
        gl.AttachShader(prog, vert);
        gl.AttachShader(prog, frag);
        gl.LinkProgram(prog);
        try checkProgram(prog);

        gl.DeleteShader(vert);
        gl.DeleteShader(frag);

        const uProj = gl.GetUniformLocation(prog, "uProj");
        const uTex = gl.GetUniformLocation(prog, "uTex");
        return .{ .id = prog, .uProj = uProj, .uTex = uTex };
    }

    pub fn deinit(self: *Shader3D) void { gl.DeleteProgram(self.id); }
    pub fn bind(self: Shader3D) void { gl.UseProgram(self.id); }
    pub fn unbind(_: Shader3D) void { gl.UseProgram(0); }
};

fn checkShader(shader: gl.GLuint, label: []const u8) !void {
    var ok: gl.GLint = 0;
    gl.GetShaderiv(shader, gl.COMPILE_STATUS, &ok);
    if (ok == gl.FALSE) {
        var len: gl.GLint = 0;
        gl.GetShaderiv(shader, gl.INFO_LOG_LENGTH, &len);
        var buf: [1024]u8 = undefined;
        const l = @min(len, 1024);
        gl.GetShaderInfoLog(shader, l, null, @ptrCast(&buf));
        std.log.err("Zephyr Shader3D {s}: {s}", .{ label, buf[0..@intCast(l)] });
        return error.ShaderCompileFailed;
    }
}
fn checkProgram(prog: gl.GLuint) !void {
    var ok: gl.GLint = 0;
    gl.GetProgramiv(prog, gl.LINK_STATUS, &ok);
    if (ok == gl.FALSE) {
        var len: gl.GLint = 0;
        gl.GetProgramiv(prog, gl.INFO_LOG_LENGTH, &len);
        var buf: [1024]u8 = undefined;
        const l = @min(len, 1024);
        gl.GetProgramInfoLog(prog, l, null, @ptrCast(&buf));
        std.log.err("Zephyr Program3D link: {s}", .{buf[0..@intCast(l)]});
        return error.ProgramLinkFailed;
    }
}
