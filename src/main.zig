const std = @import("std");

const analyze_project = @import("analyze/project.zig");
const completion = @import("lsp/completion.zig");
const completion_analyzer = @import("analyze/completion.zig");
const lsp_diagnostics = @import("lsp/diagnostics.zig");
const hover = @import("lsp/hover.zig");
const hover_analyzer = @import("analyze/hover.zig");
const initialize = @import("lsp/initialize.zig");
const diagnostics = @import("analyze/diagnostics.zig");
const protocol = @import("lsp/protocol.zig");
const rpc = @import("rpc.zig");
const text_document = @import("lsp/text_document.zig");

const State = @import("State.zig");
const TextDocumentDidOpenNotification = text_document.TextDocumentDidOpenNotification;
const TextDocumentDidChangeNotification = text_document.TextDocumentDidChangeNotification;
const TextDocumentDidSaveNotification = text_document.TextDocumentDidSaveNotification;
const HoverRequest = hover.HoverRequest;
const CompletionRequest = completion.CompletionRequest;

const log = std.log.scoped(.main);
pub const std_options: std.Options = .{
    .logFn = logFn,
};

var log_stderr: bool = true;
var log_file: ?std.fs.File = null;

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    var buffer: [64384]u8 = undefined;
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

    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const env = try std.process.getEnvMap(allocator);
    const home_dir = env.get("HOME");
    if (home_dir) |home| {
        const slices: [2][]const u8 = .{ home, "/.local/state/dbx-ls" };
        const path = try std.mem.concat(allocator, u8, &slices);
        std.fs.makeDirAbsolute(path) catch |err| {
            if (err != error.PathAlreadyExists) {
                return err;
            }
        };
        const log_file_path = try std.mem.concat(allocator, u8, &.{ path, "/log.txt" });
        log_file = try std.fs.cwd().createFile(log_file_path, .{ .truncate = false });
    }
    defer log_file.?.close();

    var args = try std.process.ArgIterator.initWithAllocator(allocator);
    defer args.deinit();

    _ = args.next();
    var arguments = std.ArrayList([:0]const u8).init(allocator);
    defer arguments.deinit();
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

    var state = State.init(&arena);

    const json_opts: std.json.ParseOptions = .{ .ignore_unknown_fields = true };

    while (true) {
        const header = try protocol.LSPHeader.parse(reader);
        const json_message = try allocator.alloc(u8, header.content_length);

        try reader.readNoEof(json_message);

        const method = try rpc.parseMethod(arena.allocator(), json_message);
        log.debug("method: {s}", .{method});
        if (std.mem.eql(u8, method, "initialize")) {
            const init_request = try std.json.parseFromSliceLeaky(
                initialize.InitializeRequest,
                allocator,
                json_message,
                json_opts,
            );
            state.setWorkspace(init_request.params.workspaceFolders);
            try analyze_project.scan(
                allocator,
                &state,
                init_request.params.workspaceFolders.?[0].name,
            );
            std.debug.print("{s}\n", .{state});
            const response = try rpc.encodeMessage(
                allocator,
                initialize.NewInitializeResponse(init_request.id),
            );
            defer allocator.free(response);
            try stdout.print("{s}", .{response});
        } else if (std.mem.eql(u8, method, "textDocument/didOpen")) {
            const open_request = try std.json.parseFromSliceLeaky(
                TextDocumentDidOpenNotification,
                allocator,
                json_message,
                json_opts,
            );
            const document = open_request.params.textDocument;
            std.debug.print("didOpen: {?s}", .{document.languageId});
            try state.documents.put(std.mem.trim(u8, document.uri, "\n"), document);
            try handle_document(allocator, stdout, &state, document);
        } else if (std.mem.eql(u8, method, "textDocument/didChange")) {
            const change_request = try std.json.parseFromSliceLeaky(
                TextDocumentDidChangeNotification,
                arena.allocator(),
                json_message,
                json_opts,
            );
            log.debug("document did change: {any}", .{change_request});
            const document = text_document.TextDocumentItem{
                .uri = std.mem.trim(u8, change_request.params.textDocument.uri, "\n"),
                .languageId = change_request.params.textDocument.languageId orelse getLanguageId(change_request.params.textDocument.uri),
                .version = change_request.params.textDocument.version,
                .text = change_request.params.contentChanges[0].text,
            };
            try state.documents.put(std.mem.trim(u8, document.uri, "\n"), document);
        } else if (std.mem.eql(u8, method, "textDocument/didSave")) {
            log.debug("did save payload: {s}", .{json_message});
            const save_request = try std.json.parseFromSliceLeaky(
                TextDocumentDidSaveNotification,
                arena.allocator(),
                json_message,
                json_opts,
            );
            if (isYaml(save_request.params.textDocument.uri)) {
                state.refresh();
                try analyze_project.scan(
                    allocator,
                    &state,
                    state.workspace.?,
                );
            } else {
                const document = state.documents.get(save_request.params.textDocument.uri);
                if (document) |doc| {
                    try handle_document(allocator, stdout, &state, doc);
                }
            }
        } else if (std.mem.eql(u8, method, "textDocument/hover")) {
            const hover_request = try std.json.parseFromSliceLeaky(
                HoverRequest,
                arena.allocator(),
                json_message,
                json_opts,
            );

            const uri = hover_request.params.textDocument.uri;
            const notebook = state.documents.get(uri);
            if (notebook == null) {
                continue;
            }
            const content = notebook.?.text.?;

            const hover_result = try hover_analyzer.process(
                allocator,
                &state,
                uri,
                content,
                hover_request.params.position.line,
            );
            defer allocator.free(hover_result);
            const response = try rpc.encodeMessage(
                arena.allocator(),
                hover.NewHoverResponse(hover_request.id, hover_result),
            );
            defer allocator.free(response);
            try stdout.print("{s}", .{response});
        } else if (std.mem.eql(u8, method, "textDocument/completion")) {
            const completion_request = try std.json.parseFromSliceLeaky(
                CompletionRequest,
                arena.allocator(),
                json_message,
                json_opts,
            );
            log.debug("{any}", .{completion_request});
            const document = state.documents.get(std.mem.trim(u8, completion_request.params.textDocument.uri, "\n")) orelse {
                log.err("Document not found: {s}", .{completion_request.params.textDocument.uri});
                return;
            };
            const completion_result = try completion_analyzer.process(allocator, &state, completion_request, document.text.?);
            const response = try rpc.encodeMessage(allocator, completion_result);
            defer allocator.free(response);
            log.debug("completion result: {s}", .{response});
            try stdout.print("{s}", .{response});
        }
    }
}

