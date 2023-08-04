pub const PacketId = @import("pid.zig").PacketId;

pub const Exit = @import("decls/exit.zig").Packet;
pub const ReceiveUpdates = @import("decls/receive_updates.zig").Packet;
pub const ChannelJoin = @import("decls/channel_join.zig").Packet;
pub const ChannelLeave = @import("decls/channel_leave.zig").Packet;
pub const SendIrcMessage = @import("decls/send_irc_message.zig").Packet;
pub const SendUserStatus = @import("decls/send_user_status.zig").Packet;
