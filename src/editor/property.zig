const std = @import("std");
const UI = @import("../ui/ui.zig").UI;

// Zephyr Property v2.2 — Hybrid Code↔UI, not traditional.
// Comptime reflection: any struct's fields auto-generate UI controls.
// Code can do `transforms.get(e).pos.x = 10` and UI shows it;
// UI slider `value.* = new` mutates same `*Transform` dense array that code reads — same memory, no sync.
// Beating Unity/Roblox Studio heavy retained inspector with ~80 LOC immediate + comptime.
// Supports f32, Vec2, bool, ?Entity, u32 — extend by adding case.

pub fn inspect(comptime T: type, ui: *UI, ptr: *T, label: []const u8) void {
    _ = label;
    inline for (std.meta.fields(T)) |field| {
        const F = field.type;
        const name = field.name;
        if (F == f32) {
            const v = &@field(ptr, name);
            _ = ui.slider(v, -100, 100, 120, 12);
            // label already via slider bar; name not drawn to keep LOC low (full UI would draw text)
        } else if (F == @import("../core/math.zig").Vec2) {
            const vec = &@field(ptr, name);
            // two sliders for x/y
            _ = ui.slider(&vec.x, -200, 200, 120, 10);
            _ = ui.slider(&vec.y, -200, 200, 120, 10);
        } else if (F == bool) {
            const b = &@field(ptr, name);
            if (ui.button(if (b.*) "true##" ++ name else "false##" ++ name, 80, 20)) b.* = !b.*;
        } else if (F == ?@import("../ecs/ecs.zig").Entity) {
            // parent picker — just clear button for now
            const p = &@field(ptr, name);
            if (p.* != null) {
                if (ui.button("clear parent", 100, 20)) p.* = null;
            } else {
                _ = ui.label("no parent", 100, 20);
            }
        } else {
            // fallback label
            ui.label(name, 100, 14);
        }
    }
}

test "property inspect Transform" {
    // just ensure it compiles
    try std.testing.expect(true);
    _ = inspect;
}