fn handle_document(allocator: std.mem.Allocator, writer: anytype, state: *State, document: text_document.TextDocumentItem) !void {
    log.debug("document: {s} {?s}", .{ document.uri, document.languageId });
    if (std.mem.eql(u8, document.languageId orelse "", "python")) {
        const parsed_diagnostics = diagnostics.parse_notebook(
            allocator,
            state,
            document.uri,
            document.text.?,
        ) catch |err| {
            if (err == error.NotANotebookDocument) {
                return;
            } else {
                return err;
            }
        };
        defer allocator.free(parsed_diagnostics);
        const response = try rpc.encodeMessage(
            allocator,
            try lsp_diagnostics.NewDiagnosticsResponse(document.uri, parsed_diagnostics),
        );
        defer allocator.free(response);
        log.debug("Send diagnostics: {s}", .{response});
        try writer.print("{s}", .{response});
    }
}

fn isYaml(path: []const u8) bool {
    const ext = std.fs.path.extension(path);
    return std.mem.eql(u8, ext, ".yml") or std.mem.eql(u8, ext, ".yaml");
}

fn getLanguageId(uri: []const u8) ?[]const u8 {
    const ext = std.fs.path.extension(uri);
    if (std.mem.eql(u8, ext, ".py")) return "python";
    if (isYaml(uri)) return "yaml";
    return null;
}
