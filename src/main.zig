const std = @import("std");
const network = @import("network");
const memutils = @import("memutils");

const Client = @import("client.zig");
const Packets = @import("packet.zig");

const RcClient = memutils.Rc(Client);

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

fn keepaliveRun(run: *bool) void {
    while (run.*) {
        {
            users.mutex.lock();
            defer users.mutex.unlock();

            var iter = users.hash_map.valueIterator();

            while (iter.next()) |next| {
                thread_pool.spawn(sendPackets, .{
                    next.*.borrow(),
                    .{Packets.PingPacket{ .data = .{} }},
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

fn handleClientData(client_rc: RcClient) void {
    defer client_rc.drop();

    var client: *Client = client_rc.data;
    defer client.reading.store(false, .SeqCst);

    var buf: [4096]u8 = undefined;

    //While there is data to recieve, or there are bytes left in our buffer
    while (client.socket.peek(&buf) catch unreachable != 0 or client.read_from_temp_buf < client.temp_read_buf_slice.len) {
        const reader = client.reader();

        const packet_id: Packets.ClientPacketType = @enumFromInt(reader.readIntLittle(u16) catch unreachable);
        const compression = reader.readIntLittle(u8) catch unreachable;
        _ = compression;
        const payload_size = reader.readIntLittle(u32) catch unreachable;

        const before_bytes_read = client.bytes_read;

        switch (packet_id) {
            .exit => {
                const update_available = reader.readIntLittle(Packets.BanchoInt) catch unreachable;
                _ = update_available;

                std.debug.print("user {s} exiting...\n", .{client.username});

                //TODO: handle user exits
                client_rc.drop();
                return;
            },
            .receive_updates => {
                const UpdateMode = enum(Packets.BanchoInt) {
                    none = 0,
                    all = 1,
                    friends = 2,
                };

                const update_mode: UpdateMode = @enumFromInt(reader.readIntLittle(Packets.BanchoInt) catch unreachable);

                std.debug.print("receive_updates with mode {s}\n", .{@tagName(update_mode)});

                users.mutex.lock();
                defer users.mutex.unlock();

                var iter = users.hash_map.valueIterator();

                while (iter.next()) |next| {
                    const updated_client: *Client = next.*.get();

                    //TODO: filter by friends if update_mode == .friends

                    thread_pool.spawn(sendPackets, .{ client_rc.borrow(), .{
                        updated_client.getPresencePacket(),
                        updated_client.getUserUpdatePacket(),
                    }, null, .{} }) catch unreachable;
                }
            },
            .channel_join => {
                var channel_name_buf: [Client.MAX_CHANNEL_LENGTH]u8 = undefined;
                const channel_name = Packets.readBanchoString(reader, &channel_name_buf) catch unreachable;

                std.debug.print("user trying to join channel {s}\n", .{channel_name});

                //TODO: check permissions

                inline for (@typeInfo(Client.AvailableChannels).Struct.fields) |field| {
                    //If the name of the field and the channel name without the # equal,
                    if (std.mem.eql(u8, field.name, channel_name[1..])) {
                        thread_pool.spawn(sendPackets, .{ client_rc.borrow(), .{
                            Packets.ChannelJoinSuccessPacket{
                                .data = .{ .channel = "#" ++ field.name },
                            },
                        }, null, .{} }) catch unreachable;

                        //Mark that the user is in that channel
                        @field(client.channels, field.name) = true;

                        //Break out, as we found the channel
                        break;
                    }
                }
            },
            .channel_leave => {
                var channel_name_buf: [Client.MAX_CHANNEL_LENGTH]u8 = undefined;
                const channel_name = Packets.readBanchoString(reader, &channel_name_buf) catch unreachable;

                std.debug.print("user trying to leave channel {s}\n", .{channel_name});

                inline for (@typeInfo(Client.AvailableChannels).Struct.fields) |field| {
                    //If the name of the field and the channel name without the # equal,
                    if (std.mem.eql(u8, field.name, channel_name[1..])) {
                        thread_pool.spawn(sendPackets, .{ client_rc.borrow(), .{
                            Packets.ChannelRevokedPacket{
                                .data = .{ .channel = "#" ++ field.name },
                            },
                        }, null, .{} }) catch unreachable;

                        //Mark that the user is no longer in the channel
                        @field(client.channels, field.name) = false;

                        //Break out, as we found the channel
                        break;
                    }
                }
            },
            .send_irc_message => {
                var buf2: [0]u8 = undefined;
                //When the client sends send_irc_message, the `sender` field is never populated
                _ = Packets.readBanchoString(reader, &buf2) catch unreachable;
                var target_buf: [Client.MAX_CHANNEL_LENGTH]u8 = undefined;
                const message = Packets.readBanchoString(reader, &buf) catch unreachable;
                const target = Packets.readBanchoString(reader, &target_buf) catch unreachable;

                //Assert the user doesnt try to send too long of a message
                //TODO: cleanly handle this error case
                std.debug.assert(message.len <= Packets.MAX_MESSAGE_SIZE);

                std.debug.print("message {s} to target {s}\n", .{ message, target });

                inline for (@typeInfo(Client.AvailableChannels).Struct.fields) |field| {
                    if (std.mem.eql(u8, field.name, target[1..])) {
                        const create_message_packet = Packets.createSendMessagePacket(
                            client.username,
                            "#" ++ field.name,
                            message,
                        );

                        users.mutex.lock();
                        defer users.mutex.unlock();

                        var iter = users.hash_map.valueIterator();

                        //Iterate over every logged in player
                        while (iter.next()) |next| {
                            var target_client: RcClient = next.*;

                            //Dont send the message to the message sender
                            if (target_client.get().user_id == client.user_id) {
                                continue;
                            }

                            //If the user is not in the channel
                            if (!@field(target_client.get().channels, field.name)) {
                                //Skip this user
                                continue;
                            }

                            //If the are in the channel, send them the packet
                            thread_pool.spawn(sendPackets, .{ target_client.borrow(), .{create_message_packet}, null, .{} }) catch unreachable;
                        }

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
    users.mutex.lock();
    users.mutex.unlock();

    std.debug.print("closing user socket\n", .{});

    //Closing socket
    client.socket.close();

    const user_id = client.user_id;

    std.debug.print("removing user from hash map\n", .{});

    //Remove the user from the list
    std.debug.assert(users.hash_map.remove(user_id));

    std.debug.print("telling all users the user has left\n", .{});
    var iter = users.hash_map.valueIterator();
    while (iter.next()) |next| {
        const client_to_notify: RcClient = next.*;

        thread_pool.spawn(sendPackets, .{ client_to_notify.borrow(), .{Packets.HandleOsuQuitPacket{
            .data = .{ .user_id = user_id },
        }}, null, .{} }) catch unreachable;
    }
}

fn checkForClientDataPeriodically(run: *bool) void {
    while (run.*) {
        {
            users.mutex.lock();
            defer users.mutex.unlock();

            var iter = users.hash_map.valueIterator();

            while (iter.next()) |next| {
                var client_rc: RcClient = next.*;
                var client = client_rc.data;
                var reading = client.reading.load(.SeqCst);

                if (!reading) {
                    client.reading.store(true, std.atomic.Ordering.SeqCst);
                    thread_pool.spawn(handleClientData, .{
                        client_rc.borrow(),
                    }) catch @panic("OOM");
                }
            }
        }

        //Sleep for 10ms
        std.time.sleep(std.time.ns_per_ms * 10);
    }
}

const UserHashMap = struct {
    pub const HashMap = std.AutoHashMap(Packets.BanchoInt, RcClient);

    hash_map: HashMap,
    mutex: std.Thread.Mutex,
};

fn handleUserLogin(client_sock: network.Socket, server_socket: network.Socket, allocator: std.mem.Allocator) void {
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
        .username_buf = undefined,
        .username = &.{},
        .password = undefined,
        .display_city = false,
        .time_zone = 0,
        .write_mutex = std.Thread.Mutex{},
        .last_heard_from = std.time.timestamp(),
        .user_id = @intCast(users.hash_map.count() + 1),
        .status = Packets.StatusUpdate{
            .beatmap_checksum = undefined,
            .beatmap_id = 0,
            .current_mods = .{},
            .play_mode = .osu,
            .status = .idle,
            .status_text = "",
            .status_text_buf = undefined,
        },
    }, allocator) catch unreachable;
    client_rc.deinit_fn = handleClientDisconnect;
    var client = client_rc.data;

    @memset(&client.status.beatmap_checksum, 0);

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
    @memcpy(client.username_buf[0..read.len], read);
    //Set the client username slice to the right size
    client.username = client.username_buf[0..read.len];

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

    std.debug.print("client logging in, name {s} password {x}\n", .{ client.username, @as(u128, @bitCast(client.password)) });
    std.debug.print("version {s}\ntime_zone {d}\ndisplay_city {}\nosu_hash {s}\n", .{ version, client.time_zone, client.display_city, osu_hash });

    //TODO: password check here!

    //The permissions the user has (TODO: ping some kind of database to get this information)
    const permissions = Packets.LoginPermissions{
        .normal = true,
        .supporter = true,
        .bat = false,
        .friend = false,
    };

    //When a client connects we need to tell it what protocol version we are using
    var protocol_negotiation_packet = Packets.ProtocolNegotiationPacket{
        .data = .{},
    };

    //After the client has been told about the protocol version, send a login reply
    var login_response_packet = Packets.LoginReplyPacket{
        .data = .{
            .login_response = .{ .user_id = client.user_id },
        },
    };

    //After the client knows it was a successful login, send them their permissions
    var login_permissions_packet = Packets.LoginPermissionsPacket{
        .data = .{
            .permissions = permissions,
        },
    };

    var user_data_packet = client.getUserUpdatePacket();

    //Send the user a presence packet, giving all the nessesary info about themselves,
    //With this the client is happy to report that it is no longer "recieving data"
    var user_presence_packet = client.getPresencePacket();

    try thread_pool.spawn(sendPackets, .{
        client_rc.borrow(),
        .{
            protocol_negotiation_packet,
            login_response_packet,
            login_permissions_packet,
            user_data_packet,
            user_presence_packet,
        },
        sendAvailableChannels,
        .{},
    });

    users.mutex.lock();
    //Assert the user id doesnt already exist
    std.debug.assert(!users.hash_map.remove(client.user_id));
    //Put the user into the hash map
    try users.hash_map.put(client.user_id, client_rc);
    defer users.mutex.unlock();

    //If we error later on, remove the user from the list
    errdefer {
        //Assert the user id does exist, it should at this point
        std.debug.assert(users.hash_map.remove(client.user_id));
    }
}

fn sendAvailableChannels(client_rc: RcClient, args: anytype) void {
    _ = args;
    defer client_rc.drop();
    var client = client_rc.data;

    //Iterate over all known channels,
    inline for (@typeInfo(Client.AvailableChannels).Struct.fields) |field| {
        const channel_name = "#" ++ field.name;

        const available_packet = Packets.ChannelAvailablePacket{
            .data = .{
                .channel = channel_name,
            },
        };

        //If the user has joined the channel,
        if (@field(client.channels, field.name)) {
            //Send an available packet, then a success packet
            thread_pool.spawn(sendPackets, .{
                client_rc.borrow(),
                .{
                    available_packet,
                    Packets.ChannelJoinSuccessPacket{
                        .data = .{
                            .channel = channel_name,
                        },
                    },
                },
                null,
                .{},
            }) catch unreachable;
        } else {
            //Send only an available packet
            thread_pool.spawn(sendPackets, .{ client_rc.borrow(), .{available_packet}, null, .{} }) catch unreachable;
        }
    }
}

var users: UserHashMap = undefined;
var thread_pool: std.Thread.Pool = undefined;

pub fn main() !void {
    try network.init();
    defer network.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("MEMORY LEAK");

    var allocator = gpa.allocator();

    users = .{
        .hash_map = UserHashMap.HashMap.init(allocator),
        .mutex = .{},
    };
    defer {
        var iter = users.hash_map.valueIterator();

        while (iter.next()) |next| {
            var client: RcClient = next.*;

            client.drop();
        }

        users.hash_map.deinit();
    }

    //Create an IPV4 TCP socket
    var server_socket = try network.Socket.create(.ipv4, .tcp);

    const port = 13381;

    //Try to bind to port 13381 (the port Bancho uses)
    try server_socket.bindToPort(port);

    try server_socket.listen();

    //Create a thread pool to handle tasks like sending packets
    try thread_pool.init(.{ .allocator = allocator });
    defer thread_pool.deinit();

    var run: bool = true;
    defer run = false;

    //Spawn a thread to periodically send a "ping" to all clients, to make sure they havent died
    var keepalive_thread = try std.Thread.spawn(.{}, keepaliveRun, .{&run});
    try keepalive_thread.setName("ping");

    var check_for_client_data_thread = try std.Thread.spawn(.{}, checkForClientDataPeriodically, .{&run});
    try check_for_client_data_thread.setName("data");

    std.debug.print("Started server on port {d}\n", .{port});

    while (true) {
        var client_socket = try server_socket.accept();

        //Timeout in seconds
        const timeout = 10;

        try client_socket.setReadTimeout(timeout * std.time.us_per_s);
        try client_socket.setWriteTimeout(timeout * std.time.us_per_s);

        //Make one of the threads in the thread pool handle the user logon
        try thread_pool.spawn(handleUserLogin, .{ client_socket, server_socket, allocator });
    }
}
