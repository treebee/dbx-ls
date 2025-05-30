const std = @import("std");

const text_document = @import("text_document.zig");

pub const CompletionRequest = struct {
    id: usize,
    jsonrpc: []const u8,
    method: []const u8,
    params: CompletionParams,

    pub const CompletionParams = struct {
        textDocument: text_document.TextDocumentIdentifier,
        position: text_document.Position,
    };
};

pub const CompletionItem = struct {
    label: []const u8,
    detail: ?[]const u8,
    documentation: ?[]const u8 = "",
    kind: ?u8 = 6,
};

pub const CompletionResponse = struct {
    id: usize,
    result: CompletionList,

    pub const CompletionList = struct {
        isIncomplete: bool = false,
        items: ?[]const CompletionItem,
    };
};

pub fn NewCompletionResponse(id: usize, items: ?[]CompletionItem) CompletionResponse {
    return CompletionResponse{
        .id = id,
        .result = .{
            .items = items,
        },
    };
}
