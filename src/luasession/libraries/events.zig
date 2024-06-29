const std = @import("std");
const ziglua = @import("root").ziglua;
const luasession = @import("root").luasession;
const LuaSession = luasession.LuaSession;
const Platform = luasession.Platform;
const Userdata = luasession.Userdata;
const LuaState = ziglua.Lua;
const FnReg = ziglua.FnReg;

//TODO add fire(...), bind(...) and unbind(...) lua methods
//TODO add fire(...), bind(...) and unbind(...) zig methods

var eventTablePointer: Userdata = .None;

const libFunctions = struct {
    fn helloWorld(l: *LuaState) i32 {
        _ = l.pushString("hello, world!");
        return 1;
    }
};


pub fn install(session: *LuaSession, platform: Platform) anyerror!void {
    if (eventTablePointer == .None){
        // use this as a variable to satisfy compiler
        eventTablePointer = .Unique; 
    }
    _ = platform; // we dont care, install everywhere
    const luaState = session.*.luaState;
    
    // WARNING the luac API will push and pop 
    // values in ways that are not self evident
    // read the documentation for luac functions before use
    
    while (true) { //here for its ability to break;
        std.debug.assert(luaState.getTop() == 1); //stack should be empty here
        
        //BEGIN install internal table
        luaState.pushLightUserdata( &eventTablePointer ); // push `testForK`
        _ = luaState.getTable( ziglua.registry_index ); // push `testForV` pop `testForK`
        const isNil = luaState.isNil(-1);
        luaState.pop(-1); //pop `testForV`
        if( isNil ) {
            luaState.pushLightUserdata( &eventTablePointer ); // push `k`
            luaState.newTable(); // push `v`
            luaState.setTable( ziglua.registry_index ); //pops `k` and `v`
        } else {
            break;
        }
        //END install internal table
        
        std.debug.assert(luaState.getTop() == 1); //stack should be empty here
        
        //BEGIN add functions to library
        luaState.newTable(); // `lib`
        
        session.addNamedFunctionToTable("helloWorld",libFunctions.helloWorld);
        
        luaState.setGlobal("events"); //pops `lib`
        //END add functions to library
        
        std.debug.assert(luaState.getTop() == 1); //stack should be empty here
        break; //finished install
    }
}