const std = @import("std");
const network = @import("network");
const memutils = @import("memutils");

const Bancho = @import("bancho/bancho.zig");
const Client = Bancho.Client;

const RcClient = Bancho.RcClient;

const UserHashMap = struct {
    pub const HashMap = std.AutoHashMap(Bancho.Int, RcClient);

    hash_map: HashMap,
    mutex: std.Thread.Mutex,
};

pub var users: UserHashMap = undefined;
pub var thread_pool: std.Thread.Pool = undefined;

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
    var keepalive_thread = try std.Thread.spawn(.{}, Bancho.keepaliveRun, .{&run});
    try keepalive_thread.setName("ping");

    var check_for_client_data_thread = try std.Thread.spawn(.{}, Bancho.checkForClientDataPeriodically, .{&run});
    try check_for_client_data_thread.setName("data");

    std.debug.print("Started server on port {d}\n", .{port});

    while (true) {
        var client_socket = try server_socket.accept();

        //Timeout in seconds
        const timeout = 10;

        //Set the client socket read/write timeouts
        try client_socket.setReadTimeout(timeout * std.time.us_per_s);
        try client_socket.setWriteTimeout(timeout * std.time.us_per_s);

        //Make one of the threads in the thread pool handle the user logon
        try thread_pool.spawn(Bancho.handleUserLogin, .{ client_socket, server_socket, allocator });
    }
}
