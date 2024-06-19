const std = @import("std");
const ziglua = @import("root").ziglua;
const LuaSession = @import("root").luasession.LuaSession;
const Platform = @import("root").luasession.Platform;
const Userdata = @import("root").luasession.Userdata;
const LuaState = ziglua.Lua;

var identityPointer: Userdata = .None;

pub fn install(session: *LuaSession, platform: Platform) anyerror!void {
    if (identityPointer == .None){
        identityPointer = .Unique;
    }
    _ = platform; // we dont care, install everywhere
    const luaState = session.*.luaState;
    
    // WARNING luac api will push and pop values without warning and you will
    // get a genaric "stopped" message. read the documentation for all functions
    // before use
    
    luaState.pushLightUserdata(&identityPointer); // push `testForK`
    _ = luaState.getTable(ziglua.registry_index); // push `testForV` pop `testForK`
    const isNil = luaState.isNil(-1);
    luaState.pop(-1); //pop `testForV`
    if( isNil ) {
        luaState.pushLightUserdata(&identityPointer); // push `k`
        luaState.newTable(); // push `v`
        luaState.setTable(ziglua.registry_index); //pops `k` and `v`
        std.log.info("setnew",.{});
    }
}
