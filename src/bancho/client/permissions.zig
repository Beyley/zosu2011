const Bancho = @import("../bancho.zig");

pub const Permissions = packed struct(Bancho.Int) {
    ///The user is a normal user
    normal: bool = true,
    ///The user is part of the BAT
    bat: bool,
    ///The user is supporting the server
    supporter: bool,
    ///The user is a friend
    friend: bool,
    ///Unused padding type
    _padding: u28 = 0,
};
