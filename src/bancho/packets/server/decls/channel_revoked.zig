const Bancho = @import("../../../bancho.zig");
const Packets = @import("../../packets.zig");
const PacketId = @import("../server.zig").PacketId;

pub const Packet = Packets.Packet(PacketId.channel_revoked, struct {
    const Self = @This();

    channel: Bancho.String,

    pub fn size(self: Self) u32 {
        return self.channel.size();
    }

    pub fn serialize(self: Self, writer: Bancho.Client.Writer) !void {
        try self.channel.serialize(writer);
    }
});

///NOTE: `channel` must live as long as this packet struct!
pub fn create(channel: []const u8) Packet {
    return .{ .data = .{ .channel = .{ .str = channel } } };
}
