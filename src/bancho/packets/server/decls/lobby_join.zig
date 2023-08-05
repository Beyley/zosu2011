const Bancho = @import("../../../bancho.zig");

const PacketId = @import("../server.zig").PacketId;
const Packets = @import("../../packets.zig");

pub const Packet = Packets.Packet(PacketId.lobby_join, struct {
    const Self = @This();

    client: Bancho.RcClient,

    pub fn size(self: Self) u32 {
        _ = self;

        return @sizeOf(Bancho.Int);
    }

    pub fn serialize(self: Self, writer: Bancho.Client.Writer) !void {
        try writer.writeIntLittle(Bancho.Int, self.client.data.stats.user_id);

        //Drop this packets reference to the client
        self.client.drop();
    }
});

pub fn create(client: Bancho.RcClient) Packet {
    return .{ .data = .{ .client = client } };
}
