const std = @import("std");

// const SIGNATURE_START_OF_CENTRAL_RECORD = 0x02014B50;
const SIGNATURE_END_OF_CENTRAL_RECORD = 0x06054B50;
const SIGNATURE_START_OF_RECORD = 0x04034B50;

const OFFSET_CENTRAL_ENTRY_SIZE = 12; // offset from SIGNATURE_END_OF_CENTERAL_RECORD
const OFFSET_ENTRY_NAME_SIZE = 26; // offset from SIGNATURE_START_OF_RECORD
const OFFSET_ENTRY_NAME = 30; // offset from SIGNATURE_START_OF_RECORD

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // for (args, 0..) |arg, i| {
    //     std.debug.print("Arg {d}: {s}\n", .{ i, arg });
    // }

    if (args.len <= 1) {
        std.log.err("First argument must be a path to file for test\n", .{});
        return;
    }

    const path = args[1];
    const file = std.fs.cwd().openFile(path, .{
        .mode = std.fs.File.OpenMode.read_only,
    }) catch |err| {
        std.log.err("Failed to open file {s}: {}\n", .{ path, err });
        return;
    };
    defer file.close();

    const st = std.fs.File.stat(file) catch |err| {
        std.log.err("Failed to stat file {s}: {}\n", .{ path, err });
        return;
    };
    const mapped = std.posix.mmap(
        null,
        st.size,
        std.posix.PROT.READ,
        .{ .TYPE = .SHARED },
        file.handle,
        0,
    ) catch |err| {
        std.log.err("Failed to mmap file {s}: {}\n", .{ path, err });
        return;
    };
    defer std.posix.munmap(mapped);

    var current_entry: u16 = 0;
    var i: usize = st.size - 1;
    while (i >= 4) : (i -= 1) {
        const signature: u32 = @bitCast(mapped[i - 3 ..][0..4].*);
        // std.debug.print("signature 0x{X}\n", .{signature});
        if (SIGNATURE_END_OF_CENTRAL_RECORD == signature) {
            const central_dir_size: u32 = @bitCast(mapped[i - 3 + OFFSET_CENTRAL_ENTRY_SIZE ..][0..4].*);
            // jump to beginning of central entry
            i = i - central_dir_size + 1 - 3;
        } else if (SIGNATURE_START_OF_RECORD == signature) {
            i = i - 3;
            const name_size: u16 = @bitCast(mapped[i + OFFSET_ENTRY_NAME_SIZE ..][0..2].*);
            try stdout.print("Record {} name {s}\n", .{ current_entry, mapped[i - 1 + OFFSET_ENTRY_NAME .. i - 1 + OFFSET_ENTRY_NAME + name_size] });
            try bw.flush();
            current_entry += 1;
        }
    }
    if (0 == current_entry) {
        try stdout.print("File {s} doesn't contains zip archive\n", .{path});
        try bw.flush();
    }
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
