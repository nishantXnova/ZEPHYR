const std = @import("std");
const Texture = @import("texture.zig").Texture;
const Batch = @import("batch.zig").Batch;
const Color = @import("color.zig").Color;

// Scratch-like sprite, but Zig-powerful: sheets + animations + flip

pub const Frame = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

pub const SpriteSheet = struct {
    tex: *Texture,
    frame_w: f32,
    frame_h: f32,
    cols: u32,
    rows: u32,

    pub fn init(tex: *Texture, frame_w: f32, frame_h: f32) SpriteSheet {
        const cols: u32 = @intFromFloat(@as(f32, @floatFromInt(tex.w)) / frame_w);
        const rows: u32 = @intFromFloat(@as(f32, @floatFromInt(tex.h)) / frame_h);
        return .{ .tex = tex, .frame_w = frame_w, .frame_h = frame_h, .cols = cols, .rows = rows };
    }
    pub fn frame(self: SpriteSheet, index: usize) Frame {
        const col = index % self.cols;
        const row = index / self.cols;
        return .{
            .x = @as(f32, @floatFromInt(col)) * self.frame_w,
            .y = @as(f32, @floatFromInt(row)) * self.frame_h,
            .w = self.frame_w,
            .h = self.frame_h,
        };
    }
};

pub const Animation = struct {
    name: []const u8,
    frames: []const usize, // indices into sheet
    fps: f32,
    loop: bool = true,

    pub fn duration(self: Animation) f32 {
        return @as(f32, @floatFromInt(self.frames.len)) / self.fps;
    }
};

pub const Animator = struct {
    sheet: SpriteSheet,
    anims: std.StringHashMap(Animation),
    current: ?Animation = null,
    time: f32 = 0,
    playing: bool = true,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, sheet: SpriteSheet) Animator {
        return .{
            .sheet = sheet,
            .anims = std.StringHashMap(Animation).init(allocator),
            .allocator = allocator,
        };
    }
    pub fn deinit(self: *Animator) void {
        self.anims.deinit();
    }
    pub fn add(self: *Animator, anim: Animation) !void {
        try self.anims.put(anim.name, anim);
    }
    pub fn play(self: *Animator, name: []const u8) void {
        if (self.anims.get(name)) |a| {
            if (self.current) |c| if (std.mem.eql(u8, c.name, name)) return;
            self.current = a;
            self.time = 0;
            self.playing = true;
        }
    }
    pub fn update(self: *Animator, dt: f32) void {
        if (!self.playing) return;
        if (self.current) |c| {
            self.time += dt;
            if (self.time >= c.duration() and c.loop) self.time = @mod(self.time, c.duration());
            if (self.time >= c.duration() and !c.loop) {
                self.time = c.duration();
                self.playing = false;
            }
        }
    }
    pub fn currentFrame(self: Animator) ?Frame {
        const c = self.current orelse return null;
        if (c.frames.len == 0) return null;
        const idx_f = self.time * c.fps;
        var idx: usize = @intFromFloat(@floor(idx_f));
        if (idx >= c.frames.len) idx = c.frames.len - 1;
        return self.sheet.frame(c.frames[idx]);
    }
    pub fn draw(self: Animator, batch: *Batch, x: f32, y: f32, tint: Color) void {
        if (self.currentFrame()) |f| {
            batch.drawTextureEx(self.sheet.tex, x, y, f.w, f.h, f.x, f.y, f.w, f.h, tint);
        }
    }
    pub fn drawEx(self: Animator, batch: *Batch, x: f32, y: f32, w: f32, h: f32, tint: Color, flip_x: bool) void {
        if (self.currentFrame()) |f| {
            const uw = if (flip_x) -f.w else f.w;
            const uu0c = (if (flip_x) f.x + f.w else f.x) / @as(f32, @floatFromInt(self.sheet.tex.w));
            const uu1c = (if (flip_x) f.x else f.x + f.w) / @as(f32, @floatFromInt(self.sheet.tex.w));
            batch.drawRectUV(x, y, w, h, uu0c, f.y / @as(f32, @floatFromInt(self.sheet.tex.h)), uu1c, (f.y+f.h)/@as(f32,@floatFromInt(self.sheet.tex.h)), tint, self.sheet.tex);
            _ = uw;
        }
    }
};

// Simple single-sprite (Scratch costume-like) — no animation
pub const Sprite = struct {
    tex: *Texture,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    tint: Color = Color.white,
    flip_x: bool = false,

    pub fn draw(self: Sprite, batch: *Batch) void {
        if (self.flip_x) {
            // flipped UV
            batch.drawRectUV(self.x, self.y, self.w, self.h, 1, 0, 0, 1, self.tint, self.tex);
        } else batch.drawTexture(self.tex, self.x, self.y, self.w, self.h);
    }
};
