const std = @import("std");
const win = @import("../platform/win32.zig");

// Zephyr Input v0.6 — Action mapping, buffering, combos. Indie-killer clever.
// Raw Window.isKeyDown is Scratch-level polling. This adds:
// - Logical actions (jump/run/shoot) mapped to many bindings (keys + gamepad stub)
// - 0.2s input buffering (coyote/jump queue like Celeste)
// - Chord detection (A+B), sequence combos (↓→ Punch)
// - Frame history for replay/debug, deterministic.
// Zero allocs per frame, explicit dt, full control.

pub const Action = enum(u32) {
    left,
    right,
    up,
    down,
    jump,
    run,
    shoot,
    pause,
    reset,
    interact,
    // up to 16
    _count,
};

pub const Binding = union(enum) {
    key: usize, // VK code
    // future: gamepad button, mouse
};

pub const ActionState = struct {
    down: bool = false,
    pressed: bool = false, // edge this frame
    released: bool = false,
    buffer: f32 = 0, // secs remaining buffered
    held_time: f32 = 0,
};

pub const Input = struct {
    // raw -> action map
    bindings: [16][4]?Binding = [_][4]?Binding{[_]?Binding{null} ** 4} ** 16,
    states: [16]ActionState = [_]ActionState{.{}} ** 16,
    history: std.ArrayList([16]bool), // per-frame down history for replay (circular stub 120 frames)
    buffer_time: f32 = 0.18, // coyote/buffer window
    combo_window: f32 = 0.45,
    seq_buf: std.ArrayList(Action), // recent pressed sequence
    seq_timer: f32 = 0,
    delay: u32 = 0, // local input delay frames (fighting-game style) — 0=predict, 2=cuts rollbacks
    delay_queue: std.ArrayList([16]bool) = .empty, // raw queue for delay
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Input {
        var inp = Input{ .history = .empty, .seq_buf = .empty, .allocator = allocator };
        // default bindings — Scratch WASD + arrows + space
        inp.bind(.left, .{ .key = 0x25 }); // LEFT
        inp.bind(.left, .{ .key = 'A' });
        inp.bind(.right, .{ .key = 0x27 }); // RIGHT
        inp.bind(.right, .{ .key = 'D' });
        inp.bind(.up, .{ .key = 0x26 });
        inp.bind(.up, .{ .key = 'W' });
        inp.bind(.down, .{ .key = 0x28 });
        inp.bind(.down, .{ .key = 'S' });
        inp.bind(.jump, .{ .key = win.VK_SPACE });
        inp.bind(.jump, .{ .key = 'W' });
        inp.bind(.run, .{ .key = 0x10 }); // SHIFT
        inp.bind(.shoot, .{ .key = win.VK_SPACE });
        inp.bind(.reset, .{ .key = 'R' });
        inp.bind(.pause, .{ .key = win.VK_ESCAPE });
        return inp;
    }
    pub fn deinit(self: *Input) void {
        self.history.deinit(self.allocator);
        self.seq_buf.deinit(self.allocator);
        self.delay_queue.deinit(self.allocator);
    }
    pub fn setDelay(self: *Input, d: u32) void { self.delay = @min(d, 6); }
    pub fn bind(self: *Input, act: Action, b: Binding) void {
        const idx = @as(usize, @intFromEnum(act));
        for (&self.bindings[idx]) |*slot| {
            if (slot.* == null) { slot.* = b; return; }
        }
        // replace first if full
        self.bindings[idx][0] = b;
    }
    // call each frame with raw window poll — deterministic
    pub fn update(self: *Input, dt: f32, pollFn: *const fn (usize) bool) void {
        // first gather raw down per action
        var raw: [16]bool = [_]bool{false} ** 16;
        for (0..16) |a| {
            var is_down = false;
            for (self.bindings[a]) |mb| {
                if (mb) |b| switch (b) {
                    .key => |vk| { if (pollFn(vk)) is_down = true; },
                };
            }
            raw[a] = is_down;
        }
        // apply local input delay (fighting-game style) — tunable via setDelay
        var effective = raw;
        if (self.delay > 0) {
            self.delay_queue.append(self.allocator, raw) catch {};
            if (self.delay_queue.items.len > 64) _ = self.delay_queue.orderedRemove(0);
            if (self.delay_queue.items.len > self.delay) {
                effective = self.delay_queue.items[self.delay_queue.items.len - self.delay - 1];
            } else {
                // first delay frames: no input yet (delay buffering)
                effective = [_]bool{false} ** 16;
            }
        }
        var any_pressed: [16]bool = [_]bool{false} ** 16;
        // evaluate bindings
        for (0..@as(usize, @intCast(@intFromEnum(Action._count)))) |a| {
            const prev_down = self.states[a].down;
            const is_down = effective[a];
            const is_pressed = is_down and !prev_down;
            const is_released = !is_down and prev_down;
            self.states[a].down = is_down;
            self.states[a].pressed = is_pressed;
            self.states[a].released = is_released;
            if (is_down) self.states[a].held_time += dt else self.states[a].held_time = 0;
            if (is_pressed) {
                self.states[a].buffer = self.buffer_time;
                any_pressed[a] = true;
                // push to seq
                self.seq_buf.append(self.allocator, @enumFromInt(a)) catch {};
                self.seq_timer = self.combo_window;
                if (self.seq_buf.items.len > 8) _ = self.seq_buf.orderedRemove(0);
            } else if (self.states[a].buffer > 0) self.states[a].buffer -= dt;
            if (self.states[a].buffer < 0) self.states[a].buffer = 0;
        }
        // history for replay (keep 120 frames)
        var frame: [16]bool = [_]bool{false} ** 16;
        for (0..16) |i| frame[i] = self.states[i].down;
        self.history.append(self.allocator, frame) catch {};
        if (self.history.items.len > 120) _ = self.history.orderedRemove(0);
        self.seq_timer -= dt;
        if (self.seq_timer <= 0) self.seq_buf.clearRetainingCapacity();
    }

    pub fn updateWindow(self: *Input, winw: *@import("../platform/window.zig").Window, dt: f32) void {
        const poll = struct {
            var w: *@import("../platform/window.zig").Window = undefined;
            fn f(vk: usize) bool { return w.isKeyDown(vk); }
        };
        poll.w = winw;
        self.update(dt, &poll.f);
    }
    // Queries — buffered variants beat raw polling
    pub fn down(self: Input, act: Action) bool {
        return self.states[@intFromEnum(act)].down;
    }
    pub fn pressed(self: Input, act: Action) bool {
        return self.states[@intFromEnum(act)].pressed;
    }
    pub fn buffered(self: Input, act: Action) bool {
        return self.states[@intFromEnum(act)].buffer > 0;
    }
    pub fn consumeBuffer(self: *Input, act: Action) bool {
        if (self.buffered(act)) {
            self.states[@intFromEnum(act)].buffer = 0;
            return true;
        }
        return false;
    }
    pub fn held(self: Input, act: Action) f32 {
        return self.states[@intFromEnum(act)].held_time;
    }
    pub fn chord(self: Input, a: Action, b: Action) bool {
        return self.down(a) and self.down(b);
    }
    pub fn axis(self: Input, neg: Action, pos: Action) f32 {
        var v: f32 = 0;
        if (self.down(neg)) v -= 1;
        if (self.down(pos)) v += 1;
        return v;
    }
    // Sequence test e.g. down, right, jump
    pub fn sequence(self: Input, acts: []const Action) bool {
        if (acts.len > self.seq_buf.items.len) return false;
        const start = self.seq_buf.items.len - acts.len;
        for (acts, 0..) |act, i| if (self.seq_buf.items[start + i] != act) return false;
        return self.seq_timer > 0;
    }
    pub fn clearBuffer(self: *Input, act: Action) void {
        self.states[@intFromEnum(act)].buffer = 0;
        self.states[@intFromEnum(act)].pressed = false;
    }
};

