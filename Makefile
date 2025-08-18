MODULES = init djotter path
TESTS = djotter path request server string

.PHONY: build lint luadoc test

build: lint test luadoc

lint:
	$(foreach x,$(MODULES), \
		luacheck lua/web-server/$(x).lua &&) true

test:
	$(foreach x,$(TESTS), \
		nvim --headless --clean --noplugin -u scripts/minimal_init.vim \
			-l tests/$(x).lua &&) true

luadoc: $(foreach x,init djotter path,luadoc/$(x).html)

luadoc/%.html: lua/web-server/%.lua
	[ -d luadoc ] || mkdir luadoc
	ldoc \
		--all \
		--verbose \
		--dir luadoc \
		--output $(basename $(notdir $@)) \
		$<

.PHONY: clean
clean:
	-rm -rf luadoc/
