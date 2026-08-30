const std = @import("std");
const win = @import("win32.zig");
const Color = @import("../gfx/color.zig").Color;
const gl = @import("../gfx/gl.zig");
const Batch = @import("../gfx/batch.zig").Batch;
const Mat4 = @import("../core/camera.zig").Mat4;

// Global state for WNDPROC
var g_should_close: bool = false;
var g_keys: [256]bool = [_]bool{false} ** 256;
var g_keys_pressed: [256]bool = [_]bool{false} ** 256;
var g_mouse_x: i32 = 0;
var g_mouse_y: i32 = 0;
var g_mouse_down: [3]bool = [_]bool{false} ** 3;
var g_wheel: i32 = 0;

fn wndProc(hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) callconv(.winapi) win.LRESULT {
    switch (msg) {
        win.WM_CLOSE, win.WM_DESTROY => {
            g_should_close = true;
            win.PostQuitMessage(0);
            return 0;
        },
        win.WM_KEYDOWN => {
            const vk = wparam & 0xFF;
            if (!g_keys[vk]) g_keys_pressed[vk] = true;
            g_keys[vk] = true;
            return 0;
        },
        win.WM_KEYUP => {
            const vk = wparam & 0xFF;
            g_keys[vk] = false;
            return 0;
        },
        win.WM_MOUSEMOVE => {
            g_mouse_x = @as(i16, @truncate(lparam & 0xFFFF));
            g_mouse_y = @as(i16, @truncate((lparam >> 16) & 0xFFFF));
            return 0;
        },
        win.WM_LBUTTONDOWN => {
            g_mouse_down[0] = true;
            return 0;
        },
        win.WM_LBUTTONUP => {
            g_mouse_down[0] = false;
            return 0;
        },
        win.WM_MOUSEWHEEL => {
            const delta: i16 = @truncate(@as(i32, @intCast((wparam >> 16) & 0xFFFF)));
            g_wheel += @as(i32, delta);
            return 0;
        },
        else => {},
    }
    return win.DefWindowProcW(hwnd, msg, wparam, lparam);
}

pub const WindowConfig = struct {
    title: []const u8 = "Zephyr - Flappy Bird",
    width: i32 = 480,
    height: i32 = 640,
    vsync: bool = false,
};

