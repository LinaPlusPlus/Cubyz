// borrowed from here
// https://medium.com/@fwx5618177/zig-concurrency-implementation-methods-69bc31c14c56
// ---

const std = @import("std");
const Thread = std.Thread;
const Event = std.event;
// const Channel = Event.Channel; // TODO: After Publish Async to make this work
const Mutex = Thread.Mutex;
const Condition = Thread.Condition;
const spawn = Thread.spawn;

const SelectOp = enum {
    Send,
    Recv,
};

const SelectCase = struct {
    op: SelectOp,
    channel: *Channel(i32),
    value: ?i32,
    is_ready: bool,
};

pub fn Channel(comptime T: type) type {
    return struct {
        mutex: Mutex,
        not_empty: Condition,
        not_full: Condition,
        buffer: []T,
        start: usize,
        end: usize,
        count: usize,
        closed: bool,
        select_cases: std.ArrayList(*SelectCase), // support select usage

        const Self = @This();

        pub fn init(self: *Self, buffer: []T) void {
            self.* = Self{
                .mutex = Mutex{},
                .not_empty = Condition{},
                .not_full = Condition{},
                .buffer = buffer,
                .start = 0,
                .end = 0,
                .count = 0,
                .closed = false,
                .select_cases = std.ArrayList(*SelectCase).init(std.heap.page_allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.not_empty.broadcast();
            self.not_full.broadcast();
            self.closed = true;
            self.buffer = undefined;
            self.start = 0;
            self.end = 0;
            self.count = 0;
        }

        pub fn send(self: *Self, item: T) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.count == self.buffer.len) {
                self.not_full.wait(&self.mutex);
            }

            self.buffer[self.end] = item;
            self.end = (self.end + 1) % self.buffer.len;
            self.count += 1;
            self.not_empty.signal();
        }

        pub fn recev(self: *Self) T {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.count == 0) {
                self.not_empty.wait(&self.mutex);
            }
            const item = self.buffer[self.start];
            self.start = (self.start + 1) % self.buffer.len;
            self.count -= 1;
            self.not_full.signal();

            return item;
        }

        pub fn send_nb(self: *Self, item: T) bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.count == self.buffer.len) {
                return false; // buffer is full
            }

            self.buffer[self.end] = item;
            self.end = (self.end + 1) % self.buffer.len;
            self.count += 1;
            self.not_empty.signal();

            return true;
        }

        pub fn recev_nb(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.count == 0) {
                return null; // buffer is empty
            }

            const item = self.buffer[self.start];
            self.start = (self.start + 1) % self.buffer.len;
            self.count -= 1;
            self.not_full.signal();

            return item;
        }

        pub fn registerSelectCase(self: *Self, case: *SelectCase) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            try self.select_cases.append(case);
        }

        pub fn trySelectOperation(self: *Self) bool {
            for (self.select_cases.items) |case| {
                switch (case.op) {
                    .Send => {
                        if (case.value != null and self.send_nb(case.value.?)) {
                            return true;
                        }
                    },
                    .Recv => {
                        if (self.recv_nb()) |item| {
                            case.value = item;
                            case.is_ready = true;

                            return true;
                        } else {
                            continue;
                        }
                    },
                }
            }

            return false;
        }
    };
}