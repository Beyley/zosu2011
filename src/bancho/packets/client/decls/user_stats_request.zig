const std = @import("std");

const Bancho = @import("../../../bancho.zig");
const Packets = @import("../../packets.zig");
const PacketId = @import("../client.zig").PacketId;

pub const Packet = Packets.Packet(PacketId.user_stats_request, struct {
    const Self = @This();

    status: Bancho.Client.Status,

    pub fn size(self: Self) u32 {
        return self.status.size();
    }

    pub fn deserialize(reader: Bancho.Client.Reader) !Self {
        return .{
            .status = try Bancho.Client.Status.deserialize(reader),
        };
    }
});
