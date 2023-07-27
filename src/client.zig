const std = @import("std");
const network = @import("network");

pub const MAX_USERNAME_LENGTH = 32;

username_buf: [MAX_USERNAME_LENGTH]u8,
username: []u8,
password: [std.crypto.hash.Md5.digest_length]u8,
socket: network.Socket,
writer: std.io.BufferedWriter(4096, network.Socket.Writer),
write_mutex: std.Thread.Mutex,

time_zone: i8,
display_city: bool,
