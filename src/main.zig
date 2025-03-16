//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const log = std.log.scoped(.main);

pub fn main() !void {
    const reader = std.io.getStdIn().reader().any();
    const stdout = std.io.getStdOut().writer();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

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
    while (true) {
        const header = try protocol.LSPHeader.parse(reader);
        const json_message = try std.heap.page_allocator.alloc(u8, header.content_length);
        defer std.heap.page_allocator.free(json_message);

        try reader.readNoEof(json_message);
        log.info("json_message: '{s}'", .{json_message});

        const method = try rpc.parseMethod(arena.allocator(), json_message);
        log.info("GOT MESSAGE FOR METHOD: {s}", .{method});
        if (std.mem.eql(u8, method, "initialize")) {
            const init_request = try std.json.parseFromSliceLeaky(initialize.InitializeRequest, arena.allocator(), json_message, .{ .ignore_unknown_fields = true });
            const client_info = init_request.params.clientInfo.?;
            log.info("client_info: {{name: {s}, version: {s}}}", .{ client_info.name, client_info.version });
            const response = try rpc.encodeMessage(arena.allocator(), initialize.NewInitializeResponse(init_request.id));
            log.info("sending reply: {s}\n", .{response});
            try stdout.print("{s}", .{response});
        } else if (std.mem.eql(u8, method, "textDocument/didOpen")) {
            const open_request = try std.json.parseFromSliceLeaky(TextDocumentDidOpenNotification, arena.allocator(), json_message, .{ .ignore_unknown_fields = true });
            log.info("didOpen: {s}", .{open_request.params.textDocument.text.?});
        } else if (std.mem.eql(u8, method, "textDocument/didChange")) {
            const change_request = try std.json.parseFromSliceLeaky(TextDocumentDidChangeNotification, arena.allocator(), json_message, .{ .ignore_unknown_fields = true });
            log.info("didChange: {any}", .{change_request.params.contentChanges});
        } else if (std.mem.eql(u8, method, "textDocument/hover")) {
            const hover_request = try std.json.parseFromSliceLeaky(TextDocumentHoverNotification, arena.allocator(), json_message, .{ .ignore_unknown_fields = true });
            log.info("hover: {any}", .{hover_request.params});
        }
    }
}

pub const TextDocumentItem = struct {
    uri: []const u8,
    languageId: ?[]const u8 = null,
    version: usize,
    text: ?[]const u8 = null,
};

pub const TextDocumentDidOpenNotification = struct {
    jsonrpc: []const u8,
    method: []const u8,
    params: DidOpenTextDocumentParams,

    pub const DidOpenTextDocumentParams = struct {
        textDocument: TextDocumentItem,
    };
};

pub const TextDocumentDidChangeNotification = struct {
    jsonrpc: []const u8,
    method: []const u8,
    params: DidChangeTextDocumentParams,

    pub const DidChangeTextDocumentParams = struct {
        textDocument: TextDocumentItem,
        contentChanges: []TextDocumentChangeEvent,
    };

    pub const TextDocumentChangeEvent = struct {
        // range: Range,
        // rangeLength: ?usize,
        text: []const u8,
    };
};

pub const TextDocumentHoverNotification = struct {
    jsonrpc: []const u8,
    method: []const u8,
    params: HoverParams,

    pub const HoverParams = struct {
        textDocument: TextDocumentIdentifier,
        position: Position,
    };
};
pub const TextDocumentIdentifier = struct {
    uri: []const u8,
};

pub const Range = struct {
    start: Position,
    end: Position,
};

pub const Position = struct {
    line: usize,
    character: usize,
};

const std = @import("std");
const rpc = @import("rpc.zig");
const protocol = @import("lsp/protocol.zig");
const initialize = @import("lsp/initialize.zig");
/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("dbx-ls_lib");
