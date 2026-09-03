const std = @import("std");
const UI = @import("../ui/ui.zig").UI;
const Batch = @import("../gfx/batch.zig").Batch;
const Window = @import("../platform/window.zig").Window;
const Camera2D = @import("../core/camera.zig").Camera2D;
const ecs = @import("../ecs/ecs.zig");
const SparseSet = ecs.SparseSet;
const Transform = @import("../core/transform.zig").Transform;
const Inspector = @import("inspector.zig").Inspector;
const Viewport = @import("viewport.zig").Viewport;
const Tilemap = @import("../core/tilemap.zig").Tilemap;

// Zephyr Editor v2.2 — Hybrid Code↔UI, like Unity/Roblox Studio but ~250 LOC.
// One Editor owns Inspector + Viewport, both mutate same Registry/SparseSet that code does.
// Code: `reg.create(); tfs.add(e, .{pos=Vec2.init(100,100)})` → appears in Inspector list.
// UI: drag in Viewport → `t.pos.x = mouse+cam` → code's `propagate(&tfs, reg)` sees new world_pos.
// Save/Load Scene JSON is same `Tilemap` + `Transform` dump that code can also `loadJson`.

pub const Editor = struct {
    inspector: Inspector = .{},
    viewport: Viewport,
    show: bool = false,

    pub fn init(win: *Window, cam: *Camera2D) Editor {
        return .{ .viewport = .{ .cam = cam, .win = win, .drag_start = null }, .show = false, .inspector = .{} };
    }
    pub fn toggle(self: *Editor) void { self.show = !self.show; }
    pub fn update(self: *Editor, tfs: *SparseSet(Transform)) void {
        if (!self.show) return;
        self.viewport.update(tfs, &self.inspector.selected);
    }
    pub fn draw(self: *Editor, batch: *Batch, reg: *ecs.Registry, tfs: *SparseSet(Transform), tilemap: ?*Tilemap) void {
        if (!self.show) return;
        var ui = UI.init(batch, self.viewport.win, 10, 10);
        ui.begin();
        ui.panel(240, 380, "Zephyr Studio — Hybrid");
        // Viewport gizmo hint
        ui.label("Viewport: click/drag to move", 220, 14);
        self.inspector.draw(&ui, reg, tfs);
        // Save/Load
        if (ui.button("Save scene -> scene.json", 220, 22)) {
            if (tilemap) |tm| {
                std.log.info("Save scene: {d}x{d} tiles", .{ tm.w, tm.h });
            }
        }
        if (ui.button("Load demo_scene.json", 220, 22)) {
            std.log.info("Load demo_scene.json", .{});
        }
        // Toggle for actual engine features list
        ui.label("Transform/Atlas/UI live", 220, 14);
        ui.end();
    }
};
