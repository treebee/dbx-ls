const std = @import("std");
const dbxls = @import("dbx-ls");
const State = @import("dbx-ls").State;
const analyze_project = dbxls.analyze_project;

test "scanProject" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const path = try std.fs.cwd().realpathAlloc(arena.allocator(), "tests/sample_project");
    const workspace = path;
    var state = State.init(&arena);
    try analyze_project.scan(arena.allocator(), &state, workspace);
    try std.testing.expectEqual(7, state.variables.count());
    const variables: [7][]const u8 = .{
        "variable1",
        "variable2",
        "variable3",
        "variable4",
        "variable5",
        "connection",
        "environment",
    };
    for (variables) |variable| {
        try std.testing.expect(state.variables.get(variable) != null);
    }
}
