const Bancho = @import("../../../bancho.zig");
const Packets = @import("../../packets.zig");
const PacketId = @import("../client.zig").PacketId;

pub const Packet = Packets.Packet(PacketId.exit, struct {
    const Self = @This();

    ///Whether the client had an update available at the time of closing the game
    update_available: bool,

    pub fn size(self: Self) u32 {
        _ = self;

        return @sizeOf(Bancho.Int);
    }

    pub fn deserialize(reader: Bancho.Client.Reader) !Self {
        return .{
            .update_available = try reader.readIntLittle(Bancho.Int) != 0,
        };
    }
});
