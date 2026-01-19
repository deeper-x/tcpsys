const std = @import("std");
const net = std.net;
// const posix = std.posix;

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

    var stdin_writer = std.fs.File.stdin().reader(&stdin_buf);
    const stdin = &stdin_writer.interface;

    // var buf: [1024]u8 = undefined;
    while (true) {
        std.debug.print("{s}> ", .{username});

        while (stdin.takeDelimiter('\n') catch null) |line| {
            if (line.len == 0) continue;
            _ = stream.write(line) catch break;
            _ = stream.write("\n") catch break;
        } else {
            break;
        }
    }
}

fn receiveMessages(stream: net.Stream) !void {
    var buf: [1024]u8 = undefined;

    while (true) {
        const n = stream.read(&buf) catch break;
        if (n == 0) break;

        // Print received message on new line
        std.debug.print("\r{s}", .{buf[0..n]});
    }
}
