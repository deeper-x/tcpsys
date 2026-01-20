const std = @import("std");
const net = std.net;

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

    const username_delimit = try std.fmt.allocPrint(allocator, "{s}#", .{username});

    const address = try net.Address.parseIp("127.0.0.1", 8080);
    const stream = try net.tcpConnectToAddress(address);
    defer stream.close();

    var write_buf: [1024]u8 = undefined;
    var writer = stream.writer(&write_buf);

    _ = try writer.interface.writeAll(username_delimit);

    std.debug.print("Connected as '{s}'. Type your messages:\n", .{username});
    try writer.interface.flush();

    const recv_thread = try std.Thread.spawn(.{}, receiveMessages, .{stream});
    recv_thread.detach();

    var stdin_buf: [1024]u8 = undefined;

    var stdin_writer = std.fs.File.stdin().reader(&stdin_buf);
    const stdin = &stdin_writer.interface;

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
