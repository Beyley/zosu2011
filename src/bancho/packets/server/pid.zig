pub const PacketId = enum(u16) {
    ///The server is telling the client the login response, whether that be an error, or their user ID
    login_reply = 5,
    ///The command the user sent through the chat has errored
    command_error = 6,
    ///The server is notifying a client that a message was sent
    send_message = 7,
    ///The server is sending a ping to the client
    ping = 8,
    ///The server is telling a client to handle a IRC username change
    handle_irc_change_username = 9,
    ///The server is telling a client to handle an IRC user leaving a channel
    handle_irc_quit = 10,
    ///The server is telling a client that a user's stats have updated
    handle_osu_update = 11,
    ///The server is telling the client a user has quit
    handle_osu_quit = 12,
    ///The server is telling the client a spectator has started watching them
    spectator_joined = 13,
    ///The server is telling the client a spectator has stopped watching them
    spectator_left = 14,
    ///The server is giving a client new spectator frames
    spectate_frames = 15,
    ///The server is telling the client there is a version update
    version_update = 19,
    ///The server is telling the client that the spectate request failed
    spectator_cant_spectate = 22,
    ///The server is force opening the chat window for something important
    get_attention = 23,
    ///The server is announcing something to all users
    announce = 24,
    ///The server is sending a match update to a client
    match_update = 26,
    ///The server is telling a client a new match was created
    match_new = 27,
    ///The server is telling a client a match was disbanded
    match_disband = 28,
    ///The server is telling a client that someone joined the lobby
    lobby_join = 34,
    ///The server is telling a client that someone left the lobby
    lobby_part = 35,
    ///The server is telling a client that joining a match succeeded
    match_join_success = 36,
    ///The server is telling a client that joining a match has failed
    match_join_fail = 37,
    ///The server is telling a client that a fellow spectator has joined the person they are spectating
    fellow_spectator_joined = 42,
    ///The server is telling a client that a fellow spectator has stopped spectating the person they are spectating
    fellow_spectator_left = 43,
    ///The server is telling a client that all players have loaded in the match
    all_players_loaded = 45,
    ///The server is telling the client that the match is starting
    match_start = 46,
    ///The server is telling the client that there is a score update for some user
    match_score_update = 48,
    ///The server is telling the client that the host is transferring to another user in the match
    match_transfer_host = 50,
    ///The server is telling the client that all players in teh match have loaded
    match_all_players_loaded = 53,
    ///The server is telling the client that some person has failed
    match_player_failed = 57,
    ///The server is telling the client that the match has completed
    match_complete = 58,
    ///The server is telling the client to skip the song intro
    match_skip = 61,
    ///TODO
    unauthorised = 62,
    ///The server is telling the client that joining the channel was a success
    channel_join_success = 64,
    ///The server is telling the client that a new channel is available to join
    channel_available = 65,
    ///The server is telling the client that a channel was revoked
    channel_revoked = 66,
    ///The server is telling the client that a new channel is available, and that it will auto-join it
    channel_available_autojoin = 67,
    ///The server is sending the beatmap info in response to a client's request
    beatmap_info_reply = 69,
    ///The server is telling the user what permissions they have
    login_permissions = 71,
    ///The server is sending the client their friends list
    friends_list = 72,
    ///The server is telling the client what protocol version it supports
    protocol_negotiation = 75,
    ///The server is telling the client that the title image has updated
    title_update = 76,
    ///The server is telling the client to take a screenshot of their whole desktop, then upload it to the website
    monitor = 80,
    ///The server is telling the client that a player has skipped
    match_player_skipped = 81,
    ///The server is telling a client about the presence of a new user
    user_presence = 83,
    ///TODO
    irc_only = 84,
    ///The server is telling the client that the server is restarting
    restart = 86,
};
