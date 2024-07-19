const main = @import("root");
const std = @import("std");
const ziglua = main.ziglua;
const LuaState = ziglua.Lua;
const Thread = std.Thread;
const session = @import("session.zig");
const LuaSession = session.LuaSession;
const Error = session.Error;
const Userdata = session.Userdata;
const Channel = @import("channel.zig").Channel;

const luaEvent = @import("event.zig");
const Event = luaEvent.Event;
const EventHandler = luaEvent.EventHandler;
const EventBody = luaEvent.EventBody;
const EventBodyKind = luaEvent.EventBodyKind;

pub const LuaSessionService = struct {
    resolversTable: Userdata,
    luaAnonTable: Userdata, //store for fast moving anonymous zig pointer to lua data
    luaState: *LuaState,
    //TODO TEST
    pub fn giveToAnonTable(self: *LuaSessionService,key: *Userdata, index: usize) !void {
        self.*.luaState.pushLightUserdata( &self.*.service.luaAnonTable ); //push `k`
        _ = self.*.luaState.getTable( ziglua.registry_index ); //pop `k` push `t`
        if( self.*.luaState.isNil( -1 ) ) {
            _ = self.*.luaState.pop( -1 ); // pop `t`
            return Error.LuaCorruptedError;
        }
        self.*.luaState.pushLightUserdata( key ); //push `k`
        if (index < 0) {
            index -= 2;
        } else {
            index += 2;
        }
        self.*.luaState.pushValue( index ); //push `data`
        _ = self.*.luaState.setTable( -1 ); //pop `k` and `data`
        _ = self.*.luaState.pop( -1 ); // pop `t`
    }
    //TODO TEST
    pub fn takeFromAnonTable(self: *LuaSessionService,key: *Userdata,andDelete: bool) !void {
        self.*.luaState.pushLightUserdata( &self.*.service.luaAnonTable ); // stack: `k`
        _ = self.*.luaState.getTable( ziglua.registry_index ); // stack: `t`
        if( self.*.luaState.isNil( -1 ) ) {
            _ = self.*.luaState.pop( -1 ); // stack: *empty*
            return Error.LuaCorruptedError;
        }
        self.*.luaState.pushLightUserdata( key ); //stack: `t,k`
        _ = self.*.luaState.pushValue( -1 ); //stack: `t,k,kClone`

        _ = self.*.luaState.getTable( -3 ); //with `t` stack: `t,k,result`
        if (andDelete) {
            _ = self.*.luaState.pushValue( -2 ); //from `k` stack: `t,k,result,kClone`
            self.*.luaState.pushNil(); //stack: `t,k,result,kClone,nil`
            _ = self.*.luaState.setTable( -5 ); //with `t` stack: `t,k,result`
        }

        self.*.luaState.replace( -2 ); // replace `t` with `result`, stack: `result,k`
        _ = self.*.luaState.pop( -1 ); // stack: `result`
    }
    pub fn init(self: *LuaSessionService,parent: *LuaSession) !void {
        _ = try Thread.spawn(.{},outer,.{self,parent}); //TEMP handle thread
    }
};

fn outer(self: *LuaSessionService,parent: *LuaSession) void {
    std.log.debug("lua service: spawned",.{});
    threadCode(self,parent) catch |e| {
        std.log.err("lua service: error: {}",.{e});
        @panic("error in lua thread");
    };
}

fn teardown(self: *LuaSession,luaState: *LuaState) !void {
    //TODO
    _ = self;
    _ = luaState;
}

fn runTheContextlessInitFile(self: *LuaSession,luaState: *LuaState) void{
    _ = self;
    //HACK sloppy error handling TEMP bevavor
    luaState.loadFile("server_init_contextless.lua",.text) catch {
        std.log.warn("lua service: no contextless init file",.{});
        return;
    };
    luaState.protectedCall(0,0,0) catch {
        // if failed
        std.log.warn("server init: Contextless init file had an error, skipped it: {s}\n", .{luaState.toString(-1) catch unreachable});
        // Remove the error from the stack and go back to the prompt
        luaState.pop(1);
        return;
    };
}

fn setup(self: *LuaSession,luaState: *LuaState) !void {
    luaState.openLibs();

    std.debug.assert(luaState.getTop() == 1); //stack should be empty here
    //BEGIN event handler registry
    luaState.*.pushLightUserdata( &self.*.service.resolversTable ); //push `k`
    luaState.newTable(); // push `v`
    luaState.setTable( ziglua.registry_index ); //pop `k` and `v`
    //END event handler registry
    //BEGIN anon data registry
    luaState.*.pushLightUserdata( &self.*.service.luaAnonTable ); //push `k`
    luaState.newTable(); // push `v`
    luaState.setTable( ziglua.registry_index ); //pop `k` and `v`
    //END anon data registry
    runTheContextlessInitFile(self,luaState);
}


fn threadCode(self: *LuaSessionService, luaSession: *LuaSession) !void {
    // Create an allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Initialize the Lua vm
    var lua = try LuaState.init(&allocator);
    defer lua.deinit();
    self.*.luaState = lua;

    try setup(luaSession,lua);

    var message: ?Event = null;
    var blockingRecev = false;
    blockingRecev = true; //HACK, it should be variable but has no mutators yet
    std.log.info("lua service: ready to take events",.{});
    while (true) {
        if (blockingRecev){
            message = luaSession.*.channel.recev();
        } else {
            message = luaSession.*.channel.recev_nb();
        }

        if (message == null) continue;

        const messageKindID: u8 = @intFromEnum(@as(EventBodyKind,message.?.body));
        std.log.debug("event({}): {}",.{messageKindID,message.?});
        //message.?.exec(&message.?,self);
        luaSession.handlers.lock.lock();
        const handler = luaSession.handlers.data[messageKindID];
        luaSession.handlers.lock.unlock();
        if(handler == null) {
            std.log.err("lua service: event has no handler({}): {}",.{messageKindID,message.?});
        } else {
            handler.?(&message.?,luaSession);
        }
        if (message.?.deinit != null) {
            message.?.deinit.?(&message.?,luaSession);
        }
    }

    try teardown(luaSession,lua);

}
