const server = @import("root").server;
const std = @import("std");
const ziglua = @import("root").ziglua;
const LuaSession = @import("root").luasession.LuaSession;
const Userdata = @import("root").luasession.Userdata;
const command = @import("../command/_command.zig");
const LuaState = ziglua.Lua;


pub var commandsTablePointer: Userdata = .None;

const libFunctions = struct {
	fn broadcast(luaState: *LuaState) i32 {
		const usageString = "usage: chat.broadcast(messageString)";
		const message = luaState.toString(1) catch {
			_ = luaState.pushBoolean(false);
			_ = luaState.pushString(usageString);
			return 2;
		};
		// _ = l.pushString("hello, world!");
		server.sendMessage(message);
		_ = luaState.pushBoolean(true);
		return 1;
	}
	fn regCommand(luaState: *LuaState) i32 {
		//HACK allowing overriting bind, cannot safely register twice
		// args: name [1], function [2]
		if ( luaState.isNil(2) ) {
			std.log.warn("failed get function: {s}\n", .{luaState.toString(-1) catch unreachable});
			@panic("lua fail"); //HACK sloppy handling
		}
		const name = luaState.toString(1) catch {
			std.log.warn("failed get name: {s}\n", .{luaState.toString(-1) catch unreachable});
			@panic("lua fail"); //HACK sloppy handling
		};
		luaState.pushLightUserdata( &commandsTablePointer ); // push `testForK`
		_ = luaState.getTable( ziglua.registry_index ); // push `testForV` pop `testForK`
		//TODO add checking here
		_ = luaState.pushString(name);
		luaState.pushValue( 2 );
		luaState.setTable( -3 ); //pop name string and

		//slopply clear the stack HACK
		luaState.pop( -1 );
		luaState.pop( -1 );
		luaState.pop( -1 );

		_ = command.commands.put(name,.{
			.name = name,
			.description = "lua added this",
			.usage = "I really dont know",
			.commandType = .{ .lua = true },
		}) catch {
			@panic("lua fail: insert command"); //HACK sloppy handling
		};
		return 0;
	}
};

pub fn install() anyerror!void {
	var luaSession = server.luaSession;
	var luaState = luaSession.?.luaState.?;

	if (commandsTablePointer == .None){
		// use this as a variable to satisfy compiler
		commandsTablePointer = .Unique;
	}

	luaState.newTable(); // `t`

	luaSession.?.addNamedFunctionToTable("broadcast",libFunctions.broadcast);
	luaSession.?.addNamedFunctionToTable("registerCommand",libFunctions.regCommand);

	luaState.setGlobal("chat"); // pop `t`
	std.debug.assert(luaState.getTop() == 1); //stack should be empty here

	//TODO replace this boilerplate with either a function or a simpler version
	while (true) { //here for its ability to break;
		luaState.pushLightUserdata( &commandsTablePointer ); // push `testForK`
		_ = luaState.getTable( ziglua.registry_index ); // push `testForV` pop `testForK`
		const isNil = luaState.isNil(-1);
		luaState.pop(-1); //pop `testForV`
		if( isNil ) {
			luaState.pushLightUserdata( &commandsTablePointer ); // push `k`
			luaState.newTable(); // push `v`
			luaState.setTable( ziglua.registry_index ); //pops `k` and `v`
		} else {
			break;
		}
	}
}