const std = @import("std");

const Bancho = @import("bancho.zig");

pub fn readBanchoString(reader: Bancho.Client.Reader, buf: []u8) ![]u8 {
    const data_type = try reader.readByte();

    if (data_type == 0) {
        return "";
    } else if (data_type == 11) {
        //Read the length of the string
        const length = try readUleb128(reader, usize);

        //If the string is too long to fit in the buffer, return an error
        if (length > buf.len) {
            return error.StringTooBig;
        }

        //Reture the chunk of the buffer that was read
        return buf[0..try reader.readAll(buf[0..length])];
    } else {
        return error.UnknownDataType;
    }

    unreachable;
}

///Reads a Uleb128 number from the stream
pub fn readUleb128(reader: Bancho.Client.Reader, comptime T: type) !T {
    var num: T = 0;

    const mask: u8 = 128;

    var b: u8 = try reader.readByte();
    num |= b & ~mask;
    //While the 8th bit is not 0,
    while (b & mask != 0) {
        //Try to shift the number to the left 7 bits to make room for the
        const shift = @shlWithOverflow(num, 7);

        //If the number overflowed from the shift, throw an error
        if (shift[1] == 1) {
            return error.NumberFromStreamTooBig;
        }

        //If it was not an overflow, set the num to the shifted value
        num = shift[0];

        //Copy in the bits from the stream, disposing of the 8th bit
        num |= b & ~mask;

        //If the 8th bit is 0, dont read more!
        if (b & mask != 0) {
            b = try reader.readByte();
        }
    }

    return num;
}

pub fn writeUleb128(writer: Bancho.Client.Writer, int: anytype) !void {
    if (int == 0) {
        try writer.writeIntLittle(u8, 0);
        return;
    }

    var num = int;

    while (num > 0) {
        var b: u8 = @intCast(num & 127);
        num >>= 7;

        if (num != 0) {
            b |= 128;
        }

        try writer.writeByte(b);
    }
}

pub fn uleb128Size(int: anytype) u32 {
    if (int == 0) {
        return @sizeOf(u8);
    }

    var num = int;

    var length: usize = 0;

    while (num > 0) {
        num >>= 7;

        length += 1;
    }

    return @intCast(length * @sizeOf(u8));
}

pub fn writeBanchoString(writer: Bancho.Client.Writer, str: []const u8) !void {
    //If the length is 0
    if (str.len == 0) {
        //Write it as a "null object"
        try writer.writeIntLittle(Bancho.Byte, 0);
    } else {
        //Write it as a "string object"
        try writer.writeIntLittle(Bancho.Byte, 11);
        //Write the length to the stream
        try writeUleb128(writer, str.len);
        //Write the bytes of the string to the stream
        try writer.writeAll(str);
    }
}

pub fn banchoStringSize(str: []const u8) u32 {
    if (str.len == 0) return @sizeOf(Bancho.Byte);

    return @intCast(@sizeOf(Bancho.Byte) + uleb128Size(str.len) + str.len);
}
