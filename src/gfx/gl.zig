//! OpenGL 3.3 core loader — pluggable, lightweight.
//! Loads via wglGetProcAddress + opengl32 fallback. Only what Zephyr needs.
const std = @import("std");
const win = @import("../platform/win32.zig");

// GL types
pub const GLenum = u32;
pub const GLuint = u32;
pub const GLint = i32;
pub const GLsizei = i32;
pub const GLboolean = u8;
pub const GLfloat = f32;
pub const GLchar = u8;
pub const GLbitfield = u32;
pub const GLsizeiptr = isize;
pub const GLintptr = isize;

// Constants
pub const COLOR_BUFFER_BIT: GLbitfield = 0x00004000;
pub const BLEND: GLenum = 0x0BE2;
pub const SRC_ALPHA: GLenum = 0x0302;
pub const ONE_MINUS_SRC_ALPHA: GLenum = 0x0303;
pub const ARRAY_BUFFER: GLenum = 0x8892;
pub const ELEMENT_ARRAY_BUFFER: GLenum = 0x8893;
pub const STATIC_DRAW: GLenum = 0x88E4;
pub const DYNAMIC_DRAW: GLenum = 0x88E8;
pub const FLOAT: GLenum = 0x1406;
pub const TRIANGLES: GLenum = 0x0004;
pub const TEXTURE_2D: GLenum = 0x0DE1;
pub const TEXTURE0: GLenum = 0x84C0;
pub const RGBA: GLenum = 0x1908;
pub const UNSIGNED_BYTE: GLenum = 0x1401;
pub const NEAREST: GLenum = 0x2600;
pub const LINEAR: GLenum = 0x2601;
pub const CLAMP_TO_EDGE: GLenum = 0x812F;
pub const TEXTURE_MIN_FILTER: GLenum = 0x2801;
pub const TEXTURE_MAG_FILTER: GLenum = 0x2800;
pub const TEXTURE_WRAP_S: GLenum = 0x2802;
pub const TEXTURE_WRAP_T: GLenum = 0x2803;
pub const VERTEX_SHADER: GLenum = 0x8B31;
pub const FRAGMENT_SHADER: GLenum = 0x8B30;
pub const COMPILE_STATUS: GLenum = 0x8B81;
pub const LINK_STATUS: GLenum = 0x8B82;
pub const INFO_LOG_LENGTH: GLenum = 0x8B84;
pub const FALSE: GLboolean = 0;
pub const TRUE: GLboolean = 1;

