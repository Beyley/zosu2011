pub const PacketId = @import("pid.zig").PacketId;

pub const Ping = @import("decls/ping.zig");
pub const ProtocolNegotiation = @import("decls/protocol_negotiation.zig");
pub const LoginResponse = @import("decls/login_response.zig");
pub const LoginPermissions = @import("decls/login_permissions.zig");
pub const UserUpdate = @import("decls/user_update.zig");
pub const UserPresence = @import("decls/user_presence.zig");
pub const ChannelAvailable = @import("decls/channel_available.zig");
pub const ChannelJoinSuccess = @import("decls/channel_join_success.zig");
pub const ChannelRevoked = @import("decls/channel_revoked.zig");
pub const HandleOsuQuit = @import("decls/handle_osu_quit.zig");
pub const SendMessage = @import("decls/send_message.zig");
