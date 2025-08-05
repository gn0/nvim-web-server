local M = require("web-server")
local f = M.internal.Path.new

for i, case in ipairs({
    { path = "/", normalized = "/", query_string = nil },
    { path = "//", normalized = "/", query_string = nil },
    { path = "/foo", normalized = "/foo", query_string = nil },
    { path = "//foo", normalized = "/foo", query_string = nil },
    { path = "/foo/", normalized = "/foo", query_string = nil },
    { path = "/foo//", normalized = "/foo", query_string = nil },
    { path = "/?", normalized = "/", query_string = "?" },
    { path = "/?foo", normalized = "/", query_string = "?foo" },
    { path = "/?foo=bar", normalized = "/", query_string = "?foo=bar" },
    { path = "/?foo&bar", normalized = "/", query_string = "?foo&bar" },
    { path = "/foo?", normalized = "/foo", query_string = "?" },
    { path = "/foo?bar", normalized = "/foo", query_string = "?bar" },
    { path = "/foo/?", normalized = "/foo", query_string = "?" },
    { path = "/foo/?bar", normalized = "/foo", query_string = "?bar" },
}) do
    local a = case.path
    local b = case.normalized
    local c = case.query_string

    assert(f(a).value == b, a .. " not -> " .. b)
    assert(
        f(a).query_string == c,
        string.format("%s not -> query_string = %s", a, c)
    )
end