// Function pointers — loaded at runtime
pub var ClearColor: *const fn (GLfloat, GLfloat, GLfloat, GLfloat) callconv(.winapi) void = undefined;
pub var Clear: *const fn (GLbitfield) callconv(.winapi) void = undefined;
pub var Viewport: *const fn (GLint, GLint, GLsizei, GLsizei) callconv(.winapi) void = undefined;
pub var Enable: *const fn (GLenum) callconv(.winapi) void = undefined;
pub var BlendFunc: *const fn (GLenum, GLenum) callconv(.winapi) void = undefined;
pub var GenVertexArrays: *const fn (GLsizei, [*]GLuint) callconv(.winapi) void = undefined;
pub var BindVertexArray: *const fn (GLuint) callconv(.winapi) void = undefined;
pub var GenBuffers: *const fn (GLsizei, [*]GLuint) callconv(.winapi) void = undefined;
pub var BindBuffer: *const fn (GLenum, GLuint) callconv(.winapi) void = undefined;
pub var BufferData: *const fn (GLenum, GLsizeiptr, ?*const anyopaque, GLenum) callconv(.winapi) void = undefined;
pub var BufferSubData: *const fn (GLenum, GLintptr, GLsizeiptr, ?*const anyopaque) callconv(.winapi) void = undefined;
pub var VertexAttribPointer: *const fn (GLuint, GLint, GLenum, GLboolean, GLsizei, ?*const anyopaque) callconv(.winapi) void = undefined;
pub var EnableVertexAttribArray: *const fn (GLuint) callconv(.winapi) void = undefined;
pub var UseProgram: *const fn (GLuint) callconv(.winapi) void = undefined;
pub var CreateShader: *const fn (GLenum) callconv(.winapi) GLuint = undefined;
pub var ShaderSource: *const fn (GLuint, GLsizei, [*]const [*:0]const GLchar, ?[*]const GLint) callconv(.winapi) void = undefined;
pub var CompileShader: *const fn (GLuint) callconv(.winapi) void = undefined;
pub var GetShaderiv: *const fn (GLuint, GLenum, *GLint) callconv(.winapi) void = undefined;
pub var GetShaderInfoLog: *const fn (GLuint, GLsizei, ?*GLsizei, [*]GLchar) callconv(.winapi) void = undefined;
pub var CreateProgram: *const fn () callconv(.winapi) GLuint = undefined;
pub var AttachShader: *const fn (GLuint, GLuint) callconv(.winapi) void = undefined;
pub var LinkProgram: *const fn (GLuint) callconv(.winapi) void = undefined;
pub var GetProgramiv: *const fn (GLuint, GLenum, *GLint) callconv(.winapi) void = undefined;
pub var GetProgramInfoLog: *const fn (GLuint, GLsizei, ?*GLsizei, [*]GLchar) callconv(.winapi) void = undefined;
pub var DeleteShader: *const fn (GLuint) callconv(.winapi) void = undefined;
pub var DeleteProgram: *const fn (GLuint) callconv(.winapi) void = undefined;
pub var GetUniformLocation: *const fn (GLuint, [*:0]const GLchar) callconv(.winapi) GLint = undefined;
pub var UniformMatrix4fv: *const fn (GLint, GLsizei, GLboolean, [*]const GLfloat) callconv(.winapi) void = undefined;
pub var Uniform1i: *const fn (GLint, GLint) callconv(.winapi) void = undefined;
pub var Uniform4f: *const fn (GLint, GLfloat, GLfloat, GLfloat, GLfloat) callconv(.winapi) void = undefined;
pub var ActiveTexture: *const fn (GLenum) callconv(.winapi) void = undefined;
pub var GenTextures: *const fn (GLsizei, [*]GLuint) callconv(.winapi) void = undefined;
pub var BindTexture: *const fn (GLenum, GLuint) callconv(.winapi) void = undefined;
pub var TexImage2D: *const fn (GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, ?*const anyopaque) callconv(.winapi) void = undefined;
pub var TexParameteri: *const fn (GLenum, GLenum, GLint) callconv(.winapi) void = undefined;
pub var DeleteTextures: *const fn (GLsizei, [*]const GLuint) callconv(.winapi) void = undefined;
pub var DrawElements: *const fn (GLenum, GLsizei, GLenum, ?*const anyopaque) callconv(.winapi) void = undefined;
pub var DrawArrays: *const fn (GLenum, GLint, GLsizei) callconv(.winapi) void = undefined;
pub var DeleteVertexArrays: *const fn (GLsizei, [*]const GLuint) callconv(.winapi) void = undefined;
pub var DeleteBuffers: *const fn (GLsizei, [*]const GLuint) callconv(.winapi) void = undefined;
pub var GetError: *const fn () callconv(.winapi) GLenum = undefined;
pub var GetString: *const fn (GLenum) callconv(.winapi) ?[*:0]const u8 = undefined;

var loaded = false;

fn loadProc(comptime T: type, name: [*:0]const u8) !T {
    if (win.wglGetProcAddress(name)) |p| return @ptrCast(p);
    // fallback to opengl32 exports for legacy funcs
    const lib = win.GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral("opengl32.dll"));
    if (lib) |h| {
        const GetProcAddress = struct {
            extern "kernel32" fn GetProcAddress(hModule: win.HINSTANCE, lpProcName: [*:0]const u8) callconv(.winapi) ?*anyopaque;
        }.GetProcAddress;
        if (GetProcAddress(h, name)) |p| return @ptrCast(p);
    }
    return error.MissingGLProc;
}

