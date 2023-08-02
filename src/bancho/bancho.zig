const std = @import("std");
const network = @import("network");
const memutils = @import("memutils");

const Main = @import("../main.zig");

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
///A serializable network string
pub const String = struct {
    str: []const u8,

    ///The size of the string when serialized on the network
    pub fn size(self: String) u32 {
        return Serialization.banchoStringSize(self.str);
    }

    pub fn serialize(self: *const String, writer: Client.Writer) !void {
        try Serialization.writeBanchoString(writer, self.str);
    }
};
///A serializable network string, with a max size known at comptime
pub fn ArrayString(comptime length: comptime_int) type {
    return struct {
        const Self = @This();

        str: [length]u8,
        len: ?usize,

        //The network size of the string
        pub fn size(self: Self) u32 {
            return Serialization.banchoStringSize(self.str[0 .. self.len orelse length]);
        }

        pub fn serialize(self: *const Self, writer: Client.Writer) !void {
            try Serialization.writeBanchoString(writer, self.str[0 .. self.len orelse length]);
        }

        pub fn deserialize(reader: Client.Reader) !Self {
            var self: Self = undefined;

            var str = try Serialization.readBanchoString(reader, &self.str);
            self.len = str.len;

            return self;
        }

        pub fn slice(self: *const Self) []const u8 {
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

pub fn keepaliveRun(run: *bool) void {
    while (run.*) {
        {
            Main.users.mutex.lock();
            defer Main.users.mutex.unlock();

            var iter = Main.users.hash_map.valueIterator();

            while (iter.next()) |next| {
                Main.thread_pool.spawn(sendPackets, .{
                    next.*.borrow(),
                    .{Packets.Server.Ping.create()},
                    null,
                    .{},
                }) catch @panic("OOM");
            }

            std.debug.print("keepalive\n", .{});
        }

        const keepalive_time = 5;

        //Sleep for 1 second
        std.time.sleep(std.time.ns_per_s * keepalive_time);
    }
}

pub fn handleUserLogin(client_sock: network.Socket, server_socket: network.Socket, allocator: std.mem.Allocator) void {
    std.debug.print("Client connected from {}\n", .{client_sock.getRemoteEndPoint() catch @panic("shit")});

    handleUserHandshake(client_sock, server_socket, allocator) catch unreachable;
}

fn handleUserHandshake(client_sock: network.Socket, server_socket: network.Socket, allocator: std.mem.Allocator) !void {
    _ = server_socket;
    //Get the raw writer
    var raw_writer = client_sock.writer();
    //Get a buffered writer over the raw writer
    var writer = std.io.bufferedWriter(raw_writer);

    var client_rc: RcClient = RcClient.init(Client{
        .socket = client_sock,
        .writer = writer,
        .username = .{
            .str = undefined,
            .len = 0,
        },
        .password = undefined,
        .display_city = false,
        .time_zone = 0,
        .write_mutex = std.Thread.Mutex{},
        .last_heard_from = std.time.timestamp(),
        .permissions = .{
            .bat = false,
            .supporter = false,
            .friend = false,
        },
        .stats = .{
            .accuracy = 1,
            .play_count = 0,
            .rank = 69,
            .ranked_score = 2,
            .total_score = 3,
            .user_id = @intCast(Main.users.hash_map.count() + 1),
            .status = Client.Status{
                .beatmap_checksum = .{ .str = undefined, .len = 0 },
                .beatmap_id = 0,
                .current_mods = .{},
                .play_mode = .osu,
                .status = .idle,
                .status_text = .{
                    .str = undefined,
                    .len = 0,
                },
            },
        },
    }, allocator) catch unreachable;
    client_rc.deinit_fn = handleClientDisconnect;
    var client: *Client = client_rc.data;

    //If something bad has happened, just drop the client
    errdefer client_rc.drop();

    var buf: [4096]u8 = undefined;

    var reader = client.reader();

    var read: []u8 = undefined;
    read = try reader.readUntilDelimiter(&buf, '\n');
    //If its less than 2 chars long, this is invalid
    if (read.len < 1) return error.ReadTooShort;
    //Remove the ending \r
    read.len -= 1;

    //If the username length is too long, return out
    //TODO: return real error here to the client
    if (read.len > Client.MAX_USERNAME_LENGTH) return error.UsernameTooLong;

    //Copy in the client username
    @memcpy(client.username.str[0..read.len], read);
    client.username.len = read.len;

    read = try reader.readUntilDelimiter(&buf, '\n');

    //If its less than 2 chars long, this is invalid
    if (read.len < 1) return error.ReadTooShort;
    //Remove the ending \r\n
    read.len -= 1;

    //Parse the password into an array of bytes
    client.password = @bitCast(try std.fmt.parseInt(u128, read, 16));

    read = try reader.readUntilDelimiter(&buf, '\n');

    //If its less than 2 chars long, this is invalid
    if (read.len < 1) return error.ReadTooShort;
    //Remove the ending \r\n
    read.len -= 1;

    //Split up the info line
    var info_iter = std.mem.split(u8, read, "|");

    //Version is just a string
    const version = info_iter.next() orelse @panic("MISSING VERSIOn");
    //Time zone is an integer, -12 -> 12
    client.time_zone = try std.fmt.parseInt(i8, info_iter.next() orelse @panic("MISSING TIME ZONE"), 10);
    //boolean for whether or not to display the users city to other users
    client.display_city = (info_iter.next() orelse @panic("MISSING DISPLAY CITY"))[0] == '1';
    //A hash of the client, ignored for now
    const osu_hash = info_iter.next() orelse @panic("MISSING osu!.exe HASH");

    //Simple version check
    if (!std.mem.startsWith(u8, version, "b1816")) {
        @panic("INCORRECT VERSION");
    }

    std.debug.print("client logging in, name {s} password {x}\n", .{ client.username.slice(), @as(u128, @bitCast(client.password)) });
    std.debug.print("version {s}\ntime_zone {d}\ndisplay_city {}\nosu_hash {s}\n", .{ version, client.time_zone, client.display_city, osu_hash });

    //TODO: password check here!

    //The permissions the user has (TODO: ping some kind of database to get this information)
    client.permissions = Client.Permissions{
        .normal = true,
        .supporter = true,
        .bat = false,
        .friend = false,
    };

    //When a client connects we need to tell it what protocol version we are using
    var protocol_negotiation_packet = Packets.Server.ProtocolNegotiation.create();

    //After the client has been told about the protocol version, send a login reply
    var login_response_packet = Packets.Server.LoginResponse.create(.{ .user_id = client.stats.user_id });

    //After the client knows it was a successful login, send them their permissions
    var login_permissions_packet = Packets.Server.LoginPermissions.create(client.permissions);

    var user_data_packet = client.getUserUpdatePacket();

    //Send the user a presence packet, giving all the nessesary info about themselves,
    //With this the client is happy to report that it is no longer "recieving data"
    var user_presence_packet = client.getPresencePacket();

    try Main.thread_pool.spawn(sendPackets, .{
        client_rc.borrow(),
        .{
            protocol_negotiation_packet,
            login_response_packet,
            login_permissions_packet,
            user_data_packet,
            user_presence_packet,
        },
        Client.sendAvailableChannels,
        .{},
    });

    Main.users.mutex.lock();
    //Assert the user id doesnt already exist
    std.debug.assert(!Main.users.hash_map.remove(client.stats.user_id));
    //Put the user into the hash map
    try Main.users.hash_map.put(client.stats.user_id, client_rc);
    defer Main.users.mutex.unlock();

    //If we error later on, remove the user from the list
    errdefer {
        //Assert the user id does exist, it should at this point
        std.debug.assert(Main.users.hash_map.remove(client.user_id));
    }
}

pub fn sendPackets(client_rc: RcClient, packets: anytype, comptime after: ?fn (client: RcClient, args: anytype) void, after_args: anytype) void {
    defer client_rc.drop();

    var client: *Client = client_rc.data;

    //Lock the mutex to make sure no other packets are sent during the sending of this one
    client.write_mutex.lock();
    defer client.write_mutex.unlock();

    inline for (@typeInfo(@TypeOf(packets)).Struct.fields) |field| {
        const packet = @field(packets, field.name);

        //Serialize the packet into the stream
        packet.serialize(client.writer.writer()) catch @panic("UNABLE TO RECOVER FROM WRITE ERROR WAAAA");
    }
    client.writer.flush() catch @panic("UNABLE TO RECOVER FROM FLUSH WAA");
    if (after) |after_fn| {
        after_fn(client_rc.borrow(), after_args);
    }
}

pub fn checkForClientDataPeriodically(run: *bool) void {
    while (run.*) {
        {
            Main.users.mutex.lock();
            defer Main.users.mutex.unlock();

            var iter = Main.users.hash_map.valueIterator();

            while (iter.next()) |next| {
                var client_rc: RcClient = next.*;
                var client = client_rc.data;
                var reading = client.reading.load(.SeqCst);

                if (!reading) {
                    client.reading.store(true, std.atomic.Ordering.SeqCst);
                    Main.thread_pool.spawn(handleClientData, .{
                        client_rc.borrow(),
                    }) catch @panic("OOM");
                }
            }
        }

        //Sleep for 10ms
        std.time.sleep(std.time.ns_per_ms * 10);
    }
}

fn handleClientData(client_rc: RcClient) void {
    defer client_rc.drop();

    var client: *Client = client_rc.data;
    defer client.reading.store(false, .SeqCst);

    var buf: [4096]u8 = undefined;

    //While there is data to recieve, or there are bytes left in our buffer
    while (client.socket.peek(&buf) catch unreachable != 0 or client.read_from_temp_buf < client.temp_read_buf_slice.len) {
        const reader = client.reader();

        const packet_id: Packets.Client.PacketId = @enumFromInt(reader.readIntLittle(u16) catch unreachable);
        const compression = reader.readIntLittle(u8) catch unreachable;
        _ = compression;
        const payload_size = reader.readIntLittle(u32) catch unreachable;

        const before_bytes_read = client.bytes_read;

        switch (packet_id) {
            .exit => {
                const packet = Packets.Client.Exit.deserialize(reader) catch unreachable;
                _ = packet;

                std.debug.print("user {s} exiting...\n", .{client.username.slice()});

                client_rc.drop();
                return;
            },
            .receive_updates => {
                const packet = Packets.Client.ReceiveUpdates.deserialize(reader) catch unreachable;

                std.debug.print("receive_updates with mode {s}\n", .{@tagName(packet.data.update_mode)});

                //If the user specified no data updates, break out and dont send anything
                if (packet.data.update_mode == .none) {
                    break;
                }

                Main.users.mutex.lock();
                defer Main.users.mutex.unlock();

                var iter = Main.users.hash_map.valueIterator();

                while (iter.next()) |next| {
                    const updated_client: *Client = next.*.get();

                    //TODO: filter by friends if update_mode == .friends

                    Main.thread_pool.spawn(sendPackets, .{ client_rc.borrow(), .{
                        updated_client.getPresencePacket(),
                        updated_client.getUserUpdatePacket(),
                    }, null, .{} }) catch unreachable;
                }
            },
            .channel_join => {
                const packet = Packets.Client.ChannelJoin.deserialize(reader) catch unreachable;

                const channel = packet.data.channel.slice();

                std.debug.print("user trying to join channel {s}\n", .{channel});

                //TODO: check permissions

                inline for (@typeInfo(Client.AvailableChannels).Struct.fields) |field| {
                    //If the name of the field and the channel name without the # equal,
                    if (std.mem.eql(u8, field.name, channel[1..])) {
                        Main.thread_pool.spawn(sendPackets, .{ client_rc.borrow(), .{
                            Packets.Server.ChannelJoinSuccess.create("#" ++ field.name),
                        }, null, .{} }) catch unreachable;

                        //Mark that the user is in that channel
                        @field(client.channels, field.name) = true;

                        //Break out, as we found the channel
                        break;
                    }
                }
            },
            .channel_leave => {
                const packet = Packets.Client.ChannelLeave.deserialize(reader) catch unreachable;

                const channel = packet.data.channel.slice();

                std.debug.print("user trying to leave channel {s}\n", .{channel});

                inline for (@typeInfo(Client.AvailableChannels).Struct.fields) |field| {
                    //If the name of the field and the channel name without the # equal,
                    if (std.mem.eql(u8, field.name, channel[1..])) {
                        Main.thread_pool.spawn(sendPackets, .{ client_rc.borrow(), .{
                            Packets.Server.ChannelRevoked.create("#" ++ field.name),
                        }, null, .{} }) catch unreachable;

                        //Mark that the user is no longer in the channel
                        @field(client.channels, field.name) = false;

                        //Break out, as we found the channel
                        break;
                    }
                }
            },
            .send_irc_message => {
                var packet = Packets.Client.SendIrcMessage.deserialize(reader) catch unreachable;

                const message = packet.data.message.slice();
                const target = packet.data.target.slice();

                std.debug.print("message {s} to target {s}\n", .{
                    message,
                    target,
                });

                //Assert the channel starts with a # in the name
                std.debug.assert(target[0] == '#');

                inline for (@typeInfo(Client.AvailableChannels).Struct.fields) |field| {
                    if (std.mem.eql(u8, field.name, target[1..])) {
                        Main.users.mutex.lock();
                        defer Main.users.mutex.unlock();

                        var iter = Main.users.hash_map.valueIterator();

                        //Iterate over every logged in player
                        while (iter.next()) |next| {
                            var target_client: RcClient = next.*;

                            //Dont send the message to the message sender
                            if (target_client.data.stats.user_id == client.stats.user_id) {
                                continue;
                            }

                            //If the user is not in the channel
                            if (!@field(target_client.data.channels, field.name)) {
                                //Skip this user
                                continue;
                            }

                            //If the are in the channel, send them a new packet
                            //NOTE: the reason we construct the packet here is so that
                            //      it gets borrowed for each time its sent in the network
                            Main.thread_pool.spawn(sendPackets, .{ target_client.borrow(), .{Packets.Server.SendMessage.create_channel_target(
                                client_rc.borrow(),
                                "#" ++ field.name,
                                message,
                            )}, null, .{} }) catch unreachable;
                        }

                        break;
                    }
                }
            },
            .send_irc_message_private => {
                const packet = Packets.Client.SendIrcMessage.deserialize(reader) catch unreachable;

                const target = packet.data.target.slice();
                const message = packet.data.message.slice();

                Main.users.mutex.lock();
                defer Main.users.mutex.unlock();

                var iter = Main.users.hash_map.valueIterator();

                while (iter.next()) |next| {
                    var target_client_rc: RcClient = next.*;
                    var target_client: *Client = target_client_rc.data;

                    const username = target_client.username.slice();

                    //If the username matches
                    if (std.mem.eql(u8, username, target)) {
                        Main.thread_pool.spawn(sendPackets, .{
                            target_client_rc.borrow(),
                            .{Packets.Server.SendMessage.create_client_target(
                                client_rc.borrow(),
                                target_client_rc.borrow(),
                                message,
                            )},
                            null,
                            .{},
                        }) catch unreachable;
                        break;
                    }
                }
            },
            else => {
                var left_to_read: usize = @intCast(payload_size);
                while (left_to_read > 0) {
                    left_to_read -= reader.read(buf[0..@min(payload_size, buf.len)]) catch unreachable;
                }
            },
        }

        std.debug.print("read packet {s}, size {d}\n", .{ @tagName(packet_id), payload_size });

        //Safety check, since we buffer packets so aggressively, we need to be sure we have read all the bytes in the payload
        std.debug.assert(client.bytes_read - before_bytes_read == payload_size);
    }
}

fn handleClientDisconnect(client: *const Client, allocator: std.mem.Allocator) void {
    _ = allocator;

    //Lock the user hash map mutex
    Main.users.mutex.lock();
    defer Main.users.mutex.unlock();

    std.debug.print("closing user socket\n", .{});

    //Closing socket
    client.socket.close();

    const user_id = client.stats.user_id;

    std.debug.print("removing user from hash map\n", .{});

    //Remove the user from the list
    std.debug.assert(Main.users.hash_map.remove(user_id));

    std.debug.print("telling all users the user has left\n", .{});
    var iter = Main.users.hash_map.valueIterator();
    while (iter.next()) |next| {
        const client_to_notify: RcClient = next.*;

        Main.thread_pool.spawn(sendPackets, .{ client_to_notify.borrow(), .{
            Packets.Server.HandleOsuQuit.create(user_id),
        }, null, .{} }) catch unreachable;
    }
}
