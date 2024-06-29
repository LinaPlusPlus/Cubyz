const server = @import("root").server;
const std = @import("std");
const ziglua = @import("root").ziglua;
const LuaSession = @import("root").luasession.LuaSession;
const LuaState = ziglua.Lua;

const libFunctions = struct {
	fn broadcast(luaState: *LuaState) i32 {
		const usageString = "usage: chat.broadcast(messageString)";
		const message = luaState.toString(-1) catch {
			_ = luaState.pushBoolean(false);
			_ = luaState.pushString(usageString);
			return 2;
		};
		// _ = l.pushString("hello, world!");
		server.sendMessage(message);
		_ = luaState.pushBoolean(true);
		return 1;
	}
};

pub fn install() anyerror!void {
	var luaSession = server.getLuaSession();
	var luaState = luaSession.getLua();

	luaState.newTable(); // `t`

	luaSession.addNamedFunctionToTable("broadcast",libFunctions.broadcast);

	luaState.setGlobal("chat"); // pop `t`
	std.debug.assert(luaState.getTop() == 1); //stack should be empty here
}