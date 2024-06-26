const std = @import("std");
const ascii = @import("std").ascii;
const unicode = @import("std").unicode;
const Allocator = std.mem.Allocator;
const Reader = std.io.AnyReader;
const Utf8View = unicode.Utf8View;

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    const stdin_file = std.io.getStdIn().reader();
    var br = std.io.bufferedReader(stdin_file);
    const stdin = br.reader().any();

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

        readLine(stdin, allocator, &input) catch |err| {
            std.log.err("Failed to read line: {}\n", .{err});
            return;
        };

        try stdout.print("Enter a text for filter:\n", .{});
        try bw.flush();

        readLine(stdin, allocator, &filter) catch |err| {
            std.log.err("Failed to read line for filter: {}\n", .{err});
            return;
        };

        if (Utf8View.init(filter)) |filter_utf| {
            makeAnagram(input, filter_utf);
            try stdout.print("Result: {s}\nTo exit enter q/Q, else - \"Enter\": \n", .{input});
            try bw.flush();
        } else |err| {
            std.log.err("Failed to convert input to UTF-8: {}\n", .{err});
        }

        readLine(stdin, allocator, &filter) catch |err| {
            std.log.err("Failed to read line for answer: {}\n", .{err});
            return;
        };
        if (filter[0] == 'q' or filter[0] == 'Q') {
            try bw.flush();
            break;
        }
    }
}

fn readLine(f_source: std.io.AnyReader, allocator: std.mem.Allocator, input: *[]u8) !void {
    var counter: usize = 0;
    input.*[0] = 0;
    while (true) {
        const symbol = try f_source.readByte();
        if ('\n' == symbol) {
            break;
        } else if (counter >= input.len) {
            input.* = try allocator.realloc(input.*, counter + 1);
        }
        input.*[counter] = symbol;
        counter += 1;
    }
}

fn makeAnagram(input: []u8, filter: Utf8View) void {
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
        reverseWord(input[start..end], filter);
        prev_start = i + 1;
        i += l;
    }
    start = prev_start;
    end = input.len;
    reverseWord(input[start..end], filter);
}

