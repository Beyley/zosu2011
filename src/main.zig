const std = @import("std");
const network = @import("network");

const Client = @import("client.zig");
const Packets = @import("packet.zig");

pub fn sendPackets(client: *Client, packets: anytype) void {
    //Lock the mutex to make sure no other packets are sent during the sending of this one
    client.write_mutex.lock();
    defer client.write_mutex.unlock();

    inline for (@typeInfo(@TypeOf(packets)).Struct.fields) |field| {
        const packet = @field(packets, field.name);

        //Serialize the packet into the stream
        packet.serialize(client.writer.writer()) catch @panic("UNABLE TO RECOVER FROM WRITE ERROR WAAAA");
    }
    client.writer.flush() catch @panic("UNABLE TO RECOVER FROM FLUSH WAA");
}

fn keepaliveRun(thread_pool: *std.Thread.Pool, clients: *UserHashMap, run: *bool) void {
    while (run.*) {
        {
            clients.mutex.lock();
            defer clients.mutex.unlock();

            var iter = clients.hash_map.valueIterator();

            while (iter.next()) |next| {
                thread_pool.spawn(sendPackets, .{
                    next.*,
                    .{Packets.PingPacket{ .data = .{} }},
                }) catch @panic("OOM");
            }

            std.debug.print("keepalive\n", .{});
        }

        const keepalive_time = 5;

        //Sleep for 1 second
        std.time.sleep(std.time.ns_per_s * keepalive_time);
    }
}

fn handleClientData(client: *Client, thread_pool: *std.Thread.Pool) void {
    _ = thread_pool;

    var buf: [4096]u8 = undefined;

    std.debug.print("thhsat {}\n", .{client.socket.internal});

    //If the client has no data to receive,
    if (client.socket.peek(&buf) catch unreachable == 0) {
        //Do nothing
        return;
    }

    const reader = client.reader();

    const packet_id: Packets.ClientPacketType = @enumFromInt(reader.readIntLittle(u16) catch unreachable);
    const compression = reader.readIntLittle(u8) catch unreachable;
    const payload_size = reader.readIntLittle(u32) catch unreachable;

    _ = reader.read(buf[0..payload_size]) catch unreachable;

    std.debug.print("GOT PACKET {s} {} {d}\n", .{ @tagName(packet_id), compression, payload_size });
}

fn checkForClientDataPeriodically(thread_pool: *std.Thread.Pool, clients: *UserHashMap, run: *bool) void {
    while (run.*) {
        {
            clients.mutex.lock();
            defer clients.mutex.unlock();

            var iter = clients.hash_map.valueIterator();

            while (iter.next()) |next| {
                thread_pool.spawn(handleClientData, .{
                    next.*,
                    thread_pool,
                }) catch @panic("OOM");
            }
        }

        //Sleep for 10ms
        std.time.sleep(std.time.ns_per_ms * 10);
    }
}

const UserHashMap = struct {
    pub const HashMap = std.AutoHashMap(Packets.BanchoInt, *Client);

    hash_map: HashMap,
    mutex: std.Thread.Mutex,
};

fn handleUserLogin(client_sock: network.Socket, server_socket: network.Socket, users: *UserHashMap, thread_pool: *std.Thread.Pool, allocator: std.mem.Allocator) void {
    std.debug.print("Client connected from {}\n", .{client_sock.getRemoteEndPoint() catch @panic("shit")});

    handleUserHandshake(client_sock, server_socket, users, thread_pool, allocator) catch @panic("user login fail");
}

