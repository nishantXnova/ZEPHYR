//! Sparse-set ECS — lightweight, cache-friendly, Zig comptime.
//! Entity is u32 index + generation. Components stored in typed SparseSets.
const std = @import("std");

pub const Entity = struct {
    id: u32,
    gen: u32,
};

const MAX_ENTITIES = 4096;

pub const Registry = struct {
    allocator: std.mem.Allocator,
    generations: [MAX_ENTITIES]u32 = [_]u32{0} ** MAX_ENTITIES,
    alive: [MAX_ENTITIES]bool = [_]bool{false} ** MAX_ENTITIES,
    free_list: std.ArrayList(u32),
    next_id: u32 = 0,

    // type-erased component storages
    storages: std.StringHashMap(*anyopaque),

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{
            .allocator = allocator,
            .free_list = .empty,
            .storages = std.StringHashMap(*anyopaque).init(allocator),
        };
    }
    pub fn deinit(self: *Registry) void {
        var it = self.storages.iterator();
        while (it.next()) |kv| {
            // storages are *SparseSet(T) boxed; caller must deinit typed storages before registry deinit
            // For now leak-safe: free key, not value (values deinit'd separately if tracked)
            self.allocator.free(kv.key_ptr.*);
        }
        self.storages.deinit();
        self.free_list.deinit(self.allocator);
    }

    pub fn create(self: *Registry) Entity {
        var id: u32 = 0;
        if (self.free_list.items.len > 0) {
            id = self.free_list.pop().?;
        } else {
            id = self.next_id;
            self.next_id += 1;
            if (self.next_id >= MAX_ENTITIES) @panic("ECS out of entities");
        }
        self.alive[id] = true;
        return .{ .id = id, .gen = self.generations[id] };
    }

    pub fn destroy(self: *Registry, e: Entity) void {
        if (!self.isAlive(e)) return;
        self.alive[e.id] = false;
        self.generations[e.id] += 1;
        self.free_list.append(self.allocator, e.id) catch {};
        // Note: components remain in storages until removed; systems should not query dead entities
    }

    pub fn isAlive(self: Registry, e: Entity) bool {
        if (e.id >= MAX_ENTITIES) return false;
        return self.alive[e.id] and self.generations[e.id] == e.gen;
    }
};

// Typed sparse set
pub fn SparseSet(comptime T: type) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        dense: std.ArrayList(T),
        dense_entities: std.ArrayList(Entity),
        sparse: [MAX_ENTITIES]?usize = [_]?usize{null} ** MAX_ENTITIES,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .dense = .empty,
                .dense_entities = .empty,
            };
        }
        pub fn deinit(self: *Self) void {
            self.dense.deinit(self.allocator);
            self.dense_entities.deinit(self.allocator);
        }
        pub fn add(self: *Self, e: Entity, value: T) !void {
            if (self.sparse[e.id] != null) {
                // replace
                const idx = self.sparse[e.id].?;
                self.dense.items[idx] = value;
                return;
            }
            const idx = self.dense.items.len;
            try self.dense.append(self.allocator, value);
            try self.dense_entities.append(self.allocator, e);
            self.sparse[e.id] = idx;
        }
        pub fn get(self: Self, e: Entity) ?*T {
            const idx = self.sparse[e.id] orelse return null;
            if (idx >= self.dense.items.len) return null;
            // check entity match (generation)
            if (self.dense_entities.items[idx].id != e.id or self.dense_entities.items[idx].gen != e.gen) return null;
            return &self.dense.items[idx];
        }
        pub fn has(self: Self, e: Entity) bool {
            return self.get(e) != null;
        }
        pub fn remove(self: *Self, e: Entity) bool {
            const idx = self.sparse[e.id] orelse return false;
            const last = self.dense.items.len - 1;
            if (idx != last) {
                self.dense.items[idx] = self.dense.items[last];
                self.dense_entities.items[idx] = self.dense_entities.items[last];
                self.sparse[self.dense_entities.items[idx].id] = idx;
            }
            _ = self.dense.pop();
            _ = self.dense_entities.pop();
            self.sparse[e.id] = null;
            return true;
        }
        pub fn count(self: Self) usize {
            return self.dense.items.len;
        }
        pub fn iterator(self: Self) Iterator {
            return .{ .set = &self, .index = 0 };
        }
        pub const Iterator = struct {
            set: *const Self,
            index: usize,
            pub fn next(it: *Iterator) ?struct { entity: Entity, value: *T } {
                if (it.index >= it.set.dense.items.len) return null;
                const e = it.set.dense_entities.items[it.index];
                const v = &it.set.dense.items[it.index];
                it.index += 1;
                return .{ .entity = e, .value = v };
            }
        };
    };
}

