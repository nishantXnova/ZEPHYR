const std = @import("std");

// High-resolution timer abstraction over Win32 QPC
const win = @import("../platform/win32.zig");

pub const Clock = struct {
    freq: i64,
    last: i64,
    dt: f32 = 0,
    total: f32 = 0,

    pub fn init() Clock {
        var freq: win.LARGE_INTEGER = undefined;
        _ = win.QueryPerformanceFrequency(&freq);
        var now: win.LARGE_INTEGER = undefined;
        _ = win.QueryPerformanceCounter(&now);
        return .{ .freq = freq.QuadPart, .last = now.QuadPart };
    }

    pub fn tick(self: *Clock) f32 {
        var now: win.LARGE_INTEGER = undefined;
        _ = win.QueryPerformanceCounter(&now);
        const delta_ticks = now.QuadPart - self.last;
        self.last = now.QuadPart;
        self.dt = @as(f32, @floatFromInt(delta_ticks)) / @as(f32, @floatFromInt(self.freq));
        // stable clamp + smoothing — avoid spikes that cause lag feel
        if (self.dt > 0.033) self.dt = 0.033;
        if (self.dt < 0.001) self.dt = 0.001;
        // simple EMA to smooth jitter
        self.dt = self.dt * 0.9 + 0.016 * 0.1;
        self.total += self.dt;
        return self.dt;
    }
};
