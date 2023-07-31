const std = @import("std");

pub const Server = @import("server/server.zig");
pub const Client = @import("client/client.zig");

const Bancho = @import("../bancho.zig");

///Constructs a serializable packet from a PID and payload data type
pub fn Packet(comptime packet_id: anytype, comptime DataType: type) type {
    if (@sizeOf(@TypeOf(packet_id)) != @sizeOf(u16)) {
        @compileError("Invalid packet id type! Type must be of size u16");
    }

    return struct {
        data: DataType,

        const Self = @This();

        pub fn serialize(self: Self, writer: Bancho.Client.Writer) !void {
            const use_compression = false;

            //Write packet type
            try writer.writeIntLittle(u16, @intFromEnum(packet_id));
            //Write compression state (always off)
            try writer.writeIntLittle(u8, @intFromBool(use_compression));
            //Write length of packet
            try writer.writeIntLittle(u32, self.data.size());
            //Serialize the packet data too
            try self.data.serialize(writer);

            std.debug.print("sending packet {s} with data {}\n", .{ @tagName(packet_id), self.data });
        }
    };
}
