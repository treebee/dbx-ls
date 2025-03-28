const log = std.log.scoped(.main);
pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = logFn,
};

var log_stderr: bool = true;
var log_level: std.log.Level = .info;
var log_file: ?std.fs.File = null;

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    var buffer: [8192]u8 = undefined;
    _ = std.fmt.bufPrint(&buffer, format, args) catch return;

    const level_txt: []const u8 = switch (level) {
        .err => "error",
        .warn => "warn ",
        .info => "info ",
        .debug => "debug",
    };
    const scope_txt: []const u8 = comptime @tagName(scope);

    var fbs = std.io.fixedBufferStream(&buffer);
    const no_space_left = blk: {
        fbs.writer().print("{s} ({s:^6}): ", .{ level_txt, scope_txt }) catch break :blk true;
        fbs.writer().print(format, args) catch break :blk true;
        fbs.writer().writeByte('\n') catch break :blk true;
        break :blk false;
    };
    if (no_space_left) {
        buffer[buffer.len - 4 ..][0..4].* = "...\n".*;
    }

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();

    if (log_stderr) {
        std.io.getStdErr().writeAll(fbs.getWritten()) catch {};
    }

    if (log_file) |file| {
        file.seekFromEnd(0) catch {};
        file.writeAll(fbs.getWritten()) catch {};
    }
}

pub fn main() !void {
    const reader = std.io.getStdIn().reader().any();
    const stdout = std.io.getStdOut().writer();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    log_file = try std.fs.cwd().createFile("log.txt", .{});
    defer log_file.?.close();

    var args = try std.process.ArgIterator.initWithAllocator(arena.allocator());

    _ = args.next();
    var arguments = std.ArrayList([:0]const u8).init(arena.allocator());
    while (args.next()) |arg| {
        try arguments.append(arg);
    }
    if (arguments.items.len > 1) {
        std.debug.print("Usage: dbx-ls [--version]", .{});
        std.process.exit(64);
    } else if (arguments.items.len == 1) {
        if (!std.mem.eql(u8, arguments.items[0], "--version")) {
            std.debug.print("Usage: dbx-ls [--version]", .{});
            std.process.exit(64);
        } else {
            try stdout.print("0.1alpha\n", .{});
            std.process.exit(0);
        }
    }

    var state = State.init(arena.allocator());

    while (true) {
        const header = try protocol.LSPHeader.parse(reader);
        const json_message = try std.heap.page_allocator.alloc(u8, header.content_length);
        defer std.heap.page_allocator.free(json_message);

        try reader.readNoEof(json_message);
        log.info("'{s}'\n", .{json_message});

        const method = try rpc.parseMethod(arena.allocator(), json_message);
        if (std.mem.eql(u8, method, "initialize")) {
            const init_request = try std.json.parseFromSliceLeaky(initialize.InitializeRequest, arena.allocator(), json_message, .{ .ignore_unknown_fields = true });
            const response = try rpc.encodeMessage(arena.allocator(), initialize.NewInitializeResponse(init_request.id));
            try stdout.print("{s}", .{response});
        } else if (std.mem.eql(u8, method, "textDocument/didOpen")) {
            const open_request = try std.json.parseFromSliceLeaky(TextDocumentDidOpenNotification, arena.allocator(), json_message, .{ .ignore_unknown_fields = true });
            log.info("didOpen: \n", .{});
            const document = open_request.params.textDocument;
            if (std.mem.eql(u8, document.languageId.?, "python")) {
                try parser.parse_notebook(arena.allocator(), &state, document.uri, document.text.?);
            }
            log.info("STATE *****************\n", .{});
            log.info("state: {s}\n", .{state});
            log.info("******************************", .{});
        } else if (std.mem.eql(u8, method, "textDocument/didChange")) {
            const change_request = try std.json.parseFromSliceLeaky(TextDocumentDidChangeNotification, arena.allocator(), json_message, .{ .ignore_unknown_fields = true });
            log.info("didChange: {any}\n", .{change_request.params.contentChanges});
        } else if (std.mem.eql(u8, method, "textDocument/hover")) {
            const hover_request = try std.json.parseFromSliceLeaky(TextDocumentHoverNotification, arena.allocator(), json_message, .{ .ignore_unknown_fields = true });
            log.info("hover: {any}\n", .{hover_request.params});
        }
    }
}

const std = @import("std");
const rpc = @import("rpc.zig");
const protocol = @import("lsp/protocol.zig");
const initialize = @import("lsp/initialize.zig");
/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("dbx-ls_lib");
const State = @import("state.zig").State;
const parser = @import("parser.zig");
const text_document = @import("text_document.zig");

const TextDocumentDidOpenNotification = text_document.TextDocumentDidOpenNotification;
const TextDocumentDidChangeNotification = text_document.TextDocumentDidChangeNotification;
const TextDocumentHoverNotification = text_document.TextDocumentHoverNotification;
