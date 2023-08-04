const Bancho = @import("../../../bancho.zig");
const Packets = @import("../../packets.zig");
const PacketId = @import("../client.zig").PacketId;

pub const Packet = Packets.Packet(PacketId.channel_join, struct {
    const Self = @This();

    ///The receive mode the client wants, this could mean sending no one, everyone, or only friends
    channel: Bancho.ArrayString(Bancho.MAX_CHANNEL_LENGTH),

    pub fn size(self: Self) u32 {
        return self.channel.size();
    }

    pub fn deserialize(reader: Bancho.Client.Reader) !Self {
        return .{ .channel = try Bancho.ArrayString(Bancho.MAX_CHANNEL_LENGTH).deserialize(reader) };
    }
});
