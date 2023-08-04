const Bancho = @import("../../../bancho.zig");
const Packets = @import("../../packets.zig");
const PacketId = @import("../server.zig").PacketId;

pub const Packet = Packets.Packet(PacketId.handle_osu_update, struct {
    const Self = @This();

    target: ?Bancho.RcClient,
    user_stats: Bancho.Client.Stats,

    pub fn size(self: Self) u32 {
        return self.user_stats.size();
    }

    pub fn serialize(self: Self, writer: Bancho.Client.Writer) !void {
        try self.user_stats.serialize(writer);

        //If the target is specified, drop our reference
        if (self.target) |target_rc| {
            target_rc.drop();
        }
    }
});

pub fn create(stats: Bancho.Client.Stats, target: ?Bancho.RcClient) Packet {
    return .{
        .data = .{
            .user_stats = stats,
            .target = target,
        },
    };
}
