const main = @import("root");
const std = @import("std");
const ziglua = main.ziglua;
const LuaState = ziglua.Lua;
const modList = @import("libraries/_index.zig");
const Thread = std.Thread;
const Channel = @import("channel.zig").Channel;

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
	None, // an "empty" userdata
	Unique, // a strictly unique userdata
	//WIP
};

pub const EventData = union(enum) {
	vec: [3]usize,
	string: []u8,
	int_usize: usize,
	custom: *anyopaque
	custom_sized: struct {
		data: *anyopaque,
		size: usize,
	},

}

//NOTE the corrent implementation of Event is subject to change
pub const EventHandler = fn (event: *Event, lua: *LuaSession) void;
pub const Event = struct {
	exec: *const EventHandler,
	data: []EventData,
};

pub const LuaSession = struct {
	initialized: bool = false,
	eventSystem: bool = false, //represents initialized check and anyopaque table key
	channel: Channel(Event) = undefined,


	luaState: ?*LuaState = null,

	pub fn init(self: *LuaSession, luaState: *LuaState) anyerror!void {
		std.debug.assert(self.*.initialized == false);
		self.*.initialized = true;
		self.*.luaState = luaState;
		const eventsPage = main.globalAllocator.create([100]Event);
		self.*.channel.init(eventsPage);
		const message = "hello other side!";


		self.*.channel.send(.{ .exec = &testBind, .data = @ptrCast(@constCast(message)), .data_len = message.len });

		_ = try Thread.spawn(.{},serviceThreadCode,.{self}); //TEMP handle thread
	}

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

	pub fn addNamedFunctionToTable(self: *LuaSession, name: []const u8, func: ziglua.ZigFn) void {
		const luaState = self.*.luaState.?;
		_ = luaState.pushString(name); //push `k`
		luaState.pushFunction(ziglua.wrap(func)); // push `v`
		//applies to whatever is on the top of the stack
		luaState.setTable( -3 ); //pops `k` and `v`
	}
};

fn serviceOuter(self: *LuaSession) void {
	serviceThreadCode(self) catch |e| {
		std.log.err("lua error: {}",.{@typeName(e)});
		@panic("error in lua thread");
	};
}

fn serviceThreadCode(self: *LuaSession) !void {
	// Create an allocator
	var gpa = std.heap.GeneralPurposeAllocator(.{}){};
	const allocator = gpa.allocator();
	defer _ = gpa.deinit();

	// Initialize the Lua vm
	var lua = try LuaState.init(&allocator);
	defer lua.deinit();

	// Add an integer to the Lua stack and retrieve it
	lua.pushInteger(42);
	std.debug.print("Hi over there! {}\n", .{try lua.toInteger(1)});

	var message: ?Event = null;
	var blockingRecev = false;
	blockingRecev = true; //HACK, it should be variable but has no mutators yet

	while (true) {
		if (blockingRecev){
			message = self.*.channel.recev();
		} else {
			message = self.*.channel.recev_nb();
		}

		// std.log.debug("{?}",.{message});
		if (message != null) {
			message.?.exec(&message.?,self);
		}


	}
}


fn testBind(event: *Event, lua: *LuaSession) void{
	std.log.debug("sided: {s}",.{ @as([]const u8,@as([*]u8, @ptrCast(event.data))[0..event.data_len]) });
	_ = lua;
}




