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
    var buffer: [4096]u8 = undefined;
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
            log.info("didOpen: {s}\n", .{open_request.params.textDocument.text.?});
            const document = open_request.params.textDocument;
            if (std.mem.eql(u8, document.languageId.?, "python")) {
                try parse_notebook(arena.allocator(), &state, document.uri, document.text.?);
            }
            log.info("state: {s}\n", .{state});
        } else if (std.mem.eql(u8, method, "textDocument/didChange")) {
            const change_request = try std.json.parseFromSliceLeaky(TextDocumentDidChangeNotification, arena.allocator(), json_message, .{ .ignore_unknown_fields = true });
            log.info("didChange: {any}\n", .{change_request.params.contentChanges});
        } else if (std.mem.eql(u8, method, "textDocument/hover")) {
            const hover_request = try std.json.parseFromSliceLeaky(TextDocumentHoverNotification, arena.allocator(), json_message, .{ .ignore_unknown_fields = true });
            log.info("hover: {any}\n", .{hover_request.params});
        }
    }
}

fn write_line(writer: anytype, line: []const u8) !void {
    try writer.print("{s}", .{line});
    try writer.writeByte('\n');
}

pub fn parse_notebook(allocator: std.mem.Allocator, state: *State, uri: []const u8, content: []const u8) !void {
    var line_iter = std.mem.splitSequence(u8, content, "\n");
    const first = line_iter.next().?;
    if (!std.mem.startsWith(u8, first, "# Databricks notebook source")) {
        log.info("Not a databricks notebook: {s}", .{uri});
        return error.NotANotebookDocument;
    }

    var buffer: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    var previous_is_magic = false;
    var notebook_cells = std.ArrayList(NotebookCell).init(allocator);

    var language = "py";
    while (line_iter.next()) |line| {
        if (std.mem.eql(u8, line, "\n")) {
            log.debug("{s}\n", .{line});
            continue;
        }
        if (std.mem.startsWith(u8, line, "# MAGIC ")) {
            if (std.mem.startsWith(u8, line, "# MAGIC %sh")) {
                language = "sh";
            } else if (std.mem.startsWith(u8, line, "# MAGIC %md")) {
                language = "md";
            }

            log.info("Magic open", .{});
            try write_line(fbs.writer(), line);
            previous_is_magic = true;
        } else if (std.mem.startsWith(u8, line, "# COMMAND ----------")) {
            log.debug("TEXT: {s}\n*******************\n", .{fbs.getWritten()});
            const cell_content = try std.fmt.allocPrint(allocator, "{s}", .{fbs.getWritten()});
            try notebook_cells.append(NotebookCell.init(language, cell_content));
            fbs.reset();
            previous_is_magic = false;
        } else {
            try write_line(fbs.writer(), line);
            previous_is_magic = false;
        }
    }
    log.debug("TEXT: {s}|{d}\n*******************\n", .{ fbs.getWritten(), try fbs.getPos() });
    if (try fbs.getPos() > 1) {
        const cell_content = try std.fmt.allocPrint(allocator, "{s}", .{fbs.getWritten()});
        try notebook_cells.append(NotebookCell{ .language = language, .text = cell_content });
    }
    try state.notebooks.put(uri, .{ .cells = notebook_cells.items });
}

pub const NotebookCell = struct {
    language: []const u8,
    text: []const u8,

    pub fn init(language: []const u8, text: []const u8) @This() {
        return NotebookCell{ .language = language, .text = text };
    }
};

pub const State = struct {
    notebooks: std.hash_map.StringHashMap(ParsedNotebook),

    pub fn init(allocator: std.mem.Allocator) State {
        return State{
            .notebooks = std.hash_map.StringHashMap(ParsedNotebook).init(allocator),
        };
    }

    pub const ParsedNotebook = struct {
        cells: []NotebookCell,
    };

    pub fn format(
        self: State,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        var notebook_iter = self.notebooks.keyIterator();
        while (notebook_iter.next()) |uri| {
            try writer.print("uri = {s}\n", .{uri.*});
            for (0.., self.notebooks.get(uri.*).?.cells) |i, cell| {
                try writer.print("\t({d}) {s} {s}\n", .{ i, cell.language, cell.text });
            }
        }

        try writer.writeAll("");
    }
};
pub const NotebookDocument = struct {
    uri: []const u8,
    version: usize,
};

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
