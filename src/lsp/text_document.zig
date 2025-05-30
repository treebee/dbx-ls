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

pub const TextDocumentDidSaveNotification = struct {
    jsonrpc: []const u8,
    method: []const u8,
    params: DidSaveTextDocumentParams,

    pub const DidSaveTextDocumentParams = struct {
        textDocument: TextDocumentIdentifier,
        text: ?[]const u8,
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
