const main = @import("root");
const std = @import("std");
const ziglua = main.ziglua;
const LuaState = ziglua.Lua;
const modList = @import("libraries/_index.zig");
const Channel = @import("channel.zig").Channel;
const LuaSessionService = @import("service.zig").LuaSessionService;

const luaEvent = @import("event.zig");
const Event = luaEvent.Event;
const EventHandler = luaEvent.EventHandler;
const EventBody = luaEvent.EventBody;

const modLength = @typeInfo(modList).Struct.decls.len;

pub const Error = error {
	DoubleInit,
	DoubleDeinit, //or not inited
	Error,
	IOError,
	LuaCorruptedError,
};

//TODO dead code?
pub const Platform = enum {
	Server,
	Client,
};

pub const Userdata = union(enum) {
	None, // an "empty" userdata
	Unique, // a strictly unique (pointer) userdata
	//WIP
};


fn testDeinit(event: *Event, lua: *LuaSession) void {
	_ = event;
	_ = lua;
	std.log.debug("an event object deinited correctly",.{});
}

pub const LuaSession = struct {
	initialized: bool = false,
	wasInitialized: bool = false,
	channel: Channel(Event) = undefined,
	service: LuaSessionService = .{
		.luaState = undefined,
		.resolversTable = .Unique,
		.luaAnonTable = .Unique,
		//TODO add stuff here
	},
	luaState: ?*LuaState = null, //OLD

	pub fn init(self: *LuaSession, luaState: *LuaState) anyerror!void {
		std.debug.assert(self.*.initialized == false);
		self.*.initialized = true;
		self.*.luaState = luaState;
		const eventsPage = main.globalAllocator.create([100]Event);
		self.*.channel.init(eventsPage);

		self.*.channel.send(.{
			.deinit = testDeinit,
			.body = .{ .initialize_service = .{} },
		});
	}

	//OLD
	pub fn installCommonSystems(self: *LuaSession, targetPlatform: Platform) anyerror!void {
		std.debug.assert(self.*.initialized == true);
		const luaState = self.*.luaState.?;
		std.log.info("install lua library: std",.{});
		luaState.openLibs();

		inline for(@typeInfo(modList).Struct.decls) |decl| {
			std.log.info("install lua library: {s}",.{decl.name});
			_ = try @field(modList, decl.name).install(self,targetPlatform);
		}
	}

	//OLD
	//TODO HACK file string is a const, change to *string or zig equivlant
	//TODO from server.init(...) inline into function;
	pub fn loadContextlessFile(self: *LuaSession) anyerror!void {
		std.debug.assert(self.*.initialized == true);
		const luaState = self.*.luaState orelse unreachable;

		std.debug.assert(self.*.initialized == true);
		try luaState.loadFile("server_init_contextless.lua",.text);
		// 0 inputs 0, returns, index of 0 for some reason
		// argument 3 is `0` in this simmlar function, blindly cloning
		// https://github.com/natecraddock/ziglua/blob/a7cf85fb871a95a46d4222fe3abdd3946e3e0dab/src/lib.zig#L2521
		try luaState.protectedCall(0,0,0);
	}

	//OLD
	pub fn addNamedFunctionToTable(self: *LuaSession, name: []const u8, func: ziglua.ZigFn) void {
		const luaState = self.*.luaState.?;
		_ = luaState.pushString(name); //push `k`
		luaState.pushFunction(ziglua.wrap(func)); // push `v`
		//applies to whatever is on the top of the stack
		luaState.setTable( -3 ); //pops `k` and `v`
	}
};







