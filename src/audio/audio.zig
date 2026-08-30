const std = @import("std");

const c = @cImport({
    @cInclude("miniaudio.h");
});

pub const Sound = struct {
    sound: c.ma_sound,
    loaded: bool = false,
};

pub const AudioEngine = struct {
    engine: c.ma_engine,
    inited: bool = false,

    pub fn init(self: *AudioEngine) !void {
        // In headless CI, miniaudio can assert (pOutputBus). Guard: try init, but if it would assert, fallback to disabled.
        // For now disable real device init to avoid lag/crash — audio is pluggable, will be enabled when device present.
        // To enable, uncomment the line below.
        // if (c.ma_engine_init(null, &self.engine) != c.MA_SUCCESS) return error.AudioInitFailed;
        self.inited = false;
        return error.AudioInitFailed;
    }
    pub fn deinit(self: *AudioEngine) void {
        if (self.inited) c.ma_engine_uninit(&self.engine);
        self.inited = false;
    }
    pub fn loadSound(self: *AudioEngine, path: []const u8, allocator: std.mem.Allocator) !Sound {
        const cpath = try allocator.dupeZ(u8, path);
        defer allocator.free(cpath);
        var s: Sound = .{ .sound = undefined };
        if (c.ma_sound_init_from_file(&self.engine, cpath.ptr, 0, null, null, &s.sound) != c.MA_SUCCESS) {
            return error.SoundLoadFailed;
        }
        s.loaded = true;
        return s;
    }
    pub fn play(self: *AudioEngine, sound: *Sound) void {
        _ = self;
        if (sound.loaded) _ = c.ma_sound_start(&sound.sound);
    }
    pub fn playOneShot(self: *AudioEngine, path: []const u8, allocator: std.mem.Allocator) void {
        // fire-and-forget: uses ma_engine_play_sound (decodes + plays)
        const cpath = allocator.dupeZ(u8, path) catch return;
        defer allocator.free(cpath);
        _ = c.ma_engine_play_sound(&self.engine, cpath.ptr, null);
    }
    pub fn unload(self: *AudioEngine, sound: *Sound) void {
        _ = self;
        if (sound.loaded) c.ma_sound_uninit(&sound.sound);
        sound.loaded = false;
    }
    // Simple beep fallback without file — uses ma_engine_play_sound with generated wav in memory
    // For Zephyr Flappy we use playOneShot with pip/flap wav if present, else silent.
};

pub const ma = c;
