const std = @import("std");

const main = @import("root");
const User = main.server.User;
const luaSession = &main.server.luaSession;
const chat = @import("../luaLibraries/_index.zig").chat;
const ziglua = main.ziglua;
//TODO decide if needed const luaState = main.ziglua.Lua;

pub const ZigCommandType = struct {
	exec: *const fn(args: []const u8, source: *User) void,
};


pub const CommandType = enum { zig,lua };

pub const CommandData = union(CommandType) {
	zig: ZigCommandType,
	lua: bool
};


pub const Command = struct {
	name: []const u8,
	description: []const u8,
	usage: []const u8,
	commandType: CommandData,
};

pub var commands: std.StringHashMap(Command) = undefined;

pub fn init() void {
	commands = std.StringHashMap(Command).init(main.globalAllocator.allocator);
	const commandList = @import("_list.zig");
	inline for(@typeInfo(commandList).Struct.decls) |decl| {
		commands.put(decl.name, Command{
			.name = decl.name,
			.description = @field(commandList, decl.name).description,
			.usage = @field(commandList, decl.name).usage,
			.commandType = .{ .zig = .{
				.exec = &@field(commandList, decl.name).execute
			} }
		}) catch unreachable;
	}
}

pub fn deinit() void {
	commands.deinit();
}

pub fn execute(msg: []const u8, source: *User) void {
	const end = std.mem.indexOfScalar(u8, msg, ' ') orelse msg.len;
	const command = msg[0..end];
	if(commands.get(command)) |cmd| {
		const result = std.fmt.allocPrint(main.stackAllocator.allocator, "#00ff00Executing Command /{s}", .{msg}) catch unreachable;
		defer main.stackAllocator.free(result);
		source.sendMessage(result);
		switch(cmd.commandType){
			.zig => |exe| {
				exe.exec(msg[@min(end + 1, msg.len)..], source);
			},
			.lua => |exe| {
				const lua = luaSession.*.?.luaState.?;
				lua.pushLightUserdata( &chat.commandsTablePointer );
				_ = lua.getTable( ziglua.registry_index );
				_ = lua.pushString( command );
				_ = lua.getTable( -2 ); //TODO figure out how wo handle type enum here


				_ = lua.pushString( msg[@min(end + 1, msg.len)..] ); //pushed the substring
				lua.pushInteger( source.id ); //TODO HACK: replace with a new uuid scheme

				// pops 2 inputs (+callee), pushes 0 results, 0 = msg_handler disabled?
				lua.protectedCall( 2, 0, 0 ) catch {
					// if failed
					std.log.warn("failed to call this thingy: {s}\n", .{lua.toString(-1) catch unreachable});
					// Remove the error from the stack and go back to the prompt
					lua.pop(1);
					@panic("failed to call the thingy"); //TODO HACK moving to better error infrastructure
				};
				_ = exe;
				//lua.getTable()
				//command
			}
		}
	} else {
		const result = std.fmt.allocPrint(main.stackAllocator.allocator, "#ff0000Unrecognized Command \"{s}\"", .{command}) catch unreachable;
		defer main.stackAllocator.free(result);
		source.sendMessage(result);
	}
}