const std = @import("std");
const ascii = @import("std").ascii;
const unicode = @import("std").unicode;
const Allocator = std.mem.Allocator;
const Utf8View = unicode.Utf8View;

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    const stdin_file = std.io.getStdIn().reader();
    var br = std.io.bufferedReader(stdin_file);
    const stdin = br.reader();

    const allocator = std.heap.page_allocator;

    while (true) {
        var input = allocator.alloc(u8, 1) catch |err| {
            std.log.err("Failed to allocate memory: {}\n", .{err});
            return;
        };
        defer allocator.free(input);
        var filter = allocator.alloc(u8, 1) catch |err| {
            std.log.err("Failed to allocate memory: {}\n", .{err});
            return;
        };
        defer allocator.free(filter);

        try stdout.print("Enter a text for anagram:\n", .{});
        try bw.flush();

        var counter: usize = 0;
        input[0] = 0;
        while (true) {
            const symbol = stdin.readByte() catch |err| {
                std.log.err("Failed to read byte: {}\n", .{err});
                return;
            };
            if ('\n' == symbol) {
                break;
            } else if (counter >= input.len) {
                input = allocator.realloc(input, counter + 1) catch |err| {
                    std.log.err("Failed to reallocate buffer: {}\n", .{err});
                    return;
                };
            }
            input[counter] = symbol;
            counter += 1;
        }

        try stdout.print("Enter a text for filter:\n", .{});
        try bw.flush();

        counter = 0;
        filter[0] = 0;
        while (true) {
            const symbol = stdin.readByte() catch |err| {
                std.log.err("Failed to read byte for filter: {}\n", .{err});
                return;
            };
            if ('\n' == symbol) {
                break;
            } else if (counter >= filter.len) {
                filter = allocator.realloc(filter, counter + 1) catch |err| {
                    std.log.err("Failed to reallocate buffer for filter: {}\n", .{err});
                    return;
                };
            }
            filter[counter] = symbol;
            counter += 1;
        }

        if (Utf8View.init(filter)) |filter_utf| {
            if (makeAnagram(input, filter_utf)) {
                try stdout.print("Result: {s}\nTo exit enter q/Q, else - \"Enter\": \n", .{input});
            } else |err| {
                try stdout.print("Failed to make anagram: {}\n", .{err});
            }
            try bw.flush();
        } else |err| {
            std.log.err("Failed to convert input to UTF-8: {}\n", .{err});
        }

        counter = 0;
        while (true) {
            const symbol = stdin.readByte() catch |err| {
                std.log.err("Failed to read byte for ans: {}\n", .{err});
                return;
            };
            if ('\n' == symbol) {
                break;
            } else if (counter >= filter.len) {
                filter = allocator.realloc(filter, counter + 1) catch |err| {
                    std.log.err("Failed to reallocate buffer for ans: {}\n", .{err});
                    return;
                };
            }
            filter[counter] = symbol;
            counter += 1;
        }

        if (filter[0] == 'q' or filter[0] == 'Q') {
            try bw.flush();
            break;
        }
    }
}

fn makeAnagram(input: []u8, filter: Utf8View) !void {
    var prev_start: usize = 0;
    var start: usize = 0;
    var end: usize = 0;
    var i: usize = 0;

    while (i < input.len) {
        const l: usize = unicode.utf8ByteSequenceLength(input[i]) catch 0;
        if (l != 1 or !ascii.isWhitespace(input[i])) {
            i += l;
            continue;
        }
        start = prev_start;
        end = i;
        try reverseWord(input[start..end], filter);
        prev_start = i + 1;
        i += l;
    }
    start = prev_start;
    end = input.len;
    try reverseWord(input[start..end], filter);
}

