const std = @import("std");
const network = @import("network");

const Packets = @import("packet.zig");

const Self = @This();

pub const MAX_USERNAME_LENGTH = 32;

user_id: Packets.BanchoInt,
username_buf: [MAX_USERNAME_LENGTH]u8,
username: []u8,
password: [std.crypto.hash.Md5.digest_length]u8,
socket: network.Socket,
writer: std.io.BufferedWriter(4096, network.Socket.Writer),
write_mutex: std.Thread.Mutex,
last_heard_from: i64,

time_zone: i8,
display_city: bool,

status: Packets.StatusUpdate,

//A set of temporary buffers we read into inside the `read` function
temp_read_buf: [4096]u8 = undefined,
temp_read_buf_slice: []u8 = &.{},
read_from_temp_buf: usize = 0,

///Atomic bool to track whether a packet is already being read or not
reading: std.atomic.Atomic(bool) = std.atomic.Atomic(bool).init(false),
bytes_read: usize = 0,

///The channels the user is currently in
channels: AvailableChannels = .{},

fn maxChannelLength() comptime_int {
    var max_channel_length = MAX_USERNAME_LENGTH;

    inline for (@typeInfo(AvailableChannels).Struct.fields) |field| {
        if (field.name.len > max_channel_length) {
            max_channel_length = field.name.len;
        }
    }

    return max_channel_length;
}

pub const MAX_CHANNEL_LENGTH = maxChannelLength();

///A struct containing all the available channels
pub const AvailableChannels = struct {
    osu: bool = true,
    taiko: bool = false,
    ctb: bool = false,
    ziglang: bool = false,
};

///Resets the read buffer, ignoring all data from the previous read
pub fn reset_read(self: *Self) !void {
    self.temp_read_buf_slice = self.temp_read_buf[0..self.socket.receive(&self.temp_read_buf)];
}

pub const Reader = std.io.Reader(*Self, network.Socket.Reader.Error, read);

pub fn getPresencePacket(self: Self) Packets.UserPresencePacket {
    return Packets.UserPresencePacket{
        .data = .{
            .user_presence = Packets.UserPresence{
                .username = self.username,
                .user_id = self.user_id,
                .timezone = self.time_zone,
                .rank = 1, //TODO
                .permissions = Packets.LoginPermissions{
                    .normal = true,
                    .supporter = true,
                    .bat = false,
                    .friend = false,
                }, //TODO
                .longitude = 0, //TODO
                .latitude = 0, //TODO
                .country = 0, //TODO
                .city = "", //TODO
                .avatar_extension = .none,
            },
        },
    };
}

pub fn getUserUpdatePacket(self: Self) Packets.UserUpdatePacket {
    return Packets.UserUpdatePacket{
        .data = .{
            .user_stats = Packets.UserStats{
                .user_id = self.user_id,
                .total_score = 0, //TODO
                .status = self.status,
                .ranked_score = 0, //TODO
                .rank = 1, //TODO
                .play_count = 0, //TODO
                .level = 0, //TODO
                .accuracy = 1, //TODO
            },
        },
    };
}

pub fn reader(self: *Self) Reader {
    self.bytes_read = 0;
    return Reader{
        .context = self,
    };
}

///Tries to read bytes from the client
pub fn read(self: *Self, buf: []u8) !usize {
    //A constantly updating buffer containing all the data we are going to be reading
    var rest_of_buf: []u8 = buf;

    while (rest_of_buf.len > 0) {
        //If we have any bytes at all in the temporary buffer left
        if (self.read_from_temp_buf < self.temp_read_buf_slice.len) {
            //Get the amount of bytes we are able to read in from the buffer
            const bytes_to_read = @min(self.temp_read_buf_slice.len - self.read_from_temp_buf, rest_of_buf.len);

            //Copy the bytes we *do* have into the output buffer
            @memcpy(
                rest_of_buf[0..bytes_to_read],
                self.temp_read_buf_slice[self.read_from_temp_buf .. self.read_from_temp_buf + bytes_to_read],
            );

            //Mark that we have read more from the buffer
            self.read_from_temp_buf += bytes_to_read;

            //If the amount of bytes left in the buffer equal the length of the data we have yet to read,
            if (bytes_to_read == rest_of_buf.len) {
                //We are done
                break;
            }

            //The rest of buf is the second chunk of the data we have not written to
            rest_of_buf = rest_of_buf[bytes_to_read..rest_of_buf.len];
        }

        //Read as much data as we can into the temp buffer
        self.temp_read_buf_slice = self.temp_read_buf[0..try self.socket.receive(&self.temp_read_buf)];

        //Reset the amount we have read from the temp buf
        self.read_from_temp_buf = 0;
    }

    self.bytes_read += buf.len;

    return buf.len;
}
