const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("root");
const blocks = main.blocks;
const chunk = main.chunk;
const chunk_meshing = @import("chunk_meshing.zig");
const mesh_storage = @import("mesh_storage.zig");

const Channel = enum(u8) {
	sun_red = 0,
	sun_green = 1,
	sun_blue = 2,
	red = 3,
	green = 4,
	blue = 5,

	pub fn shift(self: Channel) u5 {
		switch(self) {
			.red, .sun_red => return 16,
			.green, .sun_green => return 8,
			.blue, .sun_blue => return 0,
		}
	}

	pub fn isSun(self: Channel) bool {
		switch(self) {
			.sun_red, .sun_green, .sun_blue => return true,
			.red, .green, .blue => return false,
		}
	}
};

pub const ChannelChunk = struct {
	data: [chunk.chunkVolume]Atomic(u8),
	mutex: std.Thread.Mutex,
	ch: *chunk.Chunk,
	channel: Channel,

	pub fn init(self: *ChannelChunk, ch: *chunk.Chunk, channel: Channel) !void {
		self.mutex = .{};
		self.ch = ch;
		self.channel = channel;
		@memset(&self.data, Atomic(u8).init(0));
	}

	const Entry = struct {
		x: u5,
		y: u5,
		z: u5,
		value: u8,
	};

	const PositionEntry = struct {
		x: u5,
		y: u5,
		z: u5,
	};

	const ChunkEntries = struct {
		mesh: ?*chunk_meshing.ChunkMesh,
		entries: std.ArrayListUnmanaged(PositionEntry),
	};

	fn propagateDirect(self: *ChannelChunk, lightQueue: *main.utils.CircularBufferQueue(Entry)) std.mem.Allocator.Error!void {
		var neighborLists: [6]std.ArrayListUnmanaged(Entry) = .{.{}} ** 6;
		defer {
			for(&neighborLists) |*list| {
				list.deinit(main.globalAllocator);
			}
		}

		self.mutex.lock();
		errdefer self.mutex.unlock();
		while(lightQueue.dequeue()) |entry| {
			const index = chunk.getIndex(entry.x, entry.y, entry.z);
			if(entry.value <= self.data[index].load(.Unordered)) continue;
			self.data[index].store(entry.value, .Unordered);
			for(chunk.Neighbors.iterable) |neighbor| {
				const nx = entry.x + chunk.Neighbors.relX[neighbor];
				const ny = entry.y + chunk.Neighbors.relY[neighbor];
				const nz = entry.z + chunk.Neighbors.relZ[neighbor];
				var result: Entry = .{.x = @intCast(nx & chunk.chunkMask), .y = @intCast(ny & chunk.chunkMask), .z = @intCast(nz & chunk.chunkMask), .value = entry.value};
				if(!self.channel.isSun() or neighbor != chunk.Neighbors.dirDown or result.value != 255) {
					result.value -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
				}
				if(result.value == 0) continue;
				if(nx < 0 or nx >= chunk.chunkSize or ny < 0 or ny >= chunk.chunkSize or nz < 0 or nz >= chunk.chunkSize) {
					try neighborLists[neighbor].append(main.globalAllocator, result);
					continue;
				}
				const neighborIndex = chunk.getIndex(nx, ny, nz);
				var absorption: u8 = @intCast(self.ch.blocks[neighborIndex].absorption() >> self.channel.shift() & 255);
				absorption *|= @intCast(self.ch.pos.voxelSize);
				result.value -|= absorption;
				if(result.value != 0) try lightQueue.enqueue(result);
			}
		}
		self.mutex.unlock();
		if(mesh_storage.getMeshAndIncreaseRefCount(self.ch.pos)) |mesh| {
			try mesh.scheduleLightRefreshAndDecreaseRefCount();
		}

		for(0..6) |neighbor| {
			if(neighborLists[neighbor].items.len == 0) continue;
			const neighborMesh = mesh_storage.getNeighborAndIncreaseRefCount(self.ch.pos, self.ch.pos.voxelSize, @intCast(neighbor)) orelse continue;
			defer neighborMesh.decreaseRefCount();
			try neighborMesh.lightingData[@intFromEnum(self.channel)].propagateFromNeighbor(neighborLists[neighbor].items);
		}
	}

	fn propagateDestructive(self: *ChannelChunk, lightQueue: *main.utils.CircularBufferQueue(Entry), constructiveEntries: *std.ArrayListUnmanaged(ChunkEntries), isFirstBlock: bool) std.mem.Allocator.Error!std.ArrayListUnmanaged(PositionEntry) {
		var neighborLists: [6]std.ArrayListUnmanaged(Entry) = .{.{}} ** 6;
		var constructiveList: std.ArrayListUnmanaged(PositionEntry) = .{};
		defer {
			for(&neighborLists) |*list| {
				list.deinit(main.globalAllocator);
			}
		}
		var isFirstIteration: bool = isFirstBlock;

		self.mutex.lock();
		errdefer self.mutex.unlock();
		while(lightQueue.dequeue()) |entry| {
			const index = chunk.getIndex(entry.x, entry.y, entry.z);
			if(entry.value != self.data[index].load(.Unordered)) {
				if(self.data[index].load(.Unordered) != 0) {
					try constructiveList.append(main.globalAllocator, .{.x = entry.x, .y = entry.y, .z = entry.z});
				}
				continue;
			}
			if(entry.value == 0 and !isFirstIteration) continue;
			isFirstIteration = false;
			self.data[index].store(0, .Unordered);
			for(chunk.Neighbors.iterable) |neighbor| {
				const nx = entry.x + chunk.Neighbors.relX[neighbor];
				const ny = entry.y + chunk.Neighbors.relY[neighbor];
				const nz = entry.z + chunk.Neighbors.relZ[neighbor];
				var result: Entry = .{.x = @intCast(nx & chunk.chunkMask), .y = @intCast(ny & chunk.chunkMask), .z = @intCast(nz & chunk.chunkMask), .value = entry.value};
				if(!self.channel.isSun() or neighbor != chunk.Neighbors.dirDown or result.value != 255) {
					result.value -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
				}
				if(nx < 0 or nx >= chunk.chunkSize or ny < 0 or ny >= chunk.chunkSize or nz < 0 or nz >= chunk.chunkSize) {
					try neighborLists[neighbor].append(main.globalAllocator, result);
					continue;
				}
				const neighborIndex = chunk.getIndex(nx, ny, nz);
				var absorption: u8 = @intCast(self.ch.blocks[neighborIndex].absorption() >> self.channel.shift() & 255);
				absorption *|= @intCast(self.ch.pos.voxelSize);
				result.value -|= absorption;
				try lightQueue.enqueue(result);
			}
		}
		self.mutex.unlock();
		if(mesh_storage.getMeshAndIncreaseRefCount(self.ch.pos)) |mesh| {
			try mesh.scheduleLightRefreshAndDecreaseRefCount();
		}

		for(0..6) |neighbor| {
			if(neighborLists[neighbor].items.len == 0) continue;
			const neighborMesh = mesh_storage.getNeighborAndIncreaseRefCount(self.ch.pos, self.ch.pos.voxelSize, @intCast(neighbor)) orelse continue;
			try constructiveEntries.append(main.globalAllocator, .{
				.mesh = neighborMesh,
				.entries = try neighborMesh.lightingData[@intFromEnum(self.channel)].propagateDestructiveFromNeighbor(neighborLists[neighbor].items, constructiveEntries),
			});
		}

		return constructiveList;
	}

	fn propagateFromNeighbor(self: *ChannelChunk, lights: []const Entry) std.mem.Allocator.Error!void {
		var lightQueue = try main.utils.CircularBufferQueue(Entry).init(main.globalAllocator, 1 << 8);
		defer lightQueue.deinit();
		for(lights) |entry| {
			const index = chunk.getIndex(entry.x, entry.y, entry.z);
			var result = entry;
			var absorption: u8 = @intCast(self.ch.blocks[index].absorption() >> self.channel.shift() & 255);
			absorption *|= @intCast(self.ch.pos.voxelSize);
			result.value -|= absorption;
			if(result.value != 0) try lightQueue.enqueue(result);
		}
		try self.propagateDirect(&lightQueue);
	}

	fn propagateDestructiveFromNeighbor(self: *ChannelChunk, lights: []const Entry, constructiveEntries: *std.ArrayListUnmanaged(ChunkEntries)) std.mem.Allocator.Error!std.ArrayListUnmanaged(PositionEntry) {
		var lightQueue = try main.utils.CircularBufferQueue(Entry).init(main.globalAllocator, 1 << 8);
		defer lightQueue.deinit();
		for(lights) |entry| {
			const index = chunk.getIndex(entry.x, entry.y, entry.z);
			var result = entry;
			var absorption: u8 = @intCast(self.ch.blocks[index].absorption() >> self.channel.shift() & 255);
			absorption *|= @intCast(self.ch.pos.voxelSize);
			result.value -|= absorption;
			try lightQueue.enqueue(result);
		}
		return try self.propagateDestructive(&lightQueue, constructiveEntries, false);
	}

	pub fn propagateLights(self: *ChannelChunk, lights: []const [3]u8, comptime checkNeighbors: bool) std.mem.Allocator.Error!void {
		var lightQueue = try main.utils.CircularBufferQueue(Entry).init(main.globalAllocator, 1 << 8);
		defer lightQueue.deinit();
		for(lights) |pos| {
			const index = chunk.getIndex(pos[0], pos[1], pos[2]);
			if(self.channel.isSun()) {
				try lightQueue.enqueue(.{.x = @intCast(pos[0]), .y = @intCast(pos[1]), .z = @intCast(pos[2]), .value = 255});
			} else {
				try lightQueue.enqueue(.{.x = @intCast(pos[0]), .y = @intCast(pos[1]), .z = @intCast(pos[2]), .value = @intCast(self.ch.blocks[index].light() >> self.channel.shift() & 255)});
			}
		}
		if(checkNeighbors) {
			for(0..6) |neighbor| {
				const x3: i32 = if(neighbor & 1 == 0) chunk.chunkMask else 0;
				var x1: i32 = 0;
				while(x1 < chunk.chunkSize): (x1 += 1) {
					var x2: i32 = 0;
					while(x2 < chunk.chunkSize): (x2 += 1) {
						var x: i32 = undefined;
						var y: i32 = undefined;
						var z: i32 = undefined;
						if(chunk.Neighbors.relX[neighbor] != 0) {
							x = x3;
							y = x1;
							z = x2;
						} else if(chunk.Neighbors.relY[neighbor] != 0) {
							x = x1;
							y = x3;
							z = x2;
						} else {
							x = x2;
							y = x1;
							z = x3;
						}
						const otherX = x+%chunk.Neighbors.relX[neighbor] & chunk.chunkMask;
						const otherY = y+%chunk.Neighbors.relY[neighbor] & chunk.chunkMask;
						const otherZ = z+%chunk.Neighbors.relZ[neighbor] & chunk.chunkMask;
						const neighborMesh = mesh_storage.getNeighborAndIncreaseRefCount(self.ch.pos, self.ch.pos.voxelSize, @intCast(neighbor)) orelse continue;
						defer neighborMesh.decreaseRefCount();
						const neighborLightChunk = &neighborMesh.lightingData[@intFromEnum(self.channel)];
						const index = chunk.getIndex(x, y, z);
						const neighborIndex = chunk.getIndex(otherX, otherY, otherZ);
						var value: u8 = neighborLightChunk.data[neighborIndex].load(.Unordered);
						if(!self.channel.isSun() or neighbor != chunk.Neighbors.dirUp or value != 255) {
							value -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
						}
						if(value == 0) continue;
						var absorption: u8 = @intCast(self.ch.blocks[index].absorption() >> self.channel.shift() & 255);
						absorption *|= @intCast(self.ch.pos.voxelSize);
						value -|= absorption;
						if(value != 0) try lightQueue.enqueue(.{.x = @intCast(x), .y = @intCast(y), .z = @intCast(z), .value = value});
					}
				}
			}
		}
		try self.propagateDirect(&lightQueue);
	}

	pub fn propagateLightsDestructive(self: *ChannelChunk, lights: []const [3]u8) std.mem.Allocator.Error!void {
		var lightQueue = try main.utils.CircularBufferQueue(Entry).init(main.globalAllocator, 1 << 8);
		defer lightQueue.deinit();
		for(lights) |pos| {
			const index = chunk.getIndex(pos[0], pos[1], pos[2]);
			try lightQueue.enqueue(.{.x = @intCast(pos[0]), .y = @intCast(pos[1]), .z = @intCast(pos[2]), .value = self.data[index].load(.Unordered)});
		}
		var constructiveEntries: std.ArrayListUnmanaged(ChunkEntries) = .{};
		defer constructiveEntries.deinit(main.globalAllocator);
		try constructiveEntries.append(main.globalAllocator, .{
			.mesh = null,
			.entries = try self.propagateDestructive(&lightQueue, &constructiveEntries, true),
		});
		for(constructiveEntries.items) |entries| {
			const mesh = entries.mesh;
			defer if(mesh) |_mesh| _mesh.decreaseRefCount();
			var entryList = entries.entries;
			defer entryList.deinit(main.globalAllocator);
			const channelChunk = if(mesh) |_mesh| &_mesh.lightingData[@intFromEnum(self.channel)] else self;
			for(entryList.items) |entry| {
				const index = chunk.getIndex(entry.x, entry.y, entry.z);
				const value = channelChunk.data[index].load(.Unordered);
				if(value == 0) continue;
				channelChunk.data[index].store(0, .Unordered);
				try lightQueue.enqueue(.{.x = entry.x, .y = entry.y, .z = entry.z, .value = value});
			}
			try channelChunk.propagateDirect(&lightQueue);
		}
	}
};