fn reverseWord(input: []u8, filter: Utf8View) !void {
    if (input.len == 0) {
        return;
    }
    var end = input.len - 1;
    var start: usize = 0;
    while (start < end) {
        const len_start: usize = unicode.utf8ByteSequenceLength(input[start]) catch 0;
        while (end >= 0) : (end -= 1) {
            const rc: usize = unicode.utf8ByteSequenceLength(input[end]) catch 0;
            if (rc != 0) {
                break;
            }
        }
        if (start > end) {
            break;
        }
        const len_end: usize = unicode.utf8ByteSequenceLength(input[end]) catch 0;

        if (isIgnored(input[start .. start + len_start], filter)) {
            start += len_start;
        } else if (isIgnored(input[end .. end + len_end], filter)) {
            end -= len_end;
        } else {
            if (len_start == 1 and len_end == 1) {
                var tmp = input[start];
                input[start] = input[end];
                input[end] = tmp;
            } else {
                const allocator = std.heap.page_allocator;
                var first = try allocator.alloc(u8, len_start);
                std.mem.copy(u8, first, input[start .. start + len_start]);

                var last = try allocator.alloc(u8, len_end);
                std.mem.copy(u8, last, input[end .. end + len_end]);

                var tmp = try allocator.alloc(u8, end - start - len_start);
                std.mem.copy(u8, tmp, input[start + len_start .. end]);

                var s = start;
                var e = start + len_end;
                std.mem.copy(u8, input[s..e], last);

                s = e;
                e = e + tmp.len;
                std.mem.copy(u8, input[s..e], tmp);

                s = e;
                e = e + len_start;
                std.mem.copy(u8, input[s..e], first);

                allocator.free(first);
                allocator.free(last);
                allocator.free(tmp);
            }
            start += len_end;
            end -= len_start;
        }
    }
}

fn isIgnored(symbol: []const u8, filter: Utf8View) bool {
    const len: usize = unicode.utf8CountCodepoints(filter.bytes) catch 0;
    if (len == 0 and symbol.len == 1) {
        return ascii.isDigit(symbol[0]) or !ascii.isAlphabetic(symbol[0]);
    } else {
        var iterator = filter.iterator();
        var cp = iterator.nextCodepointSlice();
        while (cp != null) {
            const c = cp.?;
            if (std.mem.eql(u8, symbol, c)) {
                return true;
            }
            cp = iterator.nextCodepointSlice();
        }
        return false;
    }
}

test "test_ASCII_no_filter" {
    const filter = try Utf8View.init("");
    const in: [:0]const u8 = "Foxminded cool 24/7";
    const ex: [:0]const u8 = "dednimxoF looc 24/7";

    var input: [in.len:0]u8 = undefined;
    var exp: [ex.len:0]u8 = undefined;
    std.mem.copy(u8, &input, in);
    std.mem.copy(u8, &exp, ex);
    try makeAnagram(&input, filter);
    try std.testing.expectEqual(exp, input);
}

test "test_ASCII_filter" {
    const filter = try Utf8View.init("xl");
    const in: [:0]const u8 = "Foxminded cool 24/7";
    const ex: [:0]const u8 = "dexdnimoF oocl 7/42";

    var input: [in.len:0]u8 = undefined;
    var exp: [ex.len:0]u8 = undefined;
    std.mem.copy(u8, &input, in);
    std.mem.copy(u8, &exp, ex);
    try makeAnagram(&input, filter);
    try std.testing.expectEqual(exp, input);
}

test "test_UTF8_no_filter" {
    const filter = try Utf8View.init("");
    const in: [:0]const u8 = "волшебный 1 кролик";
    const ex: [:0]const u8 = "йынбешлов 1 килорк";

    var input: [in.len:0]u8 = undefined;
    var exp: [ex.len:0]u8 = undefined;
    std.mem.copy(u8, &input, in);
    std.mem.copy(u8, &exp, ex);
    try makeAnagram(&input, filter);
    try std.testing.expectEqual(exp, input);
}

test "test_UTF8_filter" {
    const filter = try Utf8View.init("ло");
    const in: [:0]const u8 = "волшебный 1 кролик";
    const ex: [:0]const u8 = "йолынбешв 1 киолрк";

    var input: [in.len:0]u8 = undefined;
    var exp: [ex.len:0]u8 = undefined;
    std.mem.copy(u8, &input, in);
    std.mem.copy(u8, &exp, ex);
    try makeAnagram(&input, filter);
    try std.testing.expectEqual(exp, input);
}

test "test_empty" {
    const filter = try Utf8View.init("");
    const in: [:0]const u8 = "";
    const ex: [:0]const u8 = "";

    var input: [in.len:0]u8 = undefined;
    var exp: [ex.len:0]u8 = undefined;
    std.mem.copy(u8, &input, in);
    std.mem.copy(u8, &exp, ex);
    try makeAnagram(&input, filter);
    try std.testing.expectEqual(exp, input);
}
