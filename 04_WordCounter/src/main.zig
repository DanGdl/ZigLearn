const std = @import("std");
const ascii = @import("std").ascii;

pub fn main() !void {
    // use arena allocator to allocate keys gor hashmap
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer _ = arena.deinit();
    const allocator = arena.allocator();

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.log.err(
            \\First argument must be a path to file to read:
            \\./zig-out/bin/04_WordCounter ./testfile.txt
        , .{});
        return;
    }
    const path_source = args[1];
    const f_source = std.fs.cwd().openFile(path_source, .{
        .mode = std.fs.File.OpenMode.read_only,
    }) catch |err| {
        std.log.err("Failed to open file {s}: {}\n", .{ path_source, err });
        return;
    };
    defer f_source.close();

    const st_source = std.fs.File.stat(f_source) catch |err| {
        std.log.err("Failed to stat file {s}: {}\n", .{ path_source, err });
        return;
    };
    const mapped = std.posix.mmap(
        null,
        st_source.size,
        std.posix.PROT.READ,
        .{ .TYPE = .SHARED },
        f_source.handle,
        0,
    ) catch |err| {
        std.log.err("Failed to mmap file {s}: {}\n", .{ path_source, err });
        return;
    };
    defer std.posix.munmap(mapped);

    var map = std.StringHashMap(u32).init(allocator);
    defer map.deinit();

    var idx_start: u64 = 0;
    for (0..st_source.size) |idx| {
        if (ascii.isWhitespace(mapped[idx]) or !ascii.isAlphanumeric(mapped[idx])) {
            const idx_end: u64 = idx;
            if (idx_end <= idx_start) {
                idx_start = idx_end + 1;
                continue;
            }

            var count = map.get(mapped[idx_start..idx_end]) orelse 0;
            count += 1;
            const key = switch (count) {
                1 => blk: {
                    const key_tmp = allocator.alloc(u8, idx_end - idx_start) catch |err| {
                        std.log.err("Failed to allocate memory: {}\n", .{err});
                        return;
                    };
                    @memcpy(key_tmp, mapped[idx_start..idx_end]);
                    break :blk key_tmp;
                },
                else => mapped[idx_start..idx_end],
            };

            map.put(key, count) catch |err| {
                std.log.err("Failed to put key-value to map: {}\n", .{err});
                return;
            };
            // std.debug.print("Word: {s}\n", .{mapped[idx_start..idx_end]});
            idx_start = idx_end + 1;
        }
    }

    var keys = map.keyIterator();
    while (keys.next()) |key| {
        try stdout.print("{s}: {}\n", .{ key.*, map.get(key.*) orelse 0 });
    }
    try bw.flush();
}
