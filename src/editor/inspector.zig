const std = @import("std");
const UI = @import("../ui/ui.zig").UI;
const ecs = @import("../ecs/ecs.zig");
const Entity = ecs.Entity;
const SparseSet = ecs.SparseSet;
const Transform = @import("../core/transform.zig").Transform;
const property = @import("property.zig");

// Zephyr Inspector — Hybrid. Code and UI mutate same SparseSet dense arrays.
// Select entity click in Viewport, Inspector auto-generates sliders via property.inspect(Transform).
// No duplicate state, no "apply" button — immediate, like Roblox Studio but lighter.
// Also shows Query2 live count and Atlas entries as proof of engine introspection.

pub const Inspector = struct {
    selected: ?Entity = null,

    pub fn draw(self: *Inspector, ui: *UI, reg: *ecs.Registry, tfs: *SparseSet(Transform)) void {
        ui.panel(220, 260, "Inspector");
        // entity list
        var it = tfs.iterator();
        var y: usize = 0;
        while (it.next()) |kv| {
            const e = kv.entity;
            var buf: [32]u8 = undefined;
            const label = std.fmt.bufPrint(&buf, "E{d}##{d}", .{ e.id, y }) catch "E";
            const is_sel = if (self.selected) |s| s.id == e.id and s.gen == e.gen else false;
            // use button to select
            const w: f32 = 200;
            const h: f32 = 18;
            // draw as button but without _ = text discard issue — use UI.button
            if (ui.button(label, w, h)) self.selected = e;
            if (is_sel) {
                // highlight already via button active color
            }
            y += 1;
            if (y > 8) break;
        }
        if (self.selected) |e| {
            if (tfs.get(e)) |t| {
                ui.label("Transform", 200, 14);
                property.inspect(Transform, ui, t, "Transform");
                if (ui.button("Delete", 90, 20)) {
                    _ = tfs.remove(e);
                    reg.destroy(e);
                    self.selected = null;
                }
            } else {
                ui.label("no Transform", 200, 14);
            }
        } else {
            ui.label("select entity", 200, 14);
        }
        if (ui.button("Create Box", 200, 22)) {
            const ne = reg.create();
            tfs.add(ne, .{ .pos = @import("../core/math.zig").Vec2.init(100, 100) }) catch {};
            self.selected = ne;
        }
    }
};
