
build:
	zig build

test:
	zig build test --summary all

release:
	zig build --release=fast

install: release
	cp -f zig-out/bin/dbx-ls ~/.local/bin/.

.PHONY: build release test
