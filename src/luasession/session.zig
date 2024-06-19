const std = @import("std");
const ziglua = @import("root").ziglua;
const LuaState = ziglua.Lua;
const modList = @import("libraryList.zig");

const modLength = @typeInfo(modList).Struct.decls.len;

pub const Error = error {
    DoubleInit,
    DoubleDeinit, //or not inited
    Error,
    IOError,
};

pub const Platform = enum {
    Server,
    Client,
};

pub const Userdata = union(enum) {
    None, //no special handle
    Unique, // just has to be unique 
    //WIP
};

pub const LuaSession = struct {
    initialized: bool = false,
    eventSystem: bool = false, //represents initialized check and anyopaque table key
    
    luaState: *LuaState = undefined,
    
    
    pub fn init(self: *LuaSession, luaState: *LuaState) anyerror!void {
        std.debug.assert(self.*.initialized == false);
        self.*.initialized = true;
        self.*.luaState = luaState;
    }

    pub fn installCommonSystems(self: *LuaSession, targetPlatform: Platform) anyerror!void {
        std.debug.assert(self.*.initialized == true);
        const luaState = self.*.luaState;
        luaState.openLibs();
            
        inline for(@typeInfo(modList).Struct.decls) |decl| {
            std.log.info("install {s}",.{decl.name});
            _ = try @field(modList, decl.name).install(self,targetPlatform);
        }
    }

    //TODO HACK file string is a const, change to *string or zig equivlant
    //TODO from server.init(...) inline into function;
    pub fn loadContextlessFile(self: *LuaSession) anyerror!void {
        std.debug.assert(self.*.initialized == true);
        const luaState = self.*.luaState;
        
        std.debug.assert(self.*.initialized == true);
        try luaState.loadFile("server_init_contextless.lua",.text);
        // 0 inputs 0, returns, index of 0 for some reason
        // argument 3 is `0` in this simmlar function, blindly cloning
        // https://github.com/natecraddock/ziglua/blob/a7cf85fb871a95a46d4222fe3abdd3946e3e0dab/src/lib.zig#L2521
        try luaState.protectedCall(0,0,0);
    }
};