const Server = @import("../server.zig");
const std = @import("std");
const ziglua = @import("root").ziglua;
const luasession = @import("root").luasession;

pub fn install() anyerror!void {
    std.log.debug("server had the chat library load, you can remove this message",.{});
}