pub fn load() !void {
    if (loaded) return;
    ClearColor = try loadProc(@TypeOf(ClearColor), "glClearColor");
    Clear = try loadProc(@TypeOf(Clear), "glClear");
    Viewport = try loadProc(@TypeOf(Viewport), "glViewport");
    Enable = try loadProc(@TypeOf(Enable), "glEnable");
    BlendFunc = try loadProc(@TypeOf(BlendFunc), "glBlendFunc");
    GenVertexArrays = try loadProc(@TypeOf(GenVertexArrays), "glGenVertexArrays");
    BindVertexArray = try loadProc(@TypeOf(BindVertexArray), "glBindVertexArray");
    GenBuffers = try loadProc(@TypeOf(GenBuffers), "glGenBuffers");
    BindBuffer = try loadProc(@TypeOf(BindBuffer), "glBindBuffer");
    BufferData = try loadProc(@TypeOf(BufferData), "glBufferData");
    BufferSubData = try loadProc(@TypeOf(BufferSubData), "glBufferSubData");
    VertexAttribPointer = try loadProc(@TypeOf(VertexAttribPointer), "glVertexAttribPointer");
    EnableVertexAttribArray = try loadProc(@TypeOf(EnableVertexAttribArray), "glEnableVertexAttribArray");
    UseProgram = try loadProc(@TypeOf(UseProgram), "glUseProgram");
    CreateShader = try loadProc(@TypeOf(CreateShader), "glCreateShader");
    ShaderSource = try loadProc(@TypeOf(ShaderSource), "glShaderSource");
    CompileShader = try loadProc(@TypeOf(CompileShader), "glCompileShader");
    GetShaderiv = try loadProc(@TypeOf(GetShaderiv), "glGetShaderiv");
    GetShaderInfoLog = try loadProc(@TypeOf(GetShaderInfoLog), "glGetShaderInfoLog");
    CreateProgram = try loadProc(@TypeOf(CreateProgram), "glCreateProgram");
    AttachShader = try loadProc(@TypeOf(AttachShader), "glAttachShader");
    LinkProgram = try loadProc(@TypeOf(LinkProgram), "glLinkProgram");
    GetProgramiv = try loadProc(@TypeOf(GetProgramiv), "glGetProgramiv");
    GetProgramInfoLog = try loadProc(@TypeOf(GetProgramInfoLog), "glGetProgramInfoLog");
    DeleteShader = try loadProc(@TypeOf(DeleteShader), "glDeleteShader");
    DeleteProgram = try loadProc(@TypeOf(DeleteProgram), "glDeleteProgram");
    GetUniformLocation = try loadProc(@TypeOf(GetUniformLocation), "glGetUniformLocation");
    UniformMatrix4fv = try loadProc(@TypeOf(UniformMatrix4fv), "glUniformMatrix4fv");
    Uniform1i = try loadProc(@TypeOf(Uniform1i), "glUniform1i");
    Uniform4f = try loadProc(@TypeOf(Uniform4f), "glUniform4f");
    ActiveTexture = try loadProc(@TypeOf(ActiveTexture), "glActiveTexture");
    GenTextures = try loadProc(@TypeOf(GenTextures), "glGenTextures");
    BindTexture = try loadProc(@TypeOf(BindTexture), "glBindTexture");
    TexImage2D = try loadProc(@TypeOf(TexImage2D), "glTexImage2D");
    TexParameteri = try loadProc(@TypeOf(TexParameteri), "glTexParameteri");
    DeleteTextures = try loadProc(@TypeOf(DeleteTextures), "glDeleteTextures");
    DrawElements = try loadProc(@TypeOf(DrawElements), "glDrawElements");
    DrawArrays = try loadProc(@TypeOf(DrawArrays), "glDrawArrays");
    DeleteVertexArrays = try loadProc(@TypeOf(DeleteVertexArrays), "glDeleteVertexArrays");
    DeleteBuffers = try loadProc(@TypeOf(DeleteBuffers), "glDeleteBuffers");
    GetError = try loadProc(@TypeOf(GetError), "glGetError");
    GetString = try loadProc(@TypeOf(GetString), "glGetString");
    loaded = true;
}
