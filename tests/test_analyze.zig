const std = @import("std");
const dbxls = @import("dbx-ls");
const State = @import("dbx-ls").state.State;
const analyze = dbxls.analyze;
const WorkspaceFolder = dbxls.initialize.WorkspaceFolder;

test "scan project" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const path = try std.fs.cwd().realpathAlloc(arena.allocator(), "tests/sample_project");
    std.debug.print("sample_project: {s}\n", .{path});
    const workspace = WorkspaceFolder{ .name = path, .uri = "" };
    var state = State.init(arena.allocator());
    try analyze.scan_project(arena.allocator(), &state, workspace);
    try std.testing.expectEqual(4, state.project_config.variables.count());
    const variables: [4][]const u8 = .{ "variable1", "variable2", "variable3", "variable4" };
    for (variables) |variable| {
        try std.testing.expect(state.project_config.variables.get(variable) != null);
    }
    // This should actually be '"99"', not '99'
    try std.testing.expectEqual(99, state.project_config.variables.get("variable3").?.targets.get("production").?.integer);
}
