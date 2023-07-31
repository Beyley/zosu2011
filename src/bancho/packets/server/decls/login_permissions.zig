const Bancho = @import("../../../bancho.zig");

const PacketId = @import("../server.zig").PacketId;
const Packets = @import("../../packets.zig");

pub const Packet = Packets.Packet(PacketId.login_permissions, struct {
    const Self = @This();

    permissions: Bancho.Client.Permissions,

    pub fn size(self: Self) u32 {
        _ = self;

        return @sizeOf(Bancho.Int);
    }

    pub fn serialize(self: Self, writer: Bancho.Client.Writer) !void {
        try writer.writeIntLittle(Bancho.Int, @as(Bancho.Int, @bitCast(self.permissions)));
    }
});

pub fn create(permissions: Bancho.Client.Permissions) Packet {
    return .{ .data = .{ .permissions = permissions } };
}
