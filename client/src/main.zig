const std = @import("std");
const net = std.net;
const posix = std.posix;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.skip();

    const username = args.next() orelse {
        std.debug.print("Usage: client <username>\n", .{});
        return;
    };

    const address = try net.Address.parseIp("127.0.0.1", 8080);
    const stream = try net.tcpConnectToAddress(address);
    defer stream.close();

    _ = try stream.write(username);

    std.debug.print("Connected as '{s}'. Type your messages:\n", .{username});

    const recv_thread = try std.Thread.spawn(.{}, receiveMessages, .{stream});
    recv_thread.detach();

    var stdin_buf: [1024]u8 = undefined;
    var stdout_buf: [1024]u8 = undefined;

    var stdin_writer = std.fs.File.stdout().reader(&stdin_buf);
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);

    const stdin = &stdin_writer.interface;
    const stdout = &stdout_writer.interface;

    // var buf: [1024]u8 = undefined;
    while (true) {
        try stdout.print("> ", .{});

        while (stdin.takeDelimiterExclusive('\n')) |line| {
            if (line.len == 0) continue;
            _ = stream.write(line) catch break;
            _ = stream.write("\n") catch break;
        } else |err| switch (err) {
            error.EndOfStream, // stream ended not on a line break
            error.StreamTooLong, // line could not fit in buffer
            error.ReadFailed, // caller can check reader implementation for diagnostics
            => |e| return e,
        }
    }

    try stdout.flush();
}

fn receiveMessages(stream: net.Stream) !void {
    var stdoud_buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdoud_buf);
    const stdout = &stdout_writer.interface;

    var buf: [1024]u8 = undefined;

    while (true) {
        const n = stream.read(&buf) catch break;
        if (n == 0) break;

        try stdout.print("\r{s}> ", .{buf[0..n]});
    }

    try stdout.flush();
}
