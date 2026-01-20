const std = @import("std");
const net = std.net;

const Client = struct {
    allocator: std.mem.Allocator,
    stream: net.Stream,
    username: []const u8,
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
        const thread = try std.Thread.spawn(.{}, handleClient, .{ allocator, conn.stream });
        thread.detach();
    }
}

fn handleClient(allocator: std.mem.Allocator, stream: net.Stream) !void {
    defer stream.close();

    var read_buffer: [256]u8 = undefined;
    var reader = stream.reader(&read_buffer);
    var stdin = &reader.file_reader.interface;

    const username = try stdin.takeDelimiter('#') orelse "anonymous";

    clients_mutex.lock();
    try clients.append(allocator, .{
        .allocator = allocator,
        .stream = stream,
        .username = username,
    });

    const client_idx = clients.items.len - 1;
    clients_mutex.unlock();

    std.debug.print("{s} connected\n", .{username});

    // Notify all other clients
    const join_msg = try std.fmt.allocPrint(allocator, "{s} connected\n", .{username});
    defer allocator.free(join_msg);
    send(join_msg, client_idx);

    while (true) {
        var msg_buf: [1024]u8 = undefined;
        var msg_reader = stream.reader(&msg_buf);
        var msg_stdin = &msg_reader.file_reader.interface;

        const message = try msg_stdin.takeDelimiter('\n') orelse break;

        const prompt = try std.fmt.allocPrint(allocator, "{s} says: {s}", .{ username, message });
        send(prompt, client_idx);
    }

    clients_mutex.lock();
    _ = clients.orderedRemove(client_idx);
    clients_mutex.unlock();

    std.debug.print("{s} disconnected\n", .{username});

    // Notify remaining clients
    const leave_msg = try std.fmt.allocPrint(allocator, "{s} disconnected\n", .{username});
    defer allocator.free(leave_msg);

    // send message broadcast, client_idx is null
    send(leave_msg, null);

    // allocator.free(username);
}

fn send(message: []const u8, client_idx: ?usize) void {
    clients_mutex.lock();
    defer clients_mutex.unlock();

    for (clients.items, 0..) |client, i| {
        // if client_idx is not set, it means it is a broadcast message
        if (client_idx) |actual_id| {
            if (i == actual_id) continue;
        }

        _ = client.stream.write(message) catch continue;
        _ = client.stream.write("\n") catch continue;
    }
}
