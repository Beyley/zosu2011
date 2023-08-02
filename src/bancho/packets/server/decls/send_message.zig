const Bancho = @import("../../../bancho.zig");
const Packets = @import("../../packets.zig");
const PacketId = @import("../server.zig").PacketId;

pub const Packet = Packets.Packet(PacketId.send_message, struct {
    const Self = @This();

    ///The sender of the message
    ///NOTE: The memory set here *must* stay alive until packet sending
    sender: Bancho.RcClient,

    ///The target of the message
    ///NOTE: The memory set here *must* stay alive until packet sending
    target: union(enum) {
        client: Bancho.RcClient,
        channel: Bancho.String,
    },

    message: Bancho.ArrayString(Bancho.MAX_MESSAGE_SIZE) = undefined,

    pub fn size(self: Self) u32 {
        // zig fmt: off
        return self.sender.data.username.size() 
             + blk: {
                switch(self.target) {
                    .client => {
                        break :blk self.target.client.data.username.size();
                    },
                    .channel => {
                        break :blk self.target.channel.size();
                    },
                }
             }
             + self.message.size();
        // zig fmt: on
    }

    pub fn serialize(self: Self, writer: Bancho.Client.Writer) !void {
        try self.sender.data.username.serialize(writer);
        try self.message.serialize(writer);
        switch (self.target) {
            .client => |target| try target.data.username.serialize(writer),
            .channel => |channel| try channel.serialize(writer),
        }

        //Mark that the message is serialized, so drop our reference to the target and sender
        self.sender.drop();
        switch (self.target) {
            .client => |client| {
                client.drop();
            },
            .channel => {},
        }
    }
});

pub fn create_client_target(sender: Bancho.RcClient, target: Bancho.RcClient, message: []const u8) Packet {
    var packet = Packet{
        .data = .{
            .sender = sender,
            .target = .{ .client = target },
            .message = .{
                .str = undefined,
                .len = message.len,
            },
        },
    };
    @memcpy(packet.data.message.str[0..message.len], message);

    return packet;
}

pub fn create_channel_target(sender: Bancho.RcClient, target: []const u8, message: []const u8) Packet {
    var packet = Packet{
        .data = .{
            .sender = sender,
            .target = .{ .channel = .{ .str = target } },
            .message = .{
                .str = undefined,
                .len = message.len,
            },
        },
    };
    @memcpy(packet.data.message.str[0..message.len], message);

    return packet;
}
