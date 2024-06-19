const std = @import("std");
const ziglua = @import("root").ziglua;
const LuaEngine = ziglua.Lua;

pub const Error = error {
    DoubleInit,
    DoubleDeinit, //or not inited
    Error,
    IOError,
};

pub const LuaSession = struct {
    initialized: bool = false,
    eventSystem: bool = false, //represents initialized check and anyopaque table key
    pub fn init(self: *LuaSession, luaEngine: *LuaEngine) anyerror!void {
        std.debug.assert(self.*.initialized == false);
        self.*.initialized = true;
        luaEngine.pushInteger(42);
        //std.debug.print("lua: {}\n", .{try luaEngine.toInteger(1)});
        luaEngine.pop(-1);
        //_ = luaEngine; // var IS USED
    }

    pub fn installCommonSystems(self: *LuaSession, luaEngine: *LuaEngine) anyerror!void {
        luaEngine.openLibs();
        try self.installEventSystem(luaEngine);
    }

    pub fn installEventSystem(self: *LuaSession, luaEngine: *LuaEngine) anyerror!void {
        std.debug.assert(self.*.eventSystem == false);
        self.*.eventSystem = true;
        luaEngine.pushLightUserdata(&(self.*.eventSystem));
        luaEngine.newTable();
        luaEngine.setTable((ziglua.registry_index));
    }

    //TODO HACK file string is a const, change to *string or zig equivlant
    //TODO from server.init(...) inline into function;
    pub fn loadContextlessFile(self: *LuaSession, luaEngine: *LuaEngine) anyerror!void {
        try luaEngine.loadFile("server_init_contextless.lua",.text);
        // 0 inputs 0, returns, index of 0 for some reason
        // argument 3 is `0` in this simmlar function, blindly cloning
        // https://github.com/natecraddock/ziglua/blob/a7cf85fb871a95a46d4222fe3abdd3946e3e0dab/src/lib.zig#L2521
        try luaEngine.protectedCall(0,0,0);
        _ = self; //TEMP;
    }
};
