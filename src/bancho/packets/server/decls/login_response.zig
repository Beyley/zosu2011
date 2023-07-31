const Bancho = @import("../../../bancho.zig");
const Packets = @import("../../packets.zig");
const PacketId = @import("../server.zig").PacketId;

pub const LoginResponseStatus = union(enum) {
    login_error: LoginResponseError,
    user_id: Bancho.Int,
};

pub const LoginResponseError = enum(Bancho.Int) {
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

pub const Packet = Packets.Packet(PacketId.login_reply, struct {
    login_response: LoginResponseStatus,

    const Self = @This();

    pub fn size(self: Self) u32 {
        _ = self;

        return @sizeOf(Bancho.Int);
    }

    pub fn serialize(self: Self, writer: Bancho.Client.Writer) !void {
        switch (self.login_response) {
            .login_error => |err| {
                try writer.writeIntLittle(Bancho.Int, @intFromEnum(err));
            },
            .user_id => |user_id| {
                try writer.writeIntLittle(Bancho.Int, user_id);
            },
        }
    }
});

pub fn create(status: LoginResponseStatus) Packet {
    return .{ .data = .{ .login_response = status } };
}
