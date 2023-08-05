pub const PacketId = enum(u16) {
    ///The client is sending a new user status
    send_user_status = 0,
    ///The client is sending an IRC message
    send_irc_message = 1,
    ///The client is exiting
    exit = 2,
    ///The client is requesting a status update
    request_status_update = 3,
    ///The client is responding to a server ping
    pong = 4,
    ///The client is wanting to start spectating
    start_spectating = 16,
    ///The client is wanting to stop spectating
    stop_spectating = 17,
    ///The client is sending spectator frames
    spectate_frames = 18,
    ///The client is sending an error report to the server
    error_report = 20,
    ///TODO
    cant_spectate = 21,
    ///The client is trying to send a private message
    send_irc_message_private = 25,
    ///The client is trying to part from the lobby
    lobby_part = 29,
    ///The client is trying to join the lobby
    lobby_join = 30,
    ///The client is trying to create a match
    match_create = 31,
    ///The client is trying to join a match
    match_join = 32,
    ///The client is trying to leave a match
    match_part = 33,
    ///The client wants to change slot
    match_change_slot = 38,
    ///The client is readying up
    match_ready = 39,
    ///The client is locking some slot
    match_lock = 40,
    ///The client is changing match settings
    match_change_settings = 41,
    ///The client is starting the match
    match_start = 44,
    ///The client is sending a score update to the server
    match_score_update = 47,
    ///The client is telling the server they have completed the map
    match_complete = 49,
    ///The client is changing the mods on the match
    match_change_mods = 51,
    ///The client has finished loading the map
    match_load_complete = 52,
    ///The client is stating it does not have the map
    match_no_beatmap = 54,
    ///The client is unreadying
    match_not_ready = 55,
    ///The client is saying they have failed
    match_failed = 56,
    ///The client is saying the have aquired the map
    match_has_beatmap = 59,
    ///The client is sending a skip request
    match_skip_request = 60,
    ///The client is trying to join a channel
    channel_join = 63,
    ///The client is requesting info about a beatmap
    beatmap_info_request = 68,
    ///The client is trying to transfer the host of the match
    match_transfer_host = 70,
    ///The client is trying to add a user to the friends list
    friend_add = 73,
    ///The client is trying to remove someone from their friends list
    friend_remove = 74,
    ///The client is trying to change team
    match_change_team = 77,
    ///The client is leaving a channel
    channel_leave = 78,
    ///TODO
    receive_updates = 79,
    ///The client is setting their IRC "away" message
    set_irc_away_message = 82,
    ///The client is requesting a user stats update
    user_stats_request = 85,
};
