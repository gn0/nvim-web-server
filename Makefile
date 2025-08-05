.PHONY: build lint luadoc test

build: lint test luadoc

lint:
	luacheck lua/web-server.lua

test:
	$(foreach x,djotter path request string, \
		nvim --headless --clean --noplugin -u scripts/minimal_init.vim \
			-l tests/$(x).lua &&) true

luadoc: luadoc/index.html

luadoc/index.html: lua/web-server.lua
	[ -d luadoc ] || mkdir luadoc
	ldoc --all --verbose --dir luadoc $<

.PHONY: clean
clean:
	-rm -rf luadoc/
