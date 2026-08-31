const std = @import("std");
const Batch = @import("../gfx/batch.zig").Batch;
const Texture = @import("../gfx/texture.zig").Texture;
const Tilemap = @import("tilemap.zig").Tilemap;
const Color = @import("../gfx/color.zig").Color;

// Zephyr Scene — scratch-simple JSON, full control, ultra-lightweight.
// One file = one level. No editor needed. Beats Scratch stage list.
// Reuses Tilemap.loadJsonSimple + Tilemap.drawCamera (culling).

pub const Spawn = struct {
    x: f32,
    y: f32,
    kind: u32 = 0, // 0=player,1=enemy,2=coin,3=goal
};

pub const Scene = struct {
    name: []const u8 = "untitled",
    tilemap: Tilemap,
    spawns: std.ArrayList(Spawn),
    bg: Color = Color.rgb(92, 148, 252),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, w: u32, h: u32, tile_w: u32, tile_h: u32, tileset: *Texture) !Scene {
        const tm = try Tilemap.init(allocator, w, h, tile_w, tile_h, tileset);
        return .{
            .tilemap = tm,
            .spawns = .empty,
            .allocator = allocator,
        };
    }
    pub fn deinit(self: *Scene) void {
        self.tilemap.deinit();
        self.spawns.deinit(self.allocator);
        // name is owned if it was allocated (parseJson dupes), init() uses static literal which we don't free
        // detect by checking if it was heap-allocated: try to free only if not the static literal
        // static literal ptr check is fragile — track via length+ptr of literal
        const static = "untitled";
        if (self.name.ptr != static.ptr or self.name.len != static.len) {
            self.allocator.free(self.name);
        }
    }
    pub fn addSpawn(self: *Scene, s: Spawn) !void {
        try self.spawns.append(self.allocator, s);
    }
    pub fn draw(self: Scene, batch: *Batch, cam_x: f32, cam_y: f32, view_w: f32, view_h: f32) void {
        self.tilemap.drawCamera(batch, cam_x, cam_y, view_w, view_h);
    }
    // --- JSON ---
    // Format: {"name":"level1","width":100,"height":15,"tilewidth":16,"tileheight":16,"bg":[92,148,252],"data":[0,1,...],"spawns":[{"x":40,"y":160,"kind":0},...]}
    const JsonSp = struct { x: f32, y: f32, kind: u32 = 0 };
    const JsonScene = struct {
        name: []const u8 = "untitled",
        width: u32,
        height: u32,
        tilewidth: u32 = 16,
        tileheight: u32 = 16,
        bg: ?[3]u8 = null,
        data: []u32,
        spawns: ?[]JsonSp = null,
    };

    pub fn loadJson(allocator: std.mem.Allocator, path: []const u8, tileset: *Texture) !Scene {
        const data = try std.fs.cwd().readFileAlloc(allocator, path, 8 * 1024 * 1024);
        defer allocator.free(data);
        return try parseJson(allocator, data, tileset);
    }
    pub fn parseJson(allocator: std.mem.Allocator, json_text: []const u8, tileset: *Texture) !Scene {
        const parsed = try std.json.parseFromSlice(JsonScene, allocator, json_text, .{});
        defer parsed.deinit();
        const v = parsed.value;
        var sc = try Scene.init(allocator, v.width, v.height, v.tilewidth, v.tileheight, tileset);
        // copy tiles
        const n = @min(v.data.len, sc.tilemap.tiles.len);
        @memcpy(sc.tilemap.tiles[0..n], v.data[0..n]);
        allocator.free(v.data);
        sc.name = try allocator.dupe(u8, v.name);
        if (v.bg) |c| sc.bg = Color.rgb(c[0], c[1], c[2]);
        if (v.spawns) |sp| {
            for (sp) |s| try sc.spawns.append(allocator, .{ .x = s.x, .y = s.y, .kind = s.kind });
            allocator.free(sp);
        }
        return sc;
    }
    pub fn spawnsOf(self: Scene, kind: u32, out: *std.ArrayList(Spawn)) !void {
        for (self.spawns.items) |s| if (s.kind == kind) try out.append(self.allocator, s);
    }
};

test "scene parse json" {
    // needs a dummy texture — skip if no GL but test parse logic via mini-tileset mock?
    // we test JSON parsing only via Tilemap-like manual init
    const json =
        \\{"name":"test","width":4,"height":2,"tilewidth":16,"tileheight":16,"bg":[10,20,30],"data":[0,1,0,1,1,0,1,0],"spawns":[{"x":40,"y":10,"kind":0},{"x":100,"y":20,"kind":1}]}
    ;
    // create a fake tileset texture struct with w/h only for cols calc — init Tilemap will compute cols = w/tile_w
    // Use a minimal Texture on stack (no GL id needed for this test — only cols calc uses w)
    var fake_tex = Texture{ .id = 0, .w = 64, .h = 16 };
    var sc = try Scene.parseJson(std.testing.allocator, json, &fake_tex);
    defer sc.deinit();
    try std.testing.expectEqual(@as(u32, 4), sc.tilemap.w);
    try std.testing.expectEqual(@as(usize, 2), sc.spawns.items.len);
    try std.testing.expect(sc.tilemap.get(1, 0) == 1);
}
