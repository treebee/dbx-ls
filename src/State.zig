const std = @import("std");
const text_document = @import("lsp/text_document.zig");

const lsp_initialize = @import("lsp/initialize.zig");
const log = std.log.scoped(.state);

const State = @This();

arena: *std.heap.ArenaAllocator,
allocator: std.mem.Allocator,
config_files: std.hash_map.StringHashMap(VariableMap),
jobs: std.hash_map.StringHashMap(Job),
documents: std.hash_map.StringHashMap(text_document.TextDocumentItem),
variables: std.hash_map.StringHashMap(Variable),
workspace: ?[]const u8,
targets: std.hash_map.StringHashMap(Target),

pub fn init(arena: *std.heap.ArenaAllocator) State {
    const allocator = arena.allocator();
    return State{
        .arena = arena,
        .allocator = allocator,
        .variables = std.hash_map.StringHashMap(Variable).init(allocator),
        .config_files = std.hash_map.StringHashMap(VariableMap).init(allocator),
        .jobs = std.hash_map.StringHashMap(Job).init(allocator),
        .workspace = null,
        .targets = std.hash_map.StringHashMap(Target).init(allocator),
        .documents = std.hash_map.StringHashMap(text_document.TextDocumentItem).init(allocator),
    };
}

pub fn refresh(self: *State) void {
    self.variables.clearAndFree();
    self.config_files.clearAndFree();
    self.jobs.clearAndFree();
    self.targets.clearAndFree();
}

pub const DevMode = enum {
    development,
    production,
};

pub const Target = struct {
    mode: DevMode,
    variables: ValueMap,
};

pub const NotebookTask = struct {
    key: []const u8,
    notebook_uri: []const u8,
    base_parameters: ValueMap,
    job: []const u8,
};

pub const Job = struct {
    parameters: ValueMap,
    tasks: std.StringHashMap(NotebookTask),
};

const VariableMap = std.StringHashMap(Variable);
pub const ValueMap = std.StringHashMap(Value);

pub const Value = union(enum) {
    string: []const u8,
    integer: i64,
    boolean: bool,
    none,

    pub fn format(
        self: Value,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        switch (self) {
            .string => try writer.print("{s}", .{self.string}),
            .integer => try writer.print("{d}", .{self.integer}),
            .none => try writer.print("null", .{}),
            .boolean => try writer.print("{}", .{self.boolean}),
        }

        try writer.writeAll("");
    }
};

pub const Variable = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    default: ?Value = null,

    pub fn format(
        self: Variable,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("\ndefault: {s}\n\n", .{self.default orelse .none});
        try writer.print("----------------------------------\n", .{});
        try writer.print("{s}", .{self.description orelse ""});

        try writer.writeAll("");
    }
};

pub fn setWorkspace(self: *State, workspace: ?[]lsp_initialize.WorkspaceFolder) void {
    if (workspace) |ws| {
        self.workspace = ws[0].name;
        log.info("Updated workspace: {s}", .{self.workspace.?});
    }
}