fn reverseWord(input: []u8, filter: Utf8View) void {
    if (input.len == 0) {
        return;
    }
    var end = input.len - 1;
    var start: usize = 0;
    while (start < end) {
        const len_start: u3 = unicode.utf8ByteSequenceLength(input[start]) catch 0;
        while (end >= 0) : (end -= 1) {
            const rc: u3 = unicode.utf8ByteSequenceLength(input[end]) catch 0;
            if (rc != 0) {
                break;
            }
        }
        if (start > end) {
            break;
        }
        const len_end: u3 = unicode.utf8ByteSequenceLength(input[end]) catch 0;

        if (isIgnored(input[start .. start + len_start], filter)) {
            start += len_start;
        } else if (isIgnored(input[end .. end + len_end], filter)) {
            end -= len_end;
        } else {
            const size_symbol_buff: usize = 16; // max size of tmp buffer for biggest symbol, bytes
            var size_tmp_symbol: usize = 0; // size of biggest symbol to swap, bytes
            var size_symbol: usize = 0; // size of smallest symbol to swap, bytes
            var idx_tmp_from_s: usize = 0; // index of biggest symbol's start in array 'input'
            var idx_from_s: usize = 0; // index of smallest symbol's start in array 'input'
            var idx_into_s: usize = 0; // index in array 'input' where to put smallest symbol
            var idx_tmp_into_s: usize = 0; // index in array 'input' where to put tmp symbol
            var buff_tmp = [_]u8{0} ** size_symbol_buff;

            var idx_start: usize = 0;
            var idx_end: usize = 0;
            const step: usize = 1;
            if (len_start >= len_end) {
                idx_start = start + len_start;
                idx_end = end;

                size_tmp_symbol = len_start;
                size_symbol = len_end;

                idx_tmp_from_s = start;
                idx_into_s = start;
                idx_from_s = end;
                idx_tmp_into_s = end + len_end - len_start;
            } else {
                idx_start = end + len_end - len_start - 1;
                idx_end = start + len_start;

                size_tmp_symbol = len_end;
                size_symbol = len_start;

                idx_tmp_from_s = end;
                idx_into_s = end + len_end - len_start;
                idx_from_s = start;
                idx_tmp_into_s = start;
            }
            @memcpy(buff_tmp[0..size_tmp_symbol], input[idx_tmp_from_s..(idx_tmp_from_s + size_tmp_symbol)]);
            std.mem.copyForwards(u8, input[idx_into_s..(idx_into_s + size_symbol)], input[idx_from_s..(idx_from_s + size_symbol)]);
            if (len_start != len_end) {
                while (idx_start != idx_end) {
                    var next: usize = 0;
                    if (len_start >= len_end) {
                        next = idx_start + step;
                    } else {
                        next = idx_start - step;
                    }
                    input[idx_start] = input[next];
                    idx_start = next;
                }
            }
            @memcpy(input[idx_tmp_into_s..(idx_tmp_into_s + size_tmp_symbol)], buff_tmp[0..size_tmp_symbol]);
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

test "test_UTF8_diff_size" {
    const filter = try Utf8View.init("");
    const in: [:0]const u8 = "Boлшeбный 1 кpoлик";
    const ex: [:0]const u8 = "йынбeшлoB 1 килopк";

    var input: [in.len:0]u8 = undefined;
    var exp: [ex.len:0]u8 = undefined;
    @memcpy(&input, in);
    @memcpy(&exp, ex);
    makeAnagram(&input, filter);
    try std.testing.expectEqual(exp, input);
}

test "test_ASCII_no_filter" {
    const filter = try Utf8View.init("");
    const in: [:0]const u8 = "Foxminded cool 24/7";
    const ex: [:0]const u8 = "dednimxoF looc 24/7";

    var input: [in.len:0]u8 = undefined;
    var exp: [ex.len:0]u8 = undefined;
    @memcpy(&input, in);
    @memcpy(&exp, ex);
    makeAnagram(&input, filter);
    try std.testing.expectEqual(exp, input);
}

test "test_ASCII_filter" {
    const filter = try Utf8View.init("xl");
    const in: [:0]const u8 = "Foxminded cool 24/7";
    const ex: [:0]const u8 = "dexdnimoF oocl 7/42";

    var input: [in.len:0]u8 = undefined;
    var exp: [ex.len:0]u8 = undefined;
    @memcpy(&input, in);
    @memcpy(&exp, ex);
    makeAnagram(&input, filter);
    try std.testing.expectEqual(exp, input);
}

test "test_UTF8_no_filter" {
    const filter = try Utf8View.init("");
    const in: [:0]const u8 = "волшебный 1 кролик";
    const ex: [:0]const u8 = "йынбешлов 1 килорк";

    var input: [in.len:0]u8 = undefined;
    var exp: [ex.len:0]u8 = undefined;
    @memcpy(&input, in);
    @memcpy(&exp, ex);
    makeAnagram(&input, filter);
    try std.testing.expectEqual(exp, input);
}

test "test_UTF8_filter" {
    const filter = try Utf8View.init("ло");
    const in: [:0]const u8 = "волшебный 1 кролик";
    const ex: [:0]const u8 = "йолынбешв 1 киолрк";

    var input: [in.len:0]u8 = undefined;
    var exp: [ex.len:0]u8 = undefined;
    @memcpy(&input, in);
    @memcpy(&exp, ex);
    makeAnagram(&input, filter);
    try std.testing.expectEqual(exp, input);
}

test "test_empty" {
    const filter = try Utf8View.init("");
    const in: [:0]const u8 = "";
    const ex: [:0]const u8 = "";

    var input: [in.len:0]u8 = undefined;
    var exp: [ex.len:0]u8 = undefined;
    @memcpy(&input, in);
    @memcpy(&exp, ex);
    makeAnagram(&input, filter);
    try std.testing.expectEqual(exp, input);
}
