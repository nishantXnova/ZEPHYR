pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return .{ .r = r, .g = g, .b = b };
    }
    pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }
    pub fn toBGR(self: Color) u32 {
        // Windows COLORREF is 0x00BBGGRR
        return @as(u32, self.r) | (@as(u32, self.g) << 8) | (@as(u32, self.b) << 16);
    }

    pub const white = Color.rgb(255, 255, 255);
    pub const black = Color.rgb(0, 0, 0);
    pub const red = Color.rgb(220, 38, 38);
    pub const green = Color.rgb(34, 197, 94);
    pub const blue = Color.rgb(59, 130, 246);
    pub const sky = Color.rgb(135, 206, 235);
    pub const ground = Color.rgb(222, 184, 135);
    pub const pipe = Color.rgb(34, 139, 34);
    pub const yellow = Color.rgb(251, 191, 36);
    pub const dark = Color.rgb(30, 30, 32);
};