pub fn resolveParameter(
    self: *const State,
    task: *const NotebookTask,
    param_name: []const u8,
    target_name: ?[]const u8,
) ?Value {
    var current_param_name = param_name;
    var maybe_value = task.base_parameters.get(current_param_name);

    const job = self.jobs.get(task.job);
    if (maybe_value == null) {
        if (job == null) {
            log.err("Job '{s}' not found but referenced by task '{s}'", .{ task.job, task.key });
            return null;
        }
        maybe_value = job.?.parameters.get(current_param_name);
        log.debug("maybe_value: {?s}", .{maybe_value});
        if (maybe_value == null) return null;
    }

    if (maybe_value.? == .string and std.mem.containsAtLeast(u8, maybe_value.?.string, 1, "${var.")) {
        var buffer: std.ArrayList(u8) = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        var val = maybe_value.?.string;
        std.debug.print("val = {s}\n", .{val});
        var i = std.mem.indexOf(u8, val, "${var.");
        while (i != null) {
            if (i.? != 0) {
                buffer.appendSlice(val[0..i.?]) catch {
                    break;
                };
            }
            val = val[i.? + 6 .. val.len];
            std.debug.print("val = {s}\n", .{val});
            if (std.mem.indexOf(u8, val, "}")) |j| {
                current_param_name = val[0..j];
                const global_var = self.variables.get(current_param_name);
                if (target_name) |t_name| {
                    if (self.targets.get(t_name)) |target_config| {
                        if (target_config.variables.get(current_param_name)) |target_override| {
                            if (target_override == .string) {
                                buffer.appendSlice(target_override.string) catch return null;
                            }
                        } else if (global_var) |v| {
                            if (v.default) |def| {
                                if (def == .string) {
                                    buffer.appendSlice(def.string) catch return null;
                                }
                            }
                        }
                    } else {
                        log.warn("Target '{s}' specified but not found in state.", .{t_name});
                    }
                } else {
                    if (global_var) |v| {
                        if (v.default) |def| {
                            if (def == .string) {
                                buffer.appendSlice(def.string) catch return null;
                            }
                        }
                    }
                }
            }
            val = val[current_param_name.len + 1 .. val.len];
            i = std.mem.indexOf(u8, val, "${var.");
        }
        if (val.len > 0) {
            buffer.appendSlice(val) catch return null;
        }

        const result = buffer.toOwnedSlice() catch {
            return null;
        };
        std.debug.print("resolved: {s}", .{result});
        log.debug("Resolved parameter '{s}' for task '{s}' (target: {?s}) -> {?s}", .{
            param_name, task.key, target_name, maybe_value,
        });
        return Value{ .string = result };
    }

    return maybe_value;
}

pub fn format(
    self: State,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    var variable_iter = self.variables.keyIterator();
    while (variable_iter.next()) |variable| {
        try writer.print("{s}:\n\tdescription: {s}\n\tdefault: {s}\n\ttargets: ", .{
            variable.*,
            self.variables.get(variable.*).?.description orelse "null",
            self.variables.get(variable.*).?.default orelse .none,
        });
    }
    try writer.writeAll("");
}

test "resolveParameter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var state = State.init(&arena);
    try state.variables.put("test_variable", Variable{
        .name = "test_variable",
        .description = "This is a test variable.",
        .default = State.Value{ .string = "some_value" },
    });
    var job_parameters = ValueMap.init(arena.allocator());
    try job_parameters.put("test_var", Value{ .string = "${var.test_variable}" });
    const task = State.NotebookTask{
        .key = "test_task",
        .base_parameters = ValueMap.init(arena.allocator()),
        .job = "test_job",
        .notebook_uri = "file://notebook.py",
    };
    var job_tasks = std.StringHashMap(State.NotebookTask).init(arena.allocator());
    try job_tasks.put("test_task", task);
    const job = State.Job{
        .parameters = job_parameters,
        .tasks = job_tasks,
    };
    try state.jobs.put("test_job", job);
    const maybe_value = State.resolveParameter(&state, &task, "test_var", null);
    try std.testing.expect(maybe_value != null);
    try std.testing.expect(maybe_value.? == .string);
    try std.testing.expectEqualStrings("some_value", maybe_value.?.string);
}

test "resolve mulitple" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var state = State.init(&arena);
    try state.variables.put("test_variable", Variable{
        .name = "test_variable",
        .description = "This is a test variable.",
        .default = State.Value{ .string = "some_value" },
    });
    try state.variables.put("a_test_variable", Variable{
        .name = "a_test_variable",
        .description = "This is another test variable.",
        .default = State.Value{ .string = "other_value" },
    });
    var job_parameters = ValueMap.init(arena.allocator());
    try job_parameters.put("test_var", Value{ .string = "foo_${var.test_variable}_${var.a_test_variable}_bar" });
    const task = State.NotebookTask{
        .key = "test_task",
        .base_parameters = ValueMap.init(arena.allocator()),
        .job = "test_job",
        .notebook_uri = "file://notebook.py",
    };
    var job_tasks = std.StringHashMap(State.NotebookTask).init(arena.allocator());
    try job_tasks.put("test_task", task);
    const job = State.Job{
        .parameters = job_parameters,
        .tasks = job_tasks,
    };
    try state.jobs.put("test_job", job);
    const maybe_value = State.resolveParameter(&state, &task, "test_var", null);
    try std.testing.expect(maybe_value != null);
    try std.testing.expect(maybe_value.? == .string);
    try std.testing.expectEqualStrings("foo_some_value_other_value_bar", maybe_value.?.string);
}