fn handleUserHandshake(client_sock: network.Socket, server_socket: network.Socket, users: *UserHashMap, thread_pool: *std.Thread.Pool, allocator: std.mem.Allocator) !void {
    //Get the raw writer
    var raw_writer = client_sock.writer();
    //Get a buffered writer over the raw writer
    var writer = std.io.bufferedWriter(raw_writer);

    var client = allocator.create(Client) catch @panic("OOM");
    // var client = Client{
    client.* = Client{
        .socket = server_socket,
        .writer = writer,
        .username_buf = undefined,
        .username = &.{},
        .password = undefined,
        .display_city = false,
        .time_zone = 0,
        .write_mutex = std.Thread.Mutex{},
        .last_heard_from = std.time.timestamp(),
    };

    var buf: [4096]u8 = undefined;

    var read: usize = undefined;

    read = try client_sock.receive(&buf);
    //If its less than 2 chars long, this is invalid
    if (read < 2) return;
    //Remove the ending \r\n
    read -= 2;

    //If the username length is too long, return out
    //TODO: return real error here to the client
    if (read > Client.MAX_USERNAME_LENGTH) return;

    //Copy in the client username
    @memcpy(client.username_buf[0..read], buf[0..read]);
    //Set the client username slice to the right size
    client.username = client.username_buf[0..read];

    read = try client_sock.receive(&buf);

    //If its less than 2 chars long, this is invalid
    if (read < 2) return;
    //Remove the ending \r\n
    read -= 2;

    //Parse the password into an array of bytes
    client.password = @bitCast(try std.fmt.parseInt(u128, buf[0..read], 16));

    read = try client_sock.receive(&buf);

    //If its less than 2 chars long, this is invalid
    if (read < 2) return;
    //Remove the ending \r\n
    read -= 2;

    //Split up the info line
    var info_iter = std.mem.split(u8, buf[0..read], "|");

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

    //Return the user id (TODO: return unique IDs for each user)
    const user_id = 0;

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
            .login_response = .{ .user_id = user_id },
        },
    };

    //After the client knows it was a successful login, send them their permissions
    var login_permissions_packet = Packets.LoginPermissionsPacket{
        .data = .{
            .permissions = permissions,
        },
    };

    //After the client knows their permissions, let them know about the #osu channel
    var channel_available_packet = Packets.ChannelAvailablePacket{
        .data = .{
            .channel = "#osu",
        },
    };

    //Force the user to join the #osu channel, the client uses this to determine when the login handshake is complete, for some reason
    var channel_join_success_packet = Packets.ChannelJoinSuccessPacket{
        .data = .{
            .channel = "#osu",
        },
    };

    //Send the user their user stats
    var user_data_packet = Packets.UserUpdatePacket{
        .data = .{
            .user_stats = Packets.UserStats{
                .accuracy = 1,
                .level = 0,
                .play_count = 1,
                .rank = 69,
                .ranked_score = 96,
                .status = Packets.StatusUpdate{
                    .beatmap_checksum = std.mem.zeroes([std.crypto.hash.Md5.digest_length * 2]u8),
                    .beatmap_id = 1,
                    .current_mods = .{},
                    .play_mode = .osu,
                    .status = Packets.UserStatus.idle,
                    .status_text = "",
                    .status_text_buf = undefined,
                },
                .total_score = 420,
                .user_id = user_id,
            },
        },
    };

    //Send the user a presence packet, giving all the nessesary info about themselves,
    //With this the client is happy to report that it is no longer "recieving data"
    var user_presence_packet = Packets.UserPresencePacket{
        .data = .{
            .user_presence = Packets.UserPresence{
                .avatar_extension = .png,
                .city = "city eamoa",
                .country = 1,
                .longitude = 2,
                .latitude = 3,
                .permissions = permissions,
                .rank = 69,
                .timezone = client.time_zone,
                .user_id = user_id,
                .username = client.username,
            },
        },
    };

    try thread_pool.spawn(sendPackets, .{
        &client,
        .{
            protocol_negotiation_packet,
            login_response_packet,
            login_permissions_packet,
            channel_available_packet,
            channel_join_success_packet,
            user_data_packet,
            user_presence_packet,
        },
    });

    users.mutex.lock();
    //Assert the user id doesnt already exist
    std.debug.assert(!users.hash_map.remove(user_id));
    //Put the user into the hash map
    try users.hash_map.put(user_id, &client);
    users.mutex.unlock();

    //If we error later on, remove the user from the list
    errdefer {
        users.mutex.lock();
        //Assert the user id does exist, it should at this point
        std.debug.assert(users.hash_map.remove(user_id));
        users.mutex.unlock();
    }

    // const reader = client.reader();

    // while (true) {
    // }
}

pub fn main() !void {
    try network.init();
    defer network.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("MEMORY LEAK");

    var allocator = gpa.allocator();

    var users: UserHashMap = .{
        .hash_map = UserHashMap.HashMap.init(allocator),
        .mutex = .{},
    };
    defer {
        var iter = users.hash_map.valueIterator();

        while (iter.next()) |next| {
            allocator.destroy(next.*);
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
    var thread_pool: std.Thread.Pool = undefined;
    try thread_pool.init(.{ .allocator = allocator });
    defer thread_pool.deinit();

    var run: bool = true;
    defer run = false;

    //Spawn a thread to periodically send a "ping" to all clients, to make sure they havent died
    var keepalive_thread = try std.Thread.spawn(.{}, keepaliveRun, .{ &thread_pool, &users, &run });
    try keepalive_thread.setName("ping");

    var check_for_client_data_thread = try std.Thread.spawn(.{}, checkForClientDataPeriodically, .{ &thread_pool, &users, &run });
    try check_for_client_data_thread.setName("data");

    std.debug.print("Started server on port {d}\n", .{port});

    while (true) {
        var buf: [4096]u8 = undefined;
        _ = buf;

        var client_socket = try server_socket.accept();

        //Make one of the threads in the thread pool handle the user logon
        try thread_pool.spawn(handleUserLogin, .{ client_socket, server_socket, &users, &thread_pool, allocator });
    }
}
