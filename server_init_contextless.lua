-- server_init_contextless
--
-- this file executed if it exists.
-- it runs BEFORE lua's standard library is modified and without the fancy loader.
-- therefore it lacks the APIs and runs on the baseline _G object.
-- it is mainly here for debugging.


print(debug);
