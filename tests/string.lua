local M = require("web-server")
local escape = M.internal.escape
local truncate = M.internal.truncate

assert(escape("") == "")
assert(escape(" ") == " ")
assert(escape("\n") == "\\n")
assert(escape("\r\n") == "\\r\\n")
assert(escape("foo bar") == "foo bar")
assert(escape("foo\nbar") == "foo\\nbar")
assert(escape("foo\r\nbar") == "foo\\r\\nbar")

assert(truncate("foo", 4) == "foo")
assert(truncate("foo", 3) == "foo")
assert(truncate("foo", 2) == "fo...")
