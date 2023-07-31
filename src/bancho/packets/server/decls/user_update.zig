const Bancho = @import("../../../bancho.zig");
const Packets = @import("../../packets.zig");
const PacketId = @import("../server.zig").PacketId;

pub const Packet = Packets.Packet(PacketId.handle_osu_update, struct {
    const Self = @This();

    user_stats: Bancho.Client.Stats,

    pub fn size(self: Self) u32 {
        return self.user_stats.size();
    }

    pub fn serialize(self: Self, writer: Bancho.Client.Writer) !void {
        try self.user_stats.serialize(writer);
    }
});

pub fn create(stats: Bancho.Client.Stats) Packet {
    return .{ .data = .{ .user_stats = stats } };
}
