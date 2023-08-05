const Bancho = @import("../../../bancho.zig");
const Packets = @import("../../packets.zig");
const PacketId = @import("../client.zig").PacketId;

pub const Packet = Packets.Packet(PacketId.error_report, struct {
    const Self = @This();

    error_string: Bancho.ArrayString(8192),

    pub fn size(self: Self) u32 {
        _ = self;

        return @sizeOf(Bancho.Int);
    }

    pub fn deserialize(reader: Bancho.Client.Reader) !Self {
        return .{
            .error_string = try Bancho.ArrayString(8192).deserialize(reader),
        };
    }
});
