const Bancho = @import("../../../bancho.zig");
const Packets = @import("../../packets.zig");
const PacketId = @import("../client.zig").PacketId;

pub const Packet = Packets.Packet(PacketId.send_irc_message, struct {
    const Self = @This();

    sender: Bancho.ArrayString(Bancho.Client.MAX_CHANNEL_LENGTH),
    target: Bancho.ArrayString(Bancho.Client.MAX_CHANNEL_LENGTH),
    message: Bancho.ArrayString(Bancho.MAX_MESSAGE_SIZE),

    pub fn size(self: Self) u32 {
        return self.target.size() + self.message.size();
    }

    pub fn deserialize(reader: Bancho.Client.Reader) !Self {
        return .{
            .sender = try Bancho.ArrayString(Bancho.Client.MAX_CHANNEL_LENGTH).deserialize(reader),
            .message = try Bancho.ArrayString(Bancho.MAX_MESSAGE_SIZE).deserialize(reader),
            .target = try Bancho.ArrayString(Bancho.Client.MAX_CHANNEL_LENGTH).deserialize(reader),
        };
    }
});
