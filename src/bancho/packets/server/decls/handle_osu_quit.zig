const Bancho = @import("../../../bancho.zig");
const Packets = @import("../../packets.zig");
const PacketId = @import("../server.zig").PacketId;

pub const Packet = Packets.Packet(PacketId.handle_osu_quit, struct {
    const Self = @This();

    user_id: Bancho.Int,

    pub fn size(self: Self) u32 {
        _ = self;

        return @sizeOf(Bancho.Int);
    }

    pub fn serialize(self: Self, writer: Bancho.Client.Writer) !void {
        try writer.writeIntLittle(Bancho.Int, self.user_id);
    }
});

pub fn create(user_id: Bancho.Int) Packet {
    return .{ .data = .{ .user_id = user_id } };
}
