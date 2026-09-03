const std = @import("std");
const Window = @import("../platform/window.zig").Window;
const Camera2D = @import("../core/camera.zig").Camera2D;
const ecs = @import("../ecs/ecs.zig");
const Entity = ecs.Entity;
const SparseSet = ecs.SparseSet;
const Transform = @import("../core/transform.zig").Transform;
const Rect = @import("../core/math.zig").Rect;

// Zephyr Viewport — Click to select, drag to move, same world_pos that code reads.
// Hybrid: code sets t.pos, Viewport drag mutates same t.pos — no copy.
// Uses Window.mousePos + Camera to world, hit test against Transform world_pos 16x16.

pub const Viewport = struct {
    cam: *Camera2D,
    win: *Window,
    drag_start: ?struct { e: Entity, off_x: f32, off_y: f32 } = null,

    pub fn hitTest(self: Viewport, tfs: SparseSet(Transform), mx: f32, my: f32) ?Entity {
        const wx = mx + self.cam.pos.x;
        const wy = my + self.cam.pos.y;
        var it = tfs.iterator();
        var best: ?Entity = null;
        var best_dist: f32 = 1e9;
        while (it.next()) |kv| {
            const e = kv.entity;
            const t = kv.value;
            const r = Rect.init(t.world_pos.x, t.world_pos.y, 16, 16);
            if (r.contains(.{ .x = wx, .y = wy })) {
                const d = @abs(wx - (t.world_pos.x + 8)) + @abs(wy - (t.world_pos.y + 8));
                if (d < best_dist) { best_dist = d; best = e; }
            }
        }
        return best;
    }
    pub fn update(self: *Viewport, tfs: *SparseSet(Transform), selected: *?Entity) void {
        const mp = self.win.mousePos();
        const mx: f32 = @floatFromInt(mp.x);
        const my: f32 = @floatFromInt(mp.y);
        if (self.win.isMouseDown(0)) {
            if (self.drag_start == null) {
                if (self.hitTest(tfs.*, mx, my)) |e| {
                    selected.* = e;
                    const t = tfs.get(e).?;
                    self.drag_start = .{ .e = e, .off_x = t.pos.x - (mx + self.cam.pos.x), .off_y = t.pos.y - (my + self.cam.pos.y) };
                }
            } else if (self.drag_start) |ds| {
                if (tfs.get(ds.e)) |t| {
                    t.pos.x = mx + self.cam.pos.x + ds.off_x;
                    t.pos.y = my + self.cam.pos.y + ds.off_y;
                    t.dirty = true;
                }
            }
        } else {
            self.drag_start = null;
        }
        // click without drag selects
        if (self.win.isMouseDown(0) and self.drag_start == null) {
            // handled above
        }
    }
};
