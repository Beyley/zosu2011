const std = @import("std");

const Bancho = @import("../bancho.zig");
const Client = @import("client.zig");

accuracy: f32,
// level: Bancho.Int,
play_count: Bancho.Int,
rank: Bancho.Int,
ranked_score: Bancho.Long,
status: Client.Status,
total_score: Bancho.Long,
user_id: Bancho.Int,

const Self = @This();

pub fn size(self: Self) u32 {
    // zig fmt: off
    return @sizeOf(f32) 
         + @sizeOf(Bancho.Int) * 3 
         + @sizeOf(Bancho.Long) * 2 
         + self.status.size();
    // zig fmt: on
}

pub fn serialize(self: Self, writer: Client.Writer) !void {
    try writer.writeIntLittle(Bancho.Int, self.user_id);
    try self.status.serialize(writer);
    try writer.writeIntLittle(Bancho.Long, self.ranked_score);
    try writer.writeAll(std.mem.asBytes(&self.accuracy));
    try writer.writeIntLittle(Bancho.Int, self.play_count);
    try writer.writeIntLittle(Bancho.Long, self.total_score);
    try writer.writeIntLittle(Bancho.Int, self.rank);
}
