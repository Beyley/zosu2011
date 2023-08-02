const std = @import("std");
const network = @import("network");

const Bancho = @import("../bancho.zig");

const Main = @import("../../main.zig");

const Self = @This();

pub const Permissions = @import("permissions.zig").Permissions;
pub const Status = @import("status.zig");
pub const Stats = @import("stats.zig");
pub const Presence = @import("presence.zig");

pub const MAX_USERNAME_LENGTH = 32;

username: Bancho.ArrayString(MAX_USERNAME_LENGTH),
password: [std.crypto.hash.Md5.digest_length]u8,
socket: network.Socket,
writer: std.io.BufferedWriter(4096, network.Socket.Writer),
write_mutex: std.Thread.Mutex,
last_heard_from: i64,
permissions: Permissions,
stats: Stats,

time_zone: i8,
display_city: bool,

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

pub const Writer = std.io.BufferedWriter(4096, network.Socket.Writer).Writer;
pub const Reader = std.io.Reader(*Self, network.Socket.Reader.Error, read);

pub fn getPresencePacket(self: Self) Bancho.Packets.Server.UserPresence.Packet {
    return Bancho.Packets.Server.UserPresence.Packet{
        .data = .{
            .user_presence = Presence{
                .username = self.username,
                .user_id = self.stats.user_id,
                .timezone = self.time_zone,
                .rank = self.stats.rank, //TODO
                .permissions = self.permissions,
                .longitude = 0, //TODO
                .latitude = 0, //TODO
                .country = 0, //TODO
                .city = .{ .str = &.{} }, //TODO
                .avatar_extension = .none,
            },
        },
    };
}

pub fn sendAvailableChannels(client_rc: Bancho.RcClient, args: anytype) void {
    _ = args;
    defer client_rc.drop();
    var client = client_rc.data;

    //Iterate over all known channels,
    inline for (@typeInfo(AvailableChannels).Struct.fields) |field| {
        const channel_name = "#" ++ field.name;

        const available_packet = Bancho.Packets.Server.ChannelAvailable.create(channel_name);

        //If the user has joined the channel,
        if (@field(client.channels, field.name)) {
            //Send an available packet, then a success packet
            Main.thread_pool.spawn(Bancho.sendPackets, .{
                client_rc.borrow(),
                .{
                    available_packet,
                    Bancho.Packets.Server.ChannelJoinSuccess.create(channel_name),
                },
                null,
                .{},
            }) catch unreachable;
        } else {
            //Send only an available packet
            Main.thread_pool.spawn(
                Bancho.sendPackets,
                .{ client_rc.borrow(), .{available_packet}, null, .{} },
            ) catch unreachable;
        }
    }
}
pub fn getUserUpdatePacket(self: Self) Bancho.Packets.Server.UserUpdate.Packet {
    return Bancho.Packets.Server.UserUpdate.Packet{
        .data = .{
            .user_stats = self.stats,
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
