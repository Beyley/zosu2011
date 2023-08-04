const std = @import("std");

const Bancho = @import("../bancho.zig");
const Client = @import("client.zig");

country: Bancho.Byte,
city: Bancho.String,
permissions: Client.Permissions,
avatar_extension: Bancho.AvatarExtension,
timezone: i8,
user_id: Bancho.Int,
username: Bancho.ArrayString(Bancho.MAX_USERNAME_LENGTH),
longitude: f32,
latitude: f32,
rank: Bancho.Int,

const Self = @This();

pub fn size(self: Self) u32 {
    // zig fmt: off
    return @sizeOf(Bancho.Byte) * 4 
         + @sizeOf(Bancho.Int) * 2 
         + @sizeOf(f32) * 2 
         + self.city.size() 
         + self.username.size();
    // zig fmt: on
}

pub fn serialize(self: Self, writer: Bancho.Client.Writer) !void {
    try writer.writeIntLittle(Bancho.Int, self.user_id);
    try self.username.serialize(writer);
    try writer.writeIntLittle(Bancho.Byte, @intFromEnum(self.avatar_extension));
    try writer.writeIntLittle(Bancho.Byte, @as(Bancho.Byte, @intCast(self.timezone + 24)));
    try writer.writeIntLittle(Bancho.Byte, self.country);
    try self.city.serialize(writer);
    try writer.writeIntLittle(Bancho.Byte, @as(Bancho.Byte, @truncate(@as(u32, @bitCast(self.permissions)))));
    try writer.writeAll(std.mem.asBytes(&self.longitude));
    try writer.writeAll(std.mem.asBytes(&self.latitude));
    try writer.writeIntLittle(Bancho.Int, self.rank);
}
