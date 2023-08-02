const Bancho = @import("../../../bancho.zig");
const Packets = @import("../../packets.zig");
const PacketId = @import("../client.zig").PacketId;

pub const Packet = Packets.Packet(PacketId.receive_updates, struct {
    const Self = @This();

    pub const UpdateMode = enum(Bancho.Int) {
        none = 0,
        all = 1,
        friends = 2,
    };

    ///The receive mode the client wants, this could mean sending no one, everyone, or only friends
    update_mode: UpdateMode,

    pub fn size(self: Self) u32 {
        _ = self;

        return @sizeOf(Bancho.Int);
    }

    pub fn deserialize(reader: Bancho.Client.Reader) !Self {
        return .{
            .update_mode = @enumFromInt(try reader.readIntLittle(Bancho.Int)),
        };
    }
});
