const std = @import("std");
const net = std.net;
const testing = std.testing;

/// Connected client data: allocator, stream, and username
const Client = struct {
    allocator: std.mem.Allocator, // For dynamic allocations
    stream: net.Stream, // TCP connection to client
    username: []const u8, // Client's display name (heap-allocated)
};

/// Shared list of all connected clients (protected by clients_mutex)
var clients: std.ArrayList(Client) = .empty;

/// Protects concurrent access to clients list across multiple threads
var clients_mutex = std.Thread.Mutex{};

/// TCP chat server entry point. Listens on 127.0.0.1:8080 and spawns
/// a thread per client connection. Runs until terminated.
pub fn main() !void {
    const allocator = std.heap.page_allocator; // Simple allocator for production

    // Bind to localhost:8080 with address reuse enabled
    const address = try net.Address.parseIp("127.0.0.1", 8080);
    var server = try address.listen(.{
        .reuse_address = true, // Avoid "address already in use" on restart
    });
    defer server.deinit();

    std.debug.print("TCPSYS server started on 127.0.0.1:8080\n", .{});

    // Main accept loop - one thread per client
    while (true) {
        const conn = try server.accept(); // Blocks until client connects

        // Spawn dedicated thread for this client
        const thread = try std.Thread.spawn(.{}, handleClient, .{ allocator, conn.stream });
        thread.detach(); // Run independently, auto-cleanup on completion
    }
}

/// Reads username from stream until '#' delimiter. Returns "anonymous" if empty.
/// Username stored in caller-provided buffer and valid while buffer is in scope.
fn read_username(stream: net.Stream, buffer: []u8) ![]const u8 {
    var read_buffer: [256]u8 = undefined;
    var reader = stream.reader(&read_buffer);
    var stdin = &reader.file_reader.interface;
    const username = try stdin.takeDelimiter('#') orelse "anonymous";

    @memcpy(buffer[0..username.len], username);
    return buffer[0..username.len];
}

// username is valid as long as username_buffer is in scope

/// Handles a client connection lifecycle: join, message relay, and disconnect.
/// Thread-safe. Runs in dedicated thread per client.
fn handleClient(allocator: std.mem.Allocator, stream: net.Stream) !void {
    defer stream.close(); // Always close connection on exit

    var read_buffer: [256]u8 = undefined;
    const username = try read_username(stream, &read_buffer);

    // Add client to shared list (thread-safe)
    clients_mutex.lock();
    try clients.append(allocator, .{
        .allocator = allocator,
        .stream = stream,
        .username = username,
    });
    const client_idx = clients.items.len - 1; // Save index for exclusion/removal
    clients_mutex.unlock();

    std.debug.print("{s} connected\n", .{username});

    // Tell other clients someone joined
    const join_msg = try std.fmt.allocPrint(allocator, "{s} connected\n", .{username});
    defer allocator.free(join_msg);
    send(join_msg, client_idx); // Exclude self from notification

    // Message relay loop
    while (true) {
        var msg_buf: [1024]u8 = undefined;
        var msg_reader = stream.reader(&msg_buf);
        var msg_stdin = &msg_reader.file_reader.interface;

        const message = try msg_stdin.takeDelimiter('\n') orelse break; // null = disconnect

        // Broadcast message to all except sender
        const prompt = try std.fmt.allocPrint(allocator, "{s} says: {s}", .{ username, message });
        send(prompt, client_idx);
    }

    // Cleanup: remove from list
    clients_mutex.lock();
    _ = clients.orderedRemove(client_idx);
    clients_mutex.unlock();

    std.debug.print("{s} disconnected\n", .{username});

    // Tell everyone this client left
    const leave_msg = try std.fmt.allocPrint(allocator, "{s} disconnected\n", .{username});
    defer allocator.free(leave_msg);
    send(leave_msg, null); // null = broadcast to all
}

/// Sends a message to clients, optionally excluding the sender.
/// Thread-safe. Silently skips clients that fail to receive.
fn send(message: []const u8, client_idx: ?usize) void {
    clients_mutex.lock();
    defer clients_mutex.unlock();

    for (clients.items, 0..) |client, i| {
        // Skip sender if client_idx is provided (broadcast excludes sender)
        if (client_idx) |actual_id| {
            if (i == actual_id) continue;
        }

        // Send message + newline, ignore failures
        _ = client.stream.write(message) catch continue;
        _ = client.stream.write("\n") catch continue;
    }
}
