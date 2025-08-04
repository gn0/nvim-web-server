.PHONY: luadoc
luadoc: luadoc/index.html

luadoc/index.html: lua/web-server.lua
	[ -d luadoc ] || mkdir luadoc
	ldoc --all --verbose --dir luadoc $<

.PHONY: clean
clean:
	-rm -rf luadoc/
