const text_document = @import("text_document.zig");

pub const HoverRequest = struct {
    id: usize,
    jsonrpc: []const u8,
    method: []const u8,
    params: HoverParams,

    pub const HoverParams = struct {
        textDocument: text_document.TextDocumentIdentifier,
        position: text_document.Position,
    };
};

pub const HoverResult = struct {
    contents: []const u8,
};

pub const HoverResponse = struct {
    id: usize,
    result: HoverResult,
};

pub fn NewHoverResponse(id: usize, value: []const u8) HoverResponse {
    return HoverResponse{
        .id = id,
        .result = HoverResult{ .contents = value },
    };
}
