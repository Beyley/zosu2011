const Bancho = @import("../../../bancho.zig");
const Packets = @import("../../packets.zig");
const PacketId = @import("../server.zig").PacketId;

pub const Packet = Packets.Packet(PacketId.channel_join_success, struct {
    const Self = @This();

    channel: Bancho.String,

    pub fn size(self: Self) u32 {
        return self.channel.size();
    }

    pub fn serialize(self: Self, writer: Bancho.Client.Writer) !void {
        try self.channel.serialize(writer);
    }
});

/// Creates a channel_join_success packet
/// NOTE: `channel` *must* stay alive until the packet is sent!
pub fn create(channel: []const u8) Packet {
    return .{ .data = .{ .channel = .{ .str = channel } } };
}
