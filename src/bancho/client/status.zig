const std = @import("std");

const Bancho = @import("../bancho.zig");

pub const PlayMode = enum(Bancho.Byte) {
    osu = 0,
    taiko = 1,
    catch_the_beat = 2,
};

pub const StatusType = enum(Bancho.Byte) {
    idle,
    afk,
    playing,
    editing,
    modding,
    multiplayer,
    watching,
    unknown,
    testing,
    submitting,
    paused,
    lobby,
    multiplaying,
    osu_direct,
};

pub const MAX_STATUS_TEXT_LENGTH = 64;
//The checksum of the beatmap the user is currentlyplaying on, 2x the actual digest length since its encoded as ASCII text
beatmap_checksum: Bancho.ArrayString(std.crypto.hash.Md5.digest_length * 2),
beatmap_id: Bancho.Int,
current_mods: Bancho.Mods,
play_mode: PlayMode,
status: StatusType,
status_text: Bancho.ArrayString(MAX_STATUS_TEXT_LENGTH),

const Self = @This();

pub fn size(self: Self) u32 {
    return @sizeOf(Bancho.Int) + @sizeOf(Bancho.UShort) + @sizeOf(Bancho.Byte) * 2 + self.status_text.size() + self.beatmap_checksum.size();
}

pub fn serialize(self: Self, writer: Bancho.Client.Writer) !void {
    try writer.writeIntLittle(Bancho.Byte, @as(u8, @intFromEnum(self.status)));
    try self.status_text.serialize(writer);
    try self.beatmap_checksum.serialize(writer);
    //TODO: make this line cleaner
    try writer.writeIntLittle(Bancho.UShort, @as(Bancho.UShort, @truncate(@as(u32, @bitCast(self.current_mods)))));
    try writer.writeIntLittle(Bancho.Byte, @intFromEnum(self.play_mode));
    try writer.writeIntLittle(Bancho.Int, self.beatmap_id);
}
