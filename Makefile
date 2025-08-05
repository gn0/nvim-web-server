.PHONY: build lint luadoc

build: lint luadoc

lint:
	luacheck lua/web-server.lua

luadoc: luadoc/index.html

luadoc/index.html: lua/web-server.lua
	[ -d luadoc ] || mkdir luadoc
	ldoc --all --verbose --dir luadoc $<

.PHONY: clean
clean:
	-rm -rf luadoc/
