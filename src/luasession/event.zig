const session = @import("session.zig");
const LuaSession = session.LuaSession;

pub const EventBody = union(enum) {
    initialize_service: struct {},
    deinitialize_service: struct {},
    debug_print: []u8,
    command: struct {
        playerID: usize,
        command: []u8,
        message: []u8,
    },
    custom_with_data: struct {
        exec: *const EventHandler,
        data: ?*anyopaque,
        size: usize,
    },

};

//NOTE the corrent implementation of Event is subject to change
pub const EventHandler = fn (event: *Event, lua: *LuaSession) void;
pub const Event = struct {
    deinit: ?*const EventHandler, //unload event
    body: EventBody,
};
