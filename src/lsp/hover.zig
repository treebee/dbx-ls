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
