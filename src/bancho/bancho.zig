const std = @import("std");
const network = @import("network");
const memutils = @import("memutils");

pub const Packets = @import("packets/packets.zig");
pub const Client = @import("client/client.zig");
pub const Serialization = @import("serialization.zig");

pub const RcClient = memutils.Rc(Client);

//Human-friendly names of the serialized bancho types
///A serialized byte
pub const Byte = u8;
///A serialized ushort
pub const UShort = u16;
///A serialized int
pub const Int = i32;
///A serialized long
pub const Long = i64;
///A serialized string
pub const String = struct {
    str: []const u8,

    ///The size of the string when serialized on the network
    pub fn size(self: String) u32 {
        return Serialization.banchoStringSize(self.str);
    }

    pub fn serialize(self: String, writer: Client.Writer) !void {
        try Serialization.writeBanchoString(writer, self.str);
    }
};
pub fn ArrayString(comptime length: comptime_int) type {
    return struct {
        str: [length]u8,
        len: ?usize,

        pub fn size(self: @This()) u32 {
            return Serialization.banchoStringSize(self.str[0 .. self.len orelse length]);
        }

        pub fn serialize(self: @This(), writer: Client.Writer) !void {
            try Serialization.writeBanchoString(writer, self.str[0 .. self.len orelse length]);
        }

        pub fn slice(self: *const @This()) []const u8 {
            return self.str[0 .. self.len orelse self.str.len];
        }
    };
}

//Latest protocol version referenced in the 2011 client
pub const ProtocolVersion = 7;

///The maximum length of messages
pub const MAX_MESSAGE_SIZE = 256;

pub const Mods = packed struct(Int) {
    padding: u32 = 0,
};

pub const AvatarExtension = enum(Byte) {
    none = 0,
    png = 1,
    jpeg = 2,
};
