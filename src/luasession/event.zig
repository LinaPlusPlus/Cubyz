const session = @import("session.zig");
const LuaSession = session.LuaSession;
const Userdata = session.Userdata;


pub const EventBodyKind = enum(u8){
    nil = 0, //may change
    initialize,
    deinitialize,
    debug_print,
    command,
    lua_made_event,
    custom_with_data,
};

pub const EventBody = union(EventBodyKind) {
    nil: struct {},
    initialize: struct {},
    deinitialize: struct {},
    debug_print: []u8,
    command: struct {
        playerID: usize,
        command: []u8,
        message: []u8,
    },
    lua_made_event: *Userdata, //cannot trust this wont be copied
    custom_with_data: struct {
        exec: *const EventHandler,
        data: ?*anyopaque,
        size: usize,
    },

};

pub const EventBodyLen = @typeInfo(EventBodyKind).Enum.fields.len;

//NOTE the corrent implementation of Event is subject to change
pub const EventHandler = fn (event: *Event, lua: *LuaSession) void;
pub const Event = struct {
    deinit: ?*const EventHandler, //unload event
    body: EventBody,
};
