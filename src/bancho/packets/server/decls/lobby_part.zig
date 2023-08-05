const Bancho = @import("../../../bancho.zig");

const PacketId = @import("../server.zig").PacketId;
const Packets = @import("../../packets.zig");

pub const Packet = Packets.Packet(PacketId.lobby_part, struct {
    const Self = @This();

    client: union(enum) {
        id: Bancho.Int,
        client: Bancho.RcClient,
    },

    pub fn size(self: Self) u32 {
        _ = self;

        return @sizeOf(Bancho.Int);
    }

    pub fn serialize(self: Self, writer: Bancho.Client.Writer) !void {
        switch (self.client) {
            .client => |client| {
                try writer.writeIntLittle(Bancho.Int, client.data.stats.user_id);

                //Drop this packets reference to the client
                client.drop();
            },
            .id => |user_id| {
                try writer.writeIntLittle(Bancho.Int, user_id);
            },
        }
    }
});

pub fn create_from_client(client: Bancho.RcClient) Packet {
    return .{ .data = .{ .client = .{ .client = client } } };
}

pub fn create_from_user_id(user_id: Bancho.Int) Packet {
    return .{ .data = .{ .client = .{ .id = user_id } } };
}
