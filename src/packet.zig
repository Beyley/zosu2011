const std = @import("std");
const network = @import("network");

pub const WriterType = std.io.BufferedWriter(4096, network.Socket.Writer).Writer;

//Special bancho types
pub const BanchoByte = u8;
pub const BanchoUShort = u16;
pub const BanchoInt = i32;
pub const BanchoLong = i64;

fn writeUleb128(writer: WriterType, int: anytype) !void {
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

fn uleb128Size(int: anytype) u32 {
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

fn writeBanchoString(writer: WriterType, str: []const u8) !void {
    //If the length is 0
    if (str.len == 0) {
        //Write it as a "null object"
        try writer.writeIntLittle(BanchoByte, 0);
    } else {
        //Write it as a "string object"
        try writer.writeIntLittle(BanchoByte, 11);
        //Write the length to the stream
        try writeUleb128(writer, str.len);
        //Write the bytes of the string to the stream
        try writer.writeAll(str);
    }
}

fn banchoStringSize(str: []const u8) u32 {
    if (str.len == 0) return @sizeOf(BanchoByte);

    return @intCast(@sizeOf(BanchoByte) + uleb128Size(str.len) + str.len);
}

//I'm not 100% certain this is correct, but i dont see any code in the decomp referencing higher than 6, so lets assume it is!
const ProtocolVersion = 7;

pub const ProtocolNegotiationPacket = Packet(ServerPacketType.protocol_negotiation, struct {
    const Self = @This();

    pub fn size(self: Self) u32 {
        _ = self;

        return @sizeOf(BanchoInt);
    }

    pub fn serialize(self: Self, writer: WriterType) !void {
        _ = self;

        try writer.writeIntLittle(BanchoInt, ProtocolVersion);
    }
});

pub const LoginResponse = union(enum) {
    login_error: LoginResponseError,
    user_id: BanchoInt,
};

pub const LoginResponseError = enum(BanchoInt) {
    //The user's credentials are invalid
    invalid_credentials = -1,
    //The user's client is too old
    too_old = -2,
    //The user has been banned
    banned = -3,
    //The account has not been activated yet
    unactivated_account = -4,
    //Server side error
    server_side_error = -5,
    ///Using test build without supporter
    invalid_account_for_test_build = -6,
};

pub const LoginReplyPacket = Packet(ServerPacketType.login_reply, struct {
    login_response: LoginResponse,

    const Self = @This();

    pub fn size(self: Self) u32 {
        _ = self;

        return @sizeOf(BanchoInt);
    }

    pub fn serialize(self: Self, writer: WriterType) !void {
        switch (self.login_response) {
            .login_error => |err| {
                try writer.writeIntLittle(BanchoInt, @intFromEnum(err));
            },
            .user_id => |user_id| {
                try writer.writeIntLittle(BanchoInt, user_id);
            },
        }
    }
});

pub const LoginPermissions = packed struct(BanchoInt) {
    normal: bool,
    bat: bool,
    supporter: bool,
    friend: bool,
    padding: u28 = 0,
};

pub const LoginPermissionsPacket = Packet(ServerPacketType.login_permissions, struct {
    const Self = @This();

    permissions: LoginPermissions,

    pub fn size(self: Self) u32 {
        _ = self;

        return @sizeOf(BanchoInt);
    }

    pub fn serialize(self: Self, writer: WriterType) !void {
        try writer.writeIntLittle(BanchoInt, @as(BanchoInt, @bitCast(self.permissions)));
    }
});

pub const Mods = packed struct(BanchoInt) {
    padding: u32 = 0,
};

pub const PlayMode = enum(BanchoByte) {
    osu = 0,
    taiko = 1,
    catch_the_beat = 2,
};

pub const UserStatus = enum(BanchoByte) {
    idle,
    afk,
    playing,
    editing,
    modding,
    multiplayer,
    watching,
    unknown,
    testing,
    submitting,
    paused,
    lobby,
    multiplaying,
    osu_direct,
};

pub const StatusUpdate = struct {
    pub const MAX_STATUS_TEXT_LENGTH = 64;
    //The checksum of the beatmap the user is currentlyplaying on, 2x the actual digest length since its encoded as ASCII text
    beatmap_checksum: [std.crypto.hash.Md5.digest_length * 2]u8,
    beatmap_id: BanchoInt,
    current_mods: Mods,
    play_mode: PlayMode,
    status: UserStatus,
    status_text_buf: [MAX_STATUS_TEXT_LENGTH]u8,
    status_text: []const u8,

    const Self = @This();

    pub fn size(self: Self) u32 {
        return @sizeOf(BanchoInt) + @sizeOf(BanchoUShort) + @sizeOf(BanchoByte) * 2 + banchoStringSize(self.status_text) + banchoStringSize(&self.beatmap_checksum);
    }

    pub fn serialize(self: Self, writer: WriterType) !void {
        try writer.writeIntLittle(BanchoByte, @as(u8, @intFromEnum(self.status)));
        try writeBanchoString(writer, self.status_text);
        try writeBanchoString(writer, &self.beatmap_checksum);
        try writer.writeIntLittle(BanchoUShort, @as(BanchoUShort, @truncate(@as(u32, @bitCast(self.current_mods)))));
        try writer.writeIntLittle(BanchoByte, @intFromEnum(self.play_mode));
        try writer.writeIntLittle(BanchoInt, self.beatmap_id);
    }
};

pub const UserStats = struct {
    accuracy: f32,
    level: BanchoInt,
    play_count: BanchoInt,
    rank: BanchoInt,
    ranked_score: BanchoLong,
    status: StatusUpdate,
    total_score: BanchoLong,
    user_id: BanchoInt,

    const Self = @This();

    pub fn size(self: Self) u32 {
        return @sizeOf(f32) + @sizeOf(BanchoInt) * 3 + @sizeOf(BanchoLong) * 2 + self.status.size();
    }

    pub fn serialize(self: Self, writer: WriterType) !void {
        try writer.writeIntLittle(BanchoInt, self.user_id);
        try self.status.serialize(writer);
        try writer.writeIntLittle(BanchoLong, self.ranked_score);
        try writer.writeAll(std.mem.asBytes(&self.accuracy));
        try writer.writeIntLittle(BanchoInt, self.play_count);
        try writer.writeIntLittle(BanchoLong, self.total_score);
        try writer.writeIntLittle(BanchoInt, self.rank);
    }
};

pub const UserUpdatePacket = Packet(ServerPacketType.handle_osu_update, struct {
    const Self = @This();

    user_stats: UserStats,

    pub fn size(self: Self) u32 {
        return self.user_stats.size();
    }

    pub fn serialize(self: Self, writer: WriterType) !void {
        try self.user_stats.serialize(writer);
    }
});

pub const ChannelAvailablePacket = Packet(ServerPacketType.channel_available, struct {
    const Self = @This();

    channel: []const u8,

    pub fn size(self: Self) u32 {
        return banchoStringSize(self.channel);
    }

    pub fn serialize(self: Self, writer: WriterType) !void {
        try writeBanchoString(writer, self.channel);
    }
});

pub const ChannelJoinSuccessPacket = Packet(ServerPacketType.channel_join_success, struct {
    const Self = @This();

    channel: []const u8,

    pub fn size(self: Self) u32 {
        return banchoStringSize(self.channel);
    }

    pub fn serialize(self: Self, writer: WriterType) !void {
        try writeBanchoString(writer, self.channel);
    }
});

pub const AvatarExtension = enum(BanchoByte) {
    none = 0,
    png = 1,
    jpeg = 2,
};

pub const UserPresence = struct {
    country: BanchoByte,
    city: []const u8,
    permissions: LoginPermissions,
    avatar_extension: AvatarExtension,
    timezone: i8,
    user_id: BanchoInt,
    username: []const u8,
    longitude: f32,
    latitude: f32,
    rank: BanchoInt,

    const Self = @This();

    pub fn size(self: Self) u32 {
        return @sizeOf(BanchoByte) * 4 + @sizeOf(BanchoInt) * 2 + @sizeOf(f32) * 2 + banchoStringSize(self.city) + banchoStringSize(self.username);
    }

    pub fn serialize(self: Self, writer: WriterType) !void {
        try writer.writeIntLittle(BanchoInt, self.user_id);
        try writeBanchoString(writer, self.username);
        try writer.writeIntLittle(BanchoByte, @intFromEnum(self.avatar_extension));
        try writer.writeIntLittle(BanchoByte, @as(BanchoByte, @intCast(self.timezone + 24)));
        try writer.writeIntLittle(BanchoByte, self.country);
        try writeBanchoString(writer, self.city);
        try writer.writeIntLittle(BanchoByte, @as(BanchoByte, @truncate(@as(u32, @bitCast(self.permissions)))));
        try writer.writeAll(std.mem.asBytes(&self.longitude));
        try writer.writeAll(std.mem.asBytes(&self.latitude));
        try writer.writeIntLittle(BanchoInt, self.rank);
    }
};

pub const UserPresencePacket = Packet(ServerPacketType.user_presence, struct {
    const Self = @This();

    user_presence: UserPresence,

    pub fn size(self: Self) u32 {
        return self.user_presence.size();
    }

    pub fn serialize(self: Self, writer: WriterType) !void {
        try self.user_presence.serialize(writer);
    }
});

pub const PingPacket = Packet(ServerPacketType.ping, struct {
    const Self = @This();

    pub fn size(self: Self) u32 {
        _ = self;

        return 0;
    }

    pub fn serialize(self: Self, writer: WriterType) !void {
        _ = writer;
        _ = self;
    }
});

pub fn Packet(comptime packet_id: anytype, comptime DataType: type) type {
    if (@sizeOf(@TypeOf(packet_id)) != @sizeOf(u16)) {
        @compileError("Invalid packet id type! Type must be of size u16");
    }

    return struct {
        data: DataType,

        const Self = @This();

        pub fn serialize(self: Self, writer: WriterType) !void {
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

pub const ServerPacketType = enum(u16) {
    login_reply = 5,
    command_error = 6,
    send_message = 7,
    ping = 8,
    handle_irc_change_username = 9,
    handle_irc_quit = 10,
    handle_osu_update = 11,
    handle_osu_quit = 12,
    spectator_joined = 13,
    spectator_left = 14,
    spectate_frames = 15,
    version_update = 19,
    spectator_cant_spectate = 22,
    get_attention = 23,
    announce = 24,
    match_update = 26,
    match_new = 27,
    match_disband = 28,
    lobby_join = 34,
    lobby_part = 35,
    match_join_success = 36,
    match_join_fail = 37,
    fellow_spectator_joined = 42,
    fellow_spectator_left = 43,
    all_players_loaded = 45,
    match_start = 46,
    match_score_update = 48,
    match_transfer_host = 50,
    match_all_players_loaded = 53,
    match_player_failed = 57,
    match_complete = 58,
    match_skip = 61,
    unauthorised = 62,
    channel_join_success = 64,
    channel_available = 65,
    channel_revoked = 66,
    channel_available_autojoin = 67,
    beatmap_info_reply = 69,
    login_permissions = 71,
    friends_list = 72,
    protocol_negotiation = 75,
    title_update = 76,
    monitor = 80,
    match_player_skipped = 81,
    user_presence = 83,
    irc_only = 84,
    restart = 86,
};

pub const ClientPacketType = enum(u16) {
    send_user_status = 0,
    send_irc_message = 1,
    exit = 2,
    request_status_update = 3,
    pong = 4,
    start_spectating = 16,
    stop_spectating = 17,
    spectate_frames = 18,
    error_report = 20,
    cant_spectate = 21,
    send_irc_message_private = 25,
    lobby_part = 29,
    lobby_join = 30,
    match_create = 31,
    match_join = 32,
    match_part = 33,
    match_change_slot = 38,
    match_ready = 39,
    match_lock = 40,
    match_change_settings = 41,
    match_start = 44,
    match_score_update = 47,
    match_complete = 49,
    match_change_mods = 51,
    match_load_complete = 52,
    match_no_beatmap = 54,
    match_not_ready = 55,
    match_failed = 56,
    match_has_beatmap = 59,
    match_skip_request = 60,
    channel_join = 63,
    beatmap_info_request = 68,
    match_transfer_host = 70,
    friend_add = 73,
    friend_remove = 74,
    match_change_team = 77,
    channel_leave = 78,
    receive_updates = 79,
    set_irc_away_message = 82,
    user_stats_request = 85,
};
