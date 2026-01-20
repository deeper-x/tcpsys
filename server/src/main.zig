const std = @import("std");
const net = std.net;

const Client = struct {
    stream: net.Stream,
    username: []const u8,
    allocator: std.mem.Allocator,
};

var clients: std.ArrayList(Client) = .empty;
var clients_mutex = std.Thread.Mutex{};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const address = try net.Address.parseIp("127.0.0.1", 8080);
    var server = try address.listen(.{
        .reuse_address = true,
    });
    defer server.deinit();

    std.debug.print("TCPSYS server started on 127.0.0.1:8080\n", .{});

    while (true) {
        const conn = try server.accept();
        const thread = try std.Thread.spawn(.{}, handleClient, .{ conn.stream, allocator });
        thread.detach();
    }
}

fn handleClient(stream: net.Stream, allocator: std.mem.Allocator) !void {
    defer stream.close();

    var read_buffer: [256]u8 = undefined;
    var reader = stream.reader(&read_buffer);
    var stdin = &reader.file_reader.interface;

    const username = try stdin.takeDelimiter('#') orelse "anonymous";

    clients_mutex.lock();
    try clients.append(allocator, .{
        .stream = stream,
        .username = username,
        .allocator = allocator,
    });

    const client_idx = clients.items.len - 1;
    clients_mutex.unlock();

    std.debug.print("{s} connected\n", .{username});

    // Notify all other clients
    const join_msg = try std.fmt.allocPrint(allocator, "{s} connected\n", .{username});
    defer allocator.free(join_msg);
    broadcast(join_msg, client_idx);

    while (true) {
        var msg_buf: [1024]u8 = undefined;
        const msg_len = stream.read(&msg_buf) catch break;
        if (msg_len == 0) break;

        const message = try std.fmt.allocPrint(allocator, "Message from {s}: {s}", .{ username, msg_buf[0..msg_len] });
        defer allocator.free(message);

        broadcast(message, client_idx);
    }

    clients_mutex.lock();
    _ = clients.orderedRemove(client_idx);
    clients_mutex.unlock();

    std.debug.print("{s} disconnected\n", .{username});

    // Notify remaining clients
    const leave_msg = try std.fmt.allocPrint(allocator, "{s} disconnected\n", .{username});
    defer allocator.free(leave_msg);
    broadcastToAll(leave_msg);

    allocator.free(username);
}

fn broadcast(message: []const u8, sender_idx: usize) void {
    clients_mutex.lock();
    defer clients_mutex.unlock();

    for (clients.items, 0..) |client, i| {
        if (i == sender_idx) continue;
        _ = client.stream.write(message) catch continue;
    }
}

fn broadcastToAll(message: []const u8) void {
    clients_mutex.lock();
    defer clients_mutex.unlock();

    for (clients.items) |client| {
        _ = client.stream.write(message) catch continue;
    }
}
