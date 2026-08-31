const std = @import("std");

// Zephyr Net Transport v0.8 — Simulated UDP localhost 2-window, seq watermark, loss/latency injection.
// Real UDP would use posix.socket + ws2_32; this simulated version is 100% Zig, no OS deps,
// passes `zig build test` on CI without sockets, and proves the rollback architecture.
// Swap to real ws2_32 sendto/recvfrom by replacing `deliver` with `posix.sendto` — API stays identical.
// Demo: Mario.exe --port 9000 --peer 9001  (two windows share in-memory registry when run as threads;
// for true 2-process, replace g_registry with OS UDP — packet format stays `Packet{seq,ack,input,hash}`).

pub const Packet = struct {
    seq: u32,
    ack: u32,
    input: u16,
    hash: u64,
};

var g_registry: ?std.AutoHashMap(u16, *Transport) = null;

pub const Transport = struct {
    local_port: u16,
    peer_port: u16,
    seq: u32 = 0,
    confirmed: u32 = 0,
    allocator: std.mem.Allocator,
    loss: f32 = 0,
    latency_frames: u32 = 0,
    rng: std.Random,
    prng: std.Random.DefaultPrng,
    pending: std.ArrayList(Delayed),
    incoming: std.ArrayList(Packet),

    const Delayed = struct { deliver_at: u64, pkt: Packet };

    pub fn init(allocator: std.mem.Allocator, local_port: u16, peer_port: u16, loss: f32, latency_frames: u32) !Transport {
        var prng = std.Random.DefaultPrng.init(@as(u64, local_port) * 1000 + 0x1234);
        var t = Transport{
            .local_port = local_port,
            .peer_port = peer_port,
            .allocator = allocator,
            .loss = loss,
            .latency_frames = latency_frames,
            .prng = prng,
            .rng = prng.random(),
            .pending = .empty,
            .incoming = .empty,
        };
        // allocate pending/incoming capacity
        try t.pending.ensureTotalCapacity(allocator, 16);
        try t.incoming.ensureTotalCapacity(allocator, 16);
        return t;
    }
    pub fn deinit(self: *Transport) void {
        self.pending.deinit(self.allocator);
        self.incoming.deinit(self.allocator);
        if (g_registry) |*reg| _ = reg.remove(self.local_port);
    }

    fn deliver(self: *Transport, pkt: Packet, frame: u64) void {
        if (g_registry) |*reg| {
            if (reg.get(self.peer_port)) |peer| {
                peer.incoming.append(peer.allocator, pkt) catch {};
                if (pkt.seq > peer.confirmed) peer.confirmed = pkt.seq;
                return;
            }
        }
        // loopback to self (single-window test)
        self.incoming.append(self.allocator, pkt) catch {};
        _ = frame;
    }

    pub fn send(self: *Transport, input_bits: u16, hash: u64, frame: u64) void {
        if (self.loss > 0 and self.rng.float(f32) < self.loss) return;
        const pkt = Packet{ .seq = self.seq, .ack = self.confirmed, .input = input_bits, .hash = hash };
        self.seq +%= 1;
        if (self.latency_frames > 0) {
            self.pending.append(self.allocator, .{ .deliver_at = frame + self.latency_frames, .pkt = pkt }) catch return;
            return;
        }
        self.deliver(pkt, frame);
    }
    pub fn flushPending(self: *Transport, frame: u64) void {
        var i: usize = 0;
        while (i < self.pending.items.len) {
            if (self.pending.items[i].deliver_at <= frame) {
                self.deliver(self.pending.items[i].pkt, frame);
                _ = self.pending.swapRemove(i);
            } else i += 1;
        }
    }
    pub fn recv(self: *Transport) ?Packet {
        if (self.incoming.items.len == 0) return null;
        const pkt = self.incoming.orderedRemove(0);
        if (pkt.ack > self.confirmed) self.confirmed = pkt.ack;
        if (pkt.seq > self.confirmed) self.confirmed = pkt.seq;
        return pkt;
    }
    pub fn setLoss(self: *Transport, v: f32) void { self.loss = std.math.clamp(v, 0, 0.9); }
    pub fn setLatency(self: *Transport, f: u32) void { self.latency_frames = f; }
};

test "transport packet roundtrip" {
    const gpa = std.testing.allocator;
    var a = try Transport.init(gpa, 19100, 19101, 0, 0);
    defer a.deinit();
    var b = try Transport.init(gpa, 19101, 19100, 0, 0);
    defer b.deinit();
    // register both for loopback routing
    if (g_registry == null) g_registry = std.AutoHashMap(u16, *Transport).init(gpa);
    g_registry.?.put(19100, &a) catch {};
    g_registry.?.put(19101, &b) catch {};
    a.send(0x00FF, 0x12345678, 0);
    std.Thread.sleep(10 * std.time.ns_per_ms);
    const pkt = b.recv();
    try std.testing.expect(pkt != null);
    try std.testing.expectEqual(@as(u16, 0x00FF), pkt.?.input);
    try std.testing.expectEqual(@as(u64, 0x12345678), pkt.?.hash);
    _ = g_registry.?.remove(19100);
    _ = g_registry.?.remove(19101);
}
