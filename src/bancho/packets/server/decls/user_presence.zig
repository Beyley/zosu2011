const Bancho = @import("../../../bancho.zig");
const Packets = @import("../../packets.zig");
const PacketId = @import("../server.zig").PacketId;

pub const Packet = Packets.Packet(PacketId.user_presence, struct {
    const Self = @This();

    target_client: Bancho.RcClient,
    user_presence: Bancho.Client.Presence,

    pub fn size(self: Self) u32 {
        return self.user_presence.size();
    }

    pub fn serialize(self: Self, writer: Bancho.Client.Writer) !void {
        try self.user_presence.serialize(writer);

        self.target_client.drop();
    }
});

pub fn create(presence: Bancho.Client.Presence, target_client: Bancho.RcClient) Packet {
    return .{ .data = .{
        .user_presence = presence,
        .target_client = target_client,
    } };
}
