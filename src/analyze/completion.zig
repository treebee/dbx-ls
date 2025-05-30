const std = @import("std");
const completion = @import("../lsp/completion.zig");
const State = @import("../State.zig");

const log = std.log.scoped(.completion_analyzer);

/// generates a list of completions of available variables in a databricks
/// job definition
pub fn process(
    allocator: std.mem.Allocator,
    state: *State,
    request: completion.CompletionRequest,
    source: []const u8,
) !?completion.CompletionResponse {
    const position = request.params.position;
    var lines = std.mem.splitSequence(u8, source, "\n");
    var i: usize = 0;
    while (lines.next()) |line| : (i += 1) {
        if (i != position.line) {
            continue;
        }
        if (line.len < position.character - 1) {
            log.warn("Completion failed for line '{s}', position: '{}'", .{ line, position.character });
            return completion.NewCompletionResponse(request.id, null);
        }
        if (std.mem.eql(u8, line[position.character - 1 - 5 .. position.character - 1], "${var")) {
            var items = std.ArrayList(completion.CompletionItem).init(allocator);
            var var_iter = state.variables.iterator();
            while (var_iter.next()) |variable| {
                try items.append(completion.CompletionItem{
                    .label = variable.key_ptr.*,
                    .detail = "",
                    .documentation = variable.value_ptr.*.description,
                });
            }
            return completion.NewCompletionResponse(request.id, items.items);
        }
        log.info("line: {s}: current char: {c}", .{ line, line[position.character - 1] });
        break;
    }
    return completion.NewCompletionResponse(request.id, null);
}
