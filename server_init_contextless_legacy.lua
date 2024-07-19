-- server_init_contextless
--
-- this file executed if it exists.
-- it runs on the baseline _G object.
-- it is mainly here for debugging.

print(events.helloWorld());

chat.registerCommand("hello",function (message,user)
    chat.broadcast(("hello, %s! (also %s)"):format(message,user))
end );


local fail,luaDoThis = nil,function(h) return h.."!" end;

chat.registerCommand("luar",function (message,user)
    luaDoThis,fail = load(message);
    if not luaDoThis then
        chat.broadcast(("#ff0000Failed: %s"):format(fail));
        luaDoThis = function(h) return "#ff0000Invalid lua" end;
    end
end);

chat.registerCommand("luax",function (a,b)
    chat.broadcast(tostring(luaDoThis(a) or "#707070no response..."));
end );