pub const Window = struct {
    hwnd: win.HWND,
    hdc: win.HDC,
    hglrc: ?*anyopaque = null,
    width: i32,
    height: i32,
    should_close: bool = false,
    // GL path
    batch: ?Batch = null,
    use_gl: bool = true,
    // GDI fallback
    hdc_buffer: win.HDC = null,
    hbitmap: win.HBITMAP = null,

    pub fn init(cfg: WindowConfig) !Window {
        g_should_close = false;
        g_keys = [_]bool{false} ** 256;
        g_keys_pressed = [_]bool{false} ** 256;

        const hInstance = win.GetModuleHandleW(null);
        const class_name_w = try toWideZ("ZEPHYR_WINDOW_CLASS");
        defer std.heap.c_allocator.free(class_name_w);
        const title_w = try toWideZ(cfg.title);
        defer std.heap.c_allocator.free(title_w);

        var wc = win.WNDCLASSEXW{
            .cbSize = @sizeOf(win.WNDCLASSEXW),
            .style = win.CS_HREDRAW | win.CS_VREDRAW | win.CS_OWNDC,
            .lpfnWndProc = wndProc,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = hInstance,
            .hIcon = null,
            .hCursor = win.LoadCursorW(null, @ptrFromInt(win.IDC_ARROW)),
            .hbrBackground = null,
            .lpszMenuName = null,
            .lpszClassName = class_name_w.ptr,
            .hIconSm = null,
        };
        _ = win.RegisterClassExW(&wc);

        var rect = win.RECT{ .left = 0, .top = 0, .right = cfg.width, .bottom = cfg.height };
        _ = win.AdjustWindowRectEx(&rect, win.WS_OVERLAPPEDWINDOW, 0, 0);
        const win_w = rect.right - rect.left;
        const win_h = rect.bottom - rect.top;

        const hwnd = win.CreateWindowExW(0, class_name_w.ptr, title_w.ptr, win.WS_OVERLAPPEDWINDOW | win.WS_VISIBLE, win.CW_USEDEFAULT, win.CW_USEDEFAULT, win_w, win_h, null, null, hInstance, null);
        if (hwnd == null) return error.WindowCreationFailed;
        _ = win.ShowWindow(hwnd, win.SW_SHOW);
        _ = win.UpdateWindow(hwnd);

        const hdc = win.GetDC(hwnd);
        if (hdc == null) return error.GetDCFailed;

        // Try GL path
        var self = Window{ .hwnd = hwnd, .hdc = hdc, .width = cfg.width, .height = cfg.height };
        const gl_ok = self.initGL();
        if (!gl_ok) {
            // fallback to GDI
            std.log.warn("Zephyr: OpenGL init failed, falling back to GDI", .{});
            self.use_gl = false;
            const hdc_buf = win.CreateCompatibleDC(hdc);
            if (hdc_buf == null) return error.CreateCompatibleDCFailed;
            const hbmp = win.CreateCompatibleBitmap(hdc, cfg.width, cfg.height);
            if (hbmp == null) return error.CreateBitmapFailed;
            _ = win.SelectObject(hdc_buf, hbmp);
            self.hdc_buffer = hdc_buf;
            self.hbitmap = hbmp;
        }
        _ = win.timeBeginPeriod(1);
        return self;
    }

    fn initGL(self: *Window) bool {
        var pfd = win.PIXELFORMATDESCRIPTOR{
            .dwFlags = win.PFD_DRAW_TO_WINDOW | win.PFD_SUPPORT_OPENGL | win.PFD_DOUBLEBUFFER,
            .iPixelType = win.PFD_TYPE_RGBA,
            .cColorBits = 32,
            .cDepthBits = 24,
            .cStencilBits = 8,
            .iLayerType = win.PFD_MAIN_PLANE,
        };
        const pf = win.ChoosePixelFormat(self.hdc, &pfd);
        if (pf == 0) return false;
        if (win.SetPixelFormat(self.hdc, pf, &pfd) == 0) return false;
        const rc = win.wglCreateContext(self.hdc);
        if (rc == null) return false;
        if (win.wglMakeCurrent(self.hdc, rc) == 0) return false;
        self.hglrc = rc;

        // load GL
        gl.load() catch |e| {
            std.log.err("gl load failed: {}", .{e});
            return false;
        };
        // init batch with ortho proj (0,0 top-left)
        const proj = Mat4.ortho(0, @floatFromInt(self.width), @floatFromInt(self.height), 0, -1, 1);
        self.batch = Batch.init(proj) catch |e| {
            std.log.err("batch init failed: {}", .{e});
            return false;
        };
        gl.Viewport(0, 0, self.width, self.height);
        gl.Enable(gl.BLEND);
        gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
        if (gl.GetString(0x1F02)) |ver| std.log.info("Zephyr GL: {s}", .{ver});
        return true;
    }

    pub fn deinit(self: *Window) void {
        if (self.batch) |*b| {
            var bb = b.*;
            bb.deinit();
        }
        if (self.hglrc) |rc| {
            _ = win.wglMakeCurrent(null, null);
            _ = win.wglDeleteContext(rc);
        }
        if (self.hbitmap) |bm| _ = win.DeleteObject(bm);
        if (self.hdc_buffer) |dc| _ = win.DeleteDC(dc);
        if (self.hdc) |dc| _ = win.ReleaseDC(self.hwnd, dc);
        if (self.hwnd) |hwnd| _ = win.DestroyWindow(hwnd);
    }

    pub fn poll(self: *Window) void {
        var msg: win.MSG = undefined;
        while (win.PeekMessageW(&msg, null, 0, 0, win.PM_REMOVE) != 0) {
            _ = win.TranslateMessage(&msg);
            _ = win.DispatchMessageW(&msg);
            if (msg.message == win.WM_QUIT) g_should_close = true;
        }
        self.should_close = g_should_close;
    }
    pub fn shouldClose(self: *Window) bool {
        return self.should_close or g_should_close;
    }
    pub fn isKeyDown(_: *Window, vk: usize) bool {
        return g_keys[vk & 0xFF];
    }
    pub fn isKeyPressed(_: *Window, vk: usize) bool {
        const v = g_keys_pressed[vk & 0xFF];
        if (v) g_keys_pressed[vk & 0xFF] = false;
        return v;
    }
    pub fn isSpacePressed(self: *Window) bool {
        return self.isKeyPressed(win.VK_SPACE);
    }
    pub fn mousePos(_: *Window) struct { x: i32, y: i32 } {
        return .{ .x = g_mouse_x, .y = g_mouse_y };
    }
    pub fn isMouseDown(_: *Window, btn: usize) bool {
        if (btn >= g_mouse_down.len) return false;
        return g_mouse_down[btn];
    }
    pub fn wheelDelta(_: *Window) i32 {
        const d = g_wheel;
        g_wheel = 0;
        return d;
    }
    pub fn sleep(_: *Window, ms: u32) void {
        win.Sleep(ms);
    }
    pub fn setBatchProjection(self: *Window, proj: Mat4) void {
        if (self.batch) |*b| b.setProjection(proj);
    }
    pub fn setTitle(self: *Window, title: []const u8) void {
        var buf: [256]u16 = undefined;
        const n = @min(title.len, buf.len - 1);
        for (title[0..n], 0..) |c, i| buf[i] = @as(u16, c);
        buf[n] = 0;
        const SetWindowTextW = struct {
            extern "user32" fn SetWindowTextW(hwnd: win.HWND, lpString: win.LPCWSTR) callconv(.winapi) win.BOOL;
        }.SetWindowTextW;
        _ = SetWindowTextW(self.hwnd, @ptrCast(&buf));
    }

    // Rendering — pluggable: GL batch if available, else GDI
    pub fn beginFrame(self: *Window, color: Color) void {
        if (self.use_gl and self.batch != null) {
            const r: f32 = @as(f32, @floatFromInt(color.r)) / 255.0;
            const g: f32 = @as(f32, @floatFromInt(color.g)) / 255.0;
            const b: f32 = @as(f32, @floatFromInt(color.b)) / 255.0;
            gl.ClearColor(r, g, b, 1.0);
            gl.Clear(gl.COLOR_BUFFER_BIT);
            if (self.batch) |*bb| bb.begin();
        } else {
            const col = color.toBGR();
            const brush = win.CreateSolidBrush(col);
            defer _ = win.DeleteObject(brush);
            var rect = win.RECT{ .left = 0, .top = 0, .right = self.width, .bottom = self.height };
            _ = win.FillRect(self.hdc_buffer, &rect, brush);
        }
    }
    pub fn endFrame(self: *Window) void {
        if (self.use_gl and self.batch != null) {
            if (self.batch) |*bb| bb.end();
            _ = win.SwapBuffers(self.hdc);
        } else {
            _ = win.BitBlt(self.hdc, 0, 0, self.width, self.height, self.hdc_buffer, 0, 0, win.SRCCOPY);
        }
    }
    pub fn drawRect(self: *Window, x: f32, y: f32, w: f32, h: f32, color: Color) void {
        if (self.use_gl and self.batch != null) {
            if (self.batch) |*bb| bb.drawRect(x, y, w, h, color);
        } else {
            const xi: i32 = @intFromFloat(@round(x));
            const yi: i32 = @intFromFloat(@round(y));
            const wi: i32 = @intFromFloat(@round(w));
            const hi: i32 = @intFromFloat(@round(h));
            const col = color.toBGR();
            const brush = win.CreateSolidBrush(col);
            defer _ = win.DeleteObject(brush);
            var rect = win.RECT{ .left = xi, .top = yi, .right = xi + wi, .bottom = yi + hi };
            _ = win.FillRect(self.hdc_buffer, &rect, brush);
        }
    }
    pub fn drawRectOutline(self: *Window, x: f32, y: f32, w: f32, h: f32, color: Color) void {
        const t: f32 = 2;
        self.drawRect(x, y, w, t, color);
        self.drawRect(x, y + h - t, w, t, color);
        self.drawRect(x, y, t, h, color);
        self.drawRect(x + w - t, y, t, h, color);
    }
    pub fn drawCircle(self: *Window, cx: f32, cy: f32, radius: f32, color: Color) void {
        if (self.use_gl) {
            // approximate circle with quad + could use shader disc, fallback to rect for now
            self.drawRect(cx - radius, cy - radius, radius * 2, radius * 2, color);
        } else {
            const xi: i32 = @intFromFloat(@round(cx - radius));
            const yi: i32 = @intFromFloat(@round(cy - radius));
            const ri: i32 = @intFromFloat(@round(radius * 2));
            const col = color.toBGR();
            const brush = win.CreateSolidBrush(col);
            defer _ = win.DeleteObject(brush);
            const old = win.SelectObject(self.hdc_buffer, brush);
            _ = win.Ellipse(self.hdc_buffer, xi, yi, xi + ri, yi + ri);
            _ = win.SelectObject(self.hdc_buffer, old);
        }
    }
};

fn toWideZ(utf8: []const u8) ![:0]u16 {
    var out = try std.heap.c_allocator.allocSentinel(u16, utf8.len, 0);
    for (utf8, 0..) |c, i| out[i] = @as(u16, c);
    return out;
}
