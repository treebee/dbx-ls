
build:
	zig build

test:
	zig build test --summary all

.PHONY: build test
