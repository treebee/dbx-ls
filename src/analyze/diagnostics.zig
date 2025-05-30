const std = @import("std");
const log = std.log.scoped(.parse_notebook);
const diagnostics = @import("../lsp/diagnostics.zig");
const text_document = @import("../lsp/text_document.zig");
const State = @import("../State.zig");

fn writeLine(writer: anytype, line: []const u8) !void {
    try writer.print("{s}", .{line});
    try writer.writeByte('\n');
}

pub fn parse_notebook(
    allocator: std.mem.Allocator,
    state: *State,
    uri: []const u8,
    content: []const u8,
) ![]diagnostics.Diagnostic {
    var line_iter = std.mem.splitSequence(u8, content, "\n");
    const first = line_iter.next().?;
    if (!std.mem.startsWith(u8, first, "# Databricks notebook source")) {
        log.warn("Not a databricks notebook: {s}", .{uri});
        return error.NotANotebookDocument;
    }

    var diagnostic_items = std.ArrayList(diagnostics.Diagnostic).init(allocator);

    var line_idx: usize = 1;
    while (line_iter.next()) |line| : (line_idx += 1) {
        checkparam: {
            if (!std.mem.startsWith(u8, line, "#") and
                std.mem.containsAtLeast(u8, line, 1, ".widgets.text") or
                std.mem.containsAtLeast(u8, line, 1, ".widgets.dropdown"))
            {
                var split = std.mem.splitSequence(u8, line, "\"");
                const first_part = split.first();
                const variable = split.next();
                if (variable == null) {
                    break :checkparam;
                }
                var jobs_iter = state.jobs.valueIterator();
                while (jobs_iter.next()) |job| {
                    var task_iter = job.tasks.valueIterator();
                    while (task_iter.next()) |task| {
                        if (!std.mem.eql(u8, uri, task.notebook_uri)) {
                            continue;
                        }
                        const value = state.resolveParameter(task, variable.?, null);
                        if (value != null) {
                            continue;
                        }
                        try diagnostic_items.append(diagnostics.Diagnostic{
                            .range = text_document.Range{
                                .start = .{ .line = line_idx, .character = first_part.len + 1 },
                                .end = .{ .line = line_idx, .character = first_part.len + 1 + variable.?.len },
                            },
                            .message = try std.fmt.allocPrint(
                                allocator,
                                "[unset-param] Parameter not configured for at least one task.",
                                .{},
                            ),
                            .severity = 3,
                            .code = try std.fmt.allocPrint(allocator, "{s}", .{task.key}),
                        });
                    }
                }
            }
        }
    }
    const c = try std.fmt.allocPrint(allocator, "{s}", .{content});
    log.info("Putting notebook with uri: {s}", .{uri});
    const u = try std.fmt.allocPrint(allocator, "{s}", .{uri});
    const document = text_document.TextDocumentItem{
        .uri = u,
        .languageId = "python",
        .text = c,
        .version = 0,
    };
    try state.documents.put(u, document);
    return diagnostic_items.items;
}

pub inline fn isMagic(line: []const u8) bool {
    return std.mem.startsWith(u8, line, "# MAGIC");
}

pub inline fn isShell(line: []const u8) bool {
    return std.mem.startsWith(u8, line, "# MAGIC %sh");
}

pub inline fn isMarkdown(line: []const u8) bool {
    return std.mem.startsWith(u8, line, "# MAGIC %md");
}

pub inline fn isCommand(line: []const u8) bool {
    return std.mem.startsWith(u8, line, "# COMMAND ----------");
}
