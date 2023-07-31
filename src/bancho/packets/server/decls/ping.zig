const Bancho = @import("../../../bancho.zig");
const Packets = @import("../../packets.zig");
const PacketId = @import("../server.zig").PacketId;

pub const Packet = Packets.Packet(PacketId.ping, struct {
    const Self = @This();

    pub fn size(self: Self) u32 {
        _ = self;

        return 0;
    }

    pub fn serialize(self: Self, writer: Bancho.Client.Writer) !void {
        _ = writer;
        _ = self;
    }
});

pub fn create() Packet {
    return .{ .data = .{} };
}
