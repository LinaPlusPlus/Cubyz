const std = @import("std");
const Channel = @import("fifoPolyfill.zig").Channel;
const ziglua = @import("root").ziglua;
const LuaEngine = ziglua.Lua;

pub const LuaSession = struct {
    initialized: bool = false,
    pub fn init(self: *LuaSession, luaEngine: *LuaEngine) anyerror!void {
        std.debug.assert(self.initialized == false);
        self.initialized = true;
        luaEngine.pushInteger(42);
        std.debug.print("lua: {}\n", .{try luaEngine.toInteger(1)});
    }
};