// Archetype Query — cache-friendly iteration over entities with BOTH A and B.
// Indie engines iterate all entities or hash-miss per lookup. This picks the smaller dense set,
// checks has(other), touches only contiguous dense arrays — Bevy-like but ~30 LOC.
// Usage: var q = Query2(Position,Velocity).init(&posSet, &velSet); while (q.next()) |item| { item.a.x += item.b.x * dt; }
pub fn Query2(comptime A: type, comptime B: type) type {
    return struct {
        a_set: *const SparseSet(A),
        b_set: *const SparseSet(B),
        index: usize = 0,
        // iterate over the smaller set for cache friendliness
        use_a: bool,

        pub fn init(a: *const SparseSet(A), b: *const SparseSet(B)) @This() {
            const use_a = a.count() <= b.count();
            return .{ .a_set = a, .b_set = b, .use_a = use_a };
        }
        pub fn next(self: *@This()) ?struct { entity: Entity, a: *A, b: *B } {
            if (self.use_a) {
                while (self.index < self.a_set.dense.items.len) {
                    const e = self.a_set.dense_entities.items[self.index];
                    const av = &self.a_set.dense.items[self.index];
                    self.index += 1;
                    if (self.b_set.get(e)) |bv| return .{ .entity = e, .a = av, .b = bv };
                }
            } else {
                while (self.index < self.b_set.dense.items.len) {
                    const e = self.b_set.dense_entities.items[self.index];
                    const bv = &self.b_set.dense.items[self.index];
                    self.index += 1;
                    if (self.a_set.get(e)) |av| return .{ .entity = e, .a = av, .b = bv };
                }
            }
            return null;
        }
        pub fn count(self: @This()) usize {
            // approximate — walk count (for tests)
            var n: usize = 0;
            var tmp = self;
            tmp.index = 0;
            while (tmp.next() != null) n += 1;
            return n;
        }
    };
}

// Snapshot — memcpy dense arrays for rollback/save. Extremely clever: dense is contiguous, no pointer chasing.
// Handles rollback in src/net/rollback.zig and save/load via Scene JSON pattern.
pub fn Snapshot(comptime T: type) type {
    return struct {
        data: []T,
        entities: []Entity,
        allocator: std.mem.Allocator,
        pub fn capture(set: SparseSet(T), allocator: std.mem.Allocator) !@This() {
            const d = try allocator.dupe(T, set.dense.items);
            const e = try allocator.dupe(Entity, set.dense_entities.items);
            return .{ .data = d, .entities = e, .allocator = allocator };
        }
        pub fn restore(self: @This(), set: *SparseSet(T)) !void {
            set.dense.clearRetainingCapacity();
            set.dense_entities.clearRetainingCapacity();
            // rebuild sparse map
            for (set.sparse) |*slot| slot.* = null;
            try set.dense.appendSlice(set.allocator, self.data);
            try set.dense_entities.appendSlice(set.allocator, self.entities);
            for (self.entities, 0..) |ent, i| set.sparse[ent.id] = i;
        }
        pub fn deinit(self: @This()) void {
            self.allocator.free(self.data);
            self.allocator.free(self.entities);
        }
    };
}

// Example components for docs/tests
pub const Position = struct { x: f32, y: f32 };
pub const Velocity = struct { x: f32, y: f32 };
pub const Sprite = struct { w: f32, h: f32, color: [4]u8 };

test "ecs create / sparse set" {
    const gpa = std.testing.allocator;
    var reg = Registry.init(gpa);
    defer reg.deinit();
    var pos = SparseSet(Position).init(gpa);
    defer pos.deinit();
    const e = reg.create();
    try pos.add(e, .{ .x = 10, .y = 20 });
    try std.testing.expect(pos.has(e));
    try std.testing.expectEqual(@as(f32, 10), pos.get(e).?.x);
    const e2 = reg.create();
    try std.testing.expect(!pos.has(e2));
}

test "query2 archetype iteration" {
    const gpa = std.testing.allocator;
    var reg = Registry.init(gpa);
    defer reg.deinit();
    var pos = SparseSet(Position).init(gpa);
    defer pos.deinit();
    var vel = SparseSet(Velocity).init(gpa);
    defer vel.deinit();
    const e1 = reg.create(); try pos.add(e1, .{ .x = 0, .y = 0 }); try vel.add(e1, .{ .x = 1, .y = 0 });
    const e2 = reg.create(); try pos.add(e2, .{ .x = 5, .y = 5 }); // no vel
    const e3 = reg.create(); try pos.add(e3, .{ .x = 2, .y = 2 }); try vel.add(e3, .{ .x = 0, .y = 1 });
    var q = Query2(Position, Velocity).init(&pos, &vel);
    var n: usize = 0;
    while (q.next()) |kv| { _ = kv; n += 1; }
    try std.testing.expectEqual(@as(usize, 2), n);
}

test "snapshot restore" {
    const gpa = std.testing.allocator;
    var pos = SparseSet(Position).init(gpa);
    defer pos.deinit();
    var reg = Registry.init(gpa);
    defer reg.deinit();
    const e = reg.create(); try pos.add(e, .{ .x = 10, .y = 20 });
    const snap = try Snapshot(Position).capture(pos, gpa);
    defer snap.deinit();
    // mutate
    pos.get(e).?.x = 99;
    try std.testing.expectEqual(@as(f32, 99), pos.get(e).?.x);
    try snap.restore(&pos);
    try std.testing.expectEqual(@as(f32, 10), pos.get(e).?.x);
}
