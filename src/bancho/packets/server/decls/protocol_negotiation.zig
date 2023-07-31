const Bancho = @import("../../../bancho.zig");
const Packets = @import("../../packets.zig");
const PacketId = @import("../server.zig").PacketId;

pub const Packet = Packets.Packet(PacketId.protocol_negotiation, struct {
    const Self = @This();

    version: Bancho.Int = Bancho.ProtocolVersion,

    pub fn size(self: Self) u32 {
        _ = self;

        return @sizeOf(Bancho.Int);
    }

    pub fn serialize(self: Self, writer: Bancho.Client.Writer) !void {
        try writer.writeIntLittle(Bancho.Int, self.version);
    }
});

pub fn create() Packet {
    return .{ .data = .{} };
}