test "input buffered jump" {
    const gpa = std.testing.allocator;
    var inp = Input.init(gpa);
    defer inp.deinit();
    // simulate press via pollFn
    var fake_down: [256]bool = [_]bool{false} ** 256;
    fake_down[win.VK_SPACE] = true;
    const poll = struct {
        var store: [256]bool = undefined;
        fn f(vk: usize) bool { return store[vk & 0xFF]; }
    };
    poll.store = fake_down;
    inp.update(0.016, &poll.f);
    try std.testing.expect(inp.pressed(.jump));
    try std.testing.expect(inp.buffered(.jump));
    // consume
    try std.testing.expect(inp.consumeBuffer(.jump));
    try std.testing.expect(!inp.buffered(.jump));
}

test "input axis and chord" {
    const gpa = std.testing.allocator;
    var inp = Input.init(gpa);
    defer inp.deinit();
    var fake: [256]bool = [_]bool{false} ** 256;
    fake['A'] = true;
    fake['D'] = true;
    const poll = struct {
        var s: [256]bool = undefined;
        fn f(vk: usize) bool { return s[vk & 0xFF]; }
    };
    poll.s = fake;
    inp.update(0.016, &poll.f);
    try std.testing.expect(inp.chord(.left, .right));
    try std.testing.expectEqual(@as(f32, 0), inp.axis(.left, .right));
}

test "input delay 2 cuts immediate response" {
    const gpa = std.testing.allocator;
    var inp = Input.init(gpa);
    defer inp.deinit();
    inp.setDelay(2);
    var fake: [256]bool = [_]bool{false} ** 256;
    fake[win.VK_SPACE] = true;
    const poll = struct {
        var s: [256]bool = undefined;
        fn f(vk: usize) bool { return s[vk & 0xFF]; }
    };
    poll.s = fake;
    inp.update(0.016, &poll.f); // frame 0 — delayed, not yet
    try std.testing.expect(!inp.down(.jump));
    inp.update(0.016, &poll.f); // frame 1 — still delayed
    try std.testing.expect(!inp.down(.jump));
    inp.update(0.016, &poll.f); // frame 2 — now effective from frame 0
    try std.testing.expect(inp.down(.jump));
}
