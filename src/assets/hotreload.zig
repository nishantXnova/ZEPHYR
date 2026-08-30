//! Hot-reload — polling + pluggable. Lightweight.
//! Call `AssetManager.poll()` each frame; it checks mtimes and marks dirty.
//! Pluggable: file reload is stubbed to avoid std.fs API churn in Zig 0.16 (now std.Io).
const std = @import("std");

pub const AssetHandle = u32;

fn hashPath(path: []const u8) u64 {
    var h: u64 = 14695981039346656037;
    for (path) |c| {
        h ^= c;
        h *%= 1099511628211;
    }
    return h;
}

pub const AssetEntry = struct {
    path: []u8,
    version: u32 = 1,
    dirty: bool = false,
};

pub const AssetManager = struct {
    allocator: std.mem.Allocator,
    entries: std.AutoHashMap(u64, AssetEntry),
    tick: u64 = 0,
    poll_interval: u64 = 30,

    pub fn init(allocator: std.mem.Allocator) AssetManager {
        return .{
            .allocator = allocator,
            .entries = std.AutoHashMap(u64, AssetEntry).init(allocator),
        };
    }
    pub fn deinit(self: *AssetManager) void {
        var it = self.entries.iterator();
        while (it.next()) |kv| {
            self.allocator.free(kv.value_ptr.path);
        }
        self.entries.deinit();
    }

    pub fn load(self: *AssetManager, path: []const u8) !AssetHandle {
        const h = hashPath(path);
        if (self.entries.contains(h)) return @truncate(h);
        const owned = try self.allocator.dupe(u8, path);
        try self.entries.put(h, .{ .path = owned, .version = 1 });
        return @truncate(h);
    }

    pub fn isDirty(self: *AssetManager, handle: AssetHandle) bool {
        const e = self.entries.get(@as(u64, handle)) orelse return false;
        return e.dirty;
    }
    pub fn clearDirty(self: *AssetManager, handle: AssetHandle) void {
        if (self.entries.getPtr(@as(u64, handle))) |e| e.dirty = false;
    }
    pub fn markDirty(self: *AssetManager, handle: AssetHandle) void {
        if (self.entries.getPtr(@as(u64, handle))) |e| {
            e.dirty = true;
            e.version += 1;
        }
    }

    /// Call each frame. Returns number of assets marked dirty (stub — wire to OS watcher later).
    /// To actually hot-reload a texture, call `markDirty` when you detect change externally,
    /// or extend this to use `std.Io` + `Dir.stat` when std stabilizes.
    pub fn poll(self: *AssetManager) usize {
        self.tick += 1;
        // stub: no FS poll by default to avoid Zig 0.16 std.fs breakage
        // extend: use std.Io.Dir + stat here if needed
        if (self.tick % self.poll_interval != 0) return 0;
        return 0;
    }
};

test "asset hotreload init" {
    const gpa = std.testing.allocator;
    var am = AssetManager.init(gpa);
    defer am.deinit();
    const h = try am.load("assets/score.txt");
    try std.testing.expect(!am.isDirty(h));
    am.markDirty(h);
    try std.testing.expect(am.isDirty(h));
}
