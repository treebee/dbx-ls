const std = @import("std");
const State = @import("../State.zig");
const HoverRequest = @import("../lsp/hover.zig").HoverRequest;

const log = std.log.scoped(.analyze_hover);

/// generates hover information for parameters used via databricks widgets,
/// e.g. 'dbutils.text'
/// In case the notebook is used by multiple tasks, the configured values for
/// all of those tasks and all the different targets are resolved.
pub fn process(
    allocator: std.mem.Allocator,
    state: *State,
    uri: []const u8,
    content: []const u8,
    line_number: usize,
) ![]const u8 {
    var line_iter = std.mem.splitSequence(u8, content, "\n");
    var line: ?[]const u8 = null;
    for (0..line_number + 1) |idx| {
        _ = idx;
        line = line_iter.next();
        if (line == null) return "";
    }
    if (!std.mem.containsAtLeast(u8, line.?, 1, ".widgets.")) {
        return "";
    }
    var split = std.mem.splitSequence(u8, line.?, "\"");
    _ = split.first();
    const variable = split.next();
    if (variable == null) {
        return "";
    }

    var response: ?[]const u8 = null;

    var jobs_iter = state.jobs.iterator();
    while (jobs_iter.next()) |job| {
        var tasks_iter = job.value_ptr.tasks.valueIterator();
        while (tasks_iter.next()) |task| {
            if (!std.mem.eql(u8, task.*.notebook_uri, uri)) {
                continue;
            }
            const param_str = state.resolveParameter(
                task,
                variable.?,
                null,
            );
            var p: []const u8 = "";
            if (param_str != null) {
                p = switch (param_str.?) {
                    .string => param_str.?.string,
                    .boolean => try std.fmt.allocPrint(allocator, "{?}", .{param_str.?.boolean}),
                    .integer => try std.fmt.allocPrint(allocator, "{?}", .{param_str.?.integer}),
                    .none => "",
                };
            }
            response = try std.mem.concat(
                allocator,
                u8,
                &[_][]const u8{ response orelse "", job.key_ptr.*, ": ", task.*.key, "\n\t", p, "\n\n" },
            );
            var target_iter = state.targets.iterator();
            while (target_iter.next()) |target| {
                const target_var = state.resolveParameter(
                    task,
                    variable.?,
                    target.key_ptr.*,
                );
                const target_str = try std.fmt.allocPrint(
                    allocator,
                    "\t{s}: {?s}\n",
                    .{ target.key_ptr.*, target_var },
                );
                response = try std.mem.concat(
                    allocator,
                    u8,
                    &[_][]const u8{ response.?, target_str },
                );
            }
            response = try std.mem.concat(
                allocator,
                u8,
                &[_][]const u8{ response.?, "\n" },
            );
        }
    }
    if (state.variables.get(variable.?)) |state_var| {
        if (state_var.description) |description| {
            response = try std.mem.concat(
                allocator,
                u8,
                &[_][]const u8{ response.?, "\n------------\n", description },
            );
        }
    }
    return response orelse "";
}
