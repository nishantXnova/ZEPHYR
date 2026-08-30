const std = @import("std");
const Batch = @import("../gfx/batch.zig").Batch;
const Texture = @import("../gfx/texture.zig").Texture;

// Simple tilemap — beats Scratch's stage: tile-based world with tileset + layer + camera culling.
// Supports Tiled JSON (from Tiled editor) and code-generated.

pub const Tilemap = struct {
    w: u32,
    h: u32,
    tile_w: u32,
    tile_h: u32,
    tiles: []u32, // GIDs (0 = empty), row-major
    tileset: *Texture,
    tileset_cols: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, w: u32, h: u32, tile_w: u32, tile_h: u32, tileset: *Texture) !Tilemap {
        const tiles = try allocator.alloc(u32, w * h);
        @memset(tiles, 0);
        const cols: u32 = @intFromFloat(@as(f32, @floatFromInt(tileset.w)) / @as(f32, @floatFromInt(tile_w)));
        return .{ .w = w, .h = h, .tile_w = tile_w, .tile_h = tile_h, .tiles = tiles, .tileset = tileset, .tileset_cols = cols, .allocator = allocator };
    }
    pub fn deinit(self: *Tilemap) void {
        self.allocator.free(self.tiles);
    }
    pub fn set(self: *Tilemap, x: u32, y: u32, gid: u32) void {
        if (x >= self.w or y >= self.h) return;
        self.tiles[y * self.w + x] = gid;
    }
    pub fn get(self: Tilemap, x: u32, y: u32) u32 {
        if (x >= self.w or y >= self.h) return 0;
        return self.tiles[y * self.w + x];
    }

    // Load Tiled JSON exported map (expects one tilelayer)
    pub fn loadJson(allocator: std.mem.Allocator, path: []const u8, tileset: *Texture) !Tilemap {
        const data = try std.fs.cwd().readFileAlloc(allocator, path, 8 * 1024 * 1024);
        defer allocator.free(data);
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, data, .{});
        defer parsed.deinit();
        const root = parsed.value.object;
        const w = @as(u32, @intFromFloat(root.get("width").?.integer));
        // Actually Tiled json stores width/height as integer
        // Use integer field correctly:
        const width: u32 = @intCast(root.get("width").?.integer);
        const height: u32 = @intCast(root.get("height").?.integer);
        const tilewidth: u32 = @intCast(root.get("tilewidth").?.integer);
        const tileheight: u32 = @intCast(root.get("tileheight").?.integer);
        const layers = root.get("layers").?.array;
        var tile_data: ?[]const u32 = null;
        // find first tilelayer
        for (layers.items) |layer| {
            const typ = layer.object.get("type").?.string;
            if (std.mem.eql(u8, typ, "tilelayer")) {
                const arr = layer.object.get("data").?.array;
                const n = arr.items.len;
                const out = try allocator.alloc(u32, n);
                for (arr.items, 0..) |v, i| out[i] = @intCast(v.integer);
                tile_data = out;
                break;
            }
        }
        if (tile_data == null) return error.NoTileLayer;
        const map = try Tilemap.init(allocator, width, height, tilewidth, tileheight, tileset);
        @memcpy(map.tiles, tile_data.?);
        allocator.free(tile_data.?);
        _ = w;
        return map;
    }

    // Lightweight JSON via std.json — fallback simple parser for Scratch-level simplicity
    pub fn loadJsonSimple(allocator: std.mem.Allocator, json_text: []const u8, tileset: *Texture) !Tilemap {
        // Expects format: {"width":10,"height":8,"tilewidth":16,"tileheight":16,"data":[0,1,2,...]}
        const T = struct { width: u32, height: u32, tilewidth: u32, tileheight: u32, data: []u32 };
        const parsed = try std.json.parseFromSlice(T, allocator, json_text, .{});
        defer parsed.deinit();
        const v = parsed.value;
        var map = try Tilemap.init(allocator, v.width, v.height, v.tilewidth, v.tileheight, tileset);
        if (v.data.len != map.tiles.len) {
            // allow mismatch — copy min
            const n = @min(v.data.len, map.tiles.len);
            @memcpy(map.tiles[0..n], v.data[0..n]);
            allocator.free(v.data);
        } else {
            @memcpy(map.tiles, v.data);
            allocator.free(v.data);
        }
        return map;
    }

    pub fn draw(self: Tilemap, batch: *Batch) void {
        self.drawCamera(batch, 0, 0, 9999, 9999);
    }
    pub fn drawCamera(self: Tilemap, batch: *Batch, cam_x: f32, cam_y: f32, view_w: f32, view_h: f32) void {
        const start_x: u32 = if (cam_x < 0) 0 else @as(u32, @intFromFloat(@floor(cam_x / @as(f32, @floatFromInt(self.tile_w)))));
        const start_y: u32 = if (cam_y < 0) 0 else @as(u32, @intFromFloat(@floor(cam_y / @as(f32, @floatFromInt(self.tile_h)))));
        const end_x: u32 = @min(self.w, start_x + @as(u32, @intFromFloat(@ceil(view_w / @as(f32, @floatFromInt(self.tile_w))))) + 2);
        const end_y: u32 = @min(self.h, start_y + @as(u32, @intFromFloat(@ceil(view_h / @as(f32, @floatFromInt(self.tile_h))))) + 2);
        for (start_y..end_y) |y| {
            for (start_x..end_x) |x| {
                const gid = self.get(@intCast(x), @intCast(y));
                if (gid == 0) continue;
                const id = gid - 1;
                const sx = (id % self.tileset_cols) * self.tile_w;
                const sy = (id / self.tileset_cols) * self.tile_h;
                const dx: f32 = @as(f32, @floatFromInt(x * self.tile_w));
                const dy: f32 = @as(f32, @floatFromInt(y * self.tile_h));
                batch.drawTextureEx(self.tileset, dx, dy, @floatFromInt(self.tile_w), @floatFromInt(self.tile_h), @floatFromInt(sx), @floatFromInt(sy), @floatFromInt(self.tile_w), @floatFromInt(self.tile_h), @import("../gfx/color.zig").Color.white);
            }
        }
    }
};
