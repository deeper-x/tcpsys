const std = @import("std");
const net = std.net;

/// Chat client entry point. Connects to server, sends username handshake,
/// spawns receive thread, and enters send loop. Exits on EOF or disconnect.
pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Get username from command line
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip(); // Skip program name

    const username = args.next() orelse {
        std.debug.print("Usage: client <username>\n", .{});
        return;
    };

    // Prepare username with '#' delimiter for server protocol
    const username_delimit = try std.fmt.allocPrint(allocator, "{s}#", .{username});

    // Connect to server
    const address = try net.Address.parseIp("127.0.0.1", 8080);
    const stream = try net.tcpConnectToAddress(address);
    defer stream.close();

    // Send username handshake
    var write_buf: [1024]u8 = undefined;
    var writer = stream.writer(&write_buf);
    _ = try writer.interface.writeAll(username_delimit);

    std.debug.print("Connected as '{s}'. Type your messages:\n", .{username});
    try writer.interface.flush(); // Force send

    // Spawn thread to receive messages concurrently
    const recv_thread = try std.Thread.spawn(.{}, receiveMessages, .{stream});
    recv_thread.detach();

    // Setup stdin reader for user input
    var stdin_buf: [1024]u8 = undefined;
    var stdin_writer = std.fs.File.stdin().reader(&stdin_buf);
    const stdin = &stdin_writer.interface;

    // Send loop - read from stdin and send to server
    while (true) {
        std.debug.print("{s}> ", .{username});

        while (stdin.takeDelimiter('\n') catch null) |line| {
            if (line.len == 0) continue; // Skip empty lines

            // Send message with newline; break on error
            _ = stream.write(line) catch break;
            _ = stream.write("\n") catch break;
        } else {
            break; // EOF (Ctrl+D) - exit
        }
    }
}

/// Receives and displays messages from the server in a dedicated thread.
/// Exits when connection closes or read fails.
fn receiveMessages(stream: net.Stream) !void {
    var buf: [1024]u8 = undefined;

    while (true) {
        const n = stream.read(&buf) catch break; // Break on error
        if (n == 0) break; // Break on connection close (EOF)

        // Display message, \r overwrites current input prompt
        std.debug.print("\r{s}", .{buf[0..n]});
    }
}
