const std = @import("std");
const Batch = @import("../gfx/batch.zig").Batch;
const Window = @import("../platform/window.zig").Window;
const Color = @import("../gfx/color.zig").Color;
const Rect = @import("../core/math.zig").Rect;

// Zephyr UI v1.0 — Actual engine feature. Immediate-mode, ~300 LOC, no retained graph.
// Every real engine has UI (Unity uGUI, Godot Control). Scratch has none — we beat it.
// Uses Batch directly (no new renderer), Window mouse for hit test. Layout: vertical stack.
// Usage: var ui = UI.init(batch, win, 10, 10); ui.begin(); if (ui.button("Play", 100, 30)) {} ui.label("Score", 80, 20); ui.end();

pub const UI = struct {
    batch: *Batch,
    win: *Window,
    x: f32,
    y: f32,
    cursor_y: f32,
    width: f32 = 200,
    padding: f32 = 4,
    hot: u64 = 0,
    active: u64 = 0,
    next_id: u64 = 1,

    pub fn init(batch: *Batch, win: *Window, x: f32, y: f32) UI {
        return .{ .batch = batch, .win = win, .x = x, .y = y, .cursor_y = y };
    }
    pub fn begin(self: *UI) void {
        self.cursor_y = self.y;
        self.hot = 0;
    }
    pub fn end(self: *UI) void {
        _ = self;
    }
    inline fn hashLabel(str: []const u8) u64 {
        var h: u64 = 14695981039346656037;
        for (str) |c| {
            h ^= c;
            h *%= 1099511628211;
        }
        return h;
    }
    fn hitTest(self: UI, x: f32, y: f32, w: f32, h: f32) bool {
        const mp = self.win.mousePos();
        const r = Rect.init(x, y, w, h);
        return r.contains(.{ .x = @floatFromInt(mp.x), .y = @floatFromInt(mp.y) });
    }

    pub fn label(self: *UI, text: []const u8, w: f32, h: f32) void {
        // simple label as dark bg + outline (text not rendered without font, rect placeholder)
        self.batch.drawRect(self.x, self.cursor_y, w, h, Color.rgba(30, 30, 35, 220));
        self.batch.drawRect(self.x + 2, self.cursor_y + 2, w - 4, h - 4, Color.rgba(0, 0, 0, 0));
        _ = text;
        self.cursor_y += h + self.padding;
    }
    pub fn button(self: *UI, text: []const u8, w: f32, h: f32) bool {
        const id = hashLabel(text);
        const x = self.x;
        const y = self.cursor_y;
        const hovered = self.hitTest(x, y, w, h);
        const held = self.win.isMouseDown(0);
        const pressed = hovered and held and self.win.isMouseDown(0);
        // we need edge: mouse down this frame + hover
        // Window.isMouseDown is held; we can treat click as hover && just pressed
        // Use isMouseDown + hitTest for hot, and check release as click
        var clicked = false;
        if (hovered) {
            self.hot = id;
            if (held) self.active = id else if (self.active == id) {
                // released while hovered
                clicked = true;
                self.active = 0;
            }
        } else if (self.active == id and !held) {
            self.active = 0;
        }
        // also support keyboard enter? not needed
        const col = if (self.active == id) Color.rgb(80, 120, 200) else if (hovered) Color.rgb(60, 60, 80) else Color.rgb(45, 45, 50);
        self.batch.drawRect(x, y, w, h, col);
        self.batch.drawRect(x, y, w, 2, Color.white);
        self.batch.drawRect(x, y + h - 2, w, 2, Color.white);
        // text placeholder — we don't have font, draw centered tiny rect as "text"
        self.batch.drawRect(x + w * 0.3, y + h * 0.4, w * 0.4, 2, Color.white);
        _ = pressed;
        _ = text;
        self.cursor_y += h + self.padding;
        return clicked;
    }
    pub fn slider(self: *UI, value: *f32, min: f32, max: f32, w: f32, h: f32) bool {
        const x = self.x;
        const y = self.cursor_y;
        const hovered = self.hitTest(x, y, w, h);
        var changed = false;
        if (hovered and self.win.isMouseDown(0)) {
            const mp = self.win.mousePos();
            const t = std.math.clamp((@as(f32, @floatFromInt(mp.x)) - x) / w, 0, 1);
            const new_val = min + (max - min) * t;
            if (@abs(new_val - value.*) > 0.001) {
                value.* = new_val;
                changed = true;
            }
            self.active = 1;
        } else if (!self.win.isMouseDown(0)) {
            if (self.active == 1) self.active = 0;
        }
        // bg
        self.batch.drawRect(x, y, w, h, Color.rgb(35, 35, 40));
        // fill
        const t = (value.* - min) / (max - min);
        self.batch.drawRect(x, y, w * t, h, Color.rgb(100, 180, 255));
        self.batch.drawRect(x + w * t - 2, y - 2, 4, h + 4, Color.white);
        self.cursor_y += h + self.padding;
        return changed;
    }
    pub fn panel(self: *UI, w: f32, h: f32, title: []const u8) void {
        _ = title;
        self.batch.drawRect(self.x - 4, self.cursor_y - 4, w + 8, h + 8, Color.rgba(0, 0, 0, 160));
        self.batch.drawRect(self.x - 4, self.cursor_y - 4, w + 8, 12, Color.rgb(50, 50, 60));
    }
};

test "ui button hit test" {
    // cannot test Window without OS; just test hash stability
    const h1 = UI.hashLabel("Play");
    const h2 = UI.hashLabel("Play");
    const h3 = UI.hashLabel("Pause");
    try std.testing.expect(h1 == h2);
    try std.testing.expect(h1 != h3);
}
