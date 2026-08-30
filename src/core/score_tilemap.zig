const std = @import("std");
const Batch = @import("../gfx/batch.zig").Batch;
const Texture = @import("../gfx/texture.zig").Texture;
const Color = @import("../gfx/color.zig").Color;

// Score Tilemap UI — digit rendering via tileset (digits.png 12×1 tiles 16px)
// GIDs: 1-10 = 0-9, 11 = ':', 12 = '-' (blank)
// Beats Scratch's text block: tile-based, batched, camera-independent.

pub const ScoreBoard = struct {
    tex: *Texture,
    tile_w: u32 = 16,
    tile_h: u32 = 16,
    x: f32,
    y: f32,
    digits: u32 = 6, // zero-padded

    pub fn draw(self: ScoreBoard, batch: *Batch, score: u32) void {
        var s = score;
        var i: i32 = @intCast(self.digits - 1);
        while (i >= 0) : (i -= 1) {
            const d: u32 = s % 10;
            s /= 10;
            const gid = d + 1; // 1-indexed
            const sx = (gid - 1) * self.tile_w;
            const dx = self.x + @as(f32, @floatFromInt(@as(u32, @intCast(i)) * self.tile_w));
            batch.drawTextureEx(self.tex, dx, self.y, @floatFromInt(self.tile_w), @floatFromInt(self.tile_h), @floatFromInt(sx), 0, @floatFromInt(self.tile_w), @floatFromInt(self.tile_h), Color.white);
        }
    }
    pub fn drawLabel(self: ScoreBoard, batch: *Batch, label_gid: u32, offset_x: f32) void {
        // for "SCORE:" colon tile 11 at offset
        const sx = (label_gid - 1) * self.tile_w;
        batch.drawTextureEx(self.tex, self.x + offset_x, self.y, @floatFromInt(self.tile_w), @floatFromInt(self.tile_h), @floatFromInt(sx), 0, @floatFromInt(self.tile_w), @floatFromInt(self.tile_h), Color.white);
    }
};

// Generic digit tileset helper
pub fn drawDigits(batch: *Batch, tex: *Texture, x: f32, y: f32, value: u32, pad: u32) void {
    const sb = ScoreBoard{ .tex = tex, .x = x, .y = y, .digits = pad };
    sb.draw(batch, value);
}
