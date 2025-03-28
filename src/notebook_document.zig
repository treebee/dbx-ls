pub const NotebookCell = struct {
    language: []const u8,
    text: []const u8,

    pub fn init(language: []const u8, text: []const u8) @This() {
        return NotebookCell{ .language = language, .text = text };
    }
};

pub const NotebookDocument = struct {
    uri: []const u8,
    version: usize,
};
