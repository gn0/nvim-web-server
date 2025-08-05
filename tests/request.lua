local M = require("web-server")
local process_request_line = M.internal.process_request_line

for _, input in ipairs({"/", "/foo", "/foo/bar", "/foo?bar=baz"}) do
    local _, method, path, proto, bad = process_request_line(
        "GET " .. input .. " HTTP/1.1\n\n"
    )
    assert(method == "GET", "wrong method for " .. input)
    assert(path == input, "wrong path for " .. input)
    assert(proto == "HTTP/1.1", "wrong proto for " .. input)
    assert(not bad, "wrong bad for " .. input)
end

for _, input in ipairs({
    "GET",
    "GET /",
    "GET / HTTP/1.1 foo",
    "POST / HTTP/1.1",
    "DELETE / HTTP/1.1",
}) do
    local _, _, _, _, bad = process_request_line(input .. "\n\n")
    assert(bad, "wrong bad for '" .. input .. "'")
end

local process_request_header = M.internal.process_request_header

for i, input in ipairs({
    "GET / HTTP/1.1\nIf-None-Match: foo-bar\n\n",
    "GET / HTTP/1.1\nIf-None-Match: \"foo-bar\"\n\n",
    "GET / HTTP/1.1\nHost: foo\nIf-None-Match: foo-bar\n\n",
    "GET / HTTP/1.1\nHost: foo\nIf-None-Match: \"foo-bar\"\n\n",
    "GET / HTTP/1.1\nHost: foo\nIf-None-Match: foo-bar\n"
    .. "Connection: keep-alive\n\n",
    "GET / HTTP/1.1\nHost: foo\nIf-None-Match: \"foo-bar\"\n"
    .. "Connection: keep-alive\n\n",
}) do
    local result = process_request_header(input)
    assert(result == "foo-bar", "wrong for #" .. i)
end

for i, input in ipairs({
    "GET / HTTP/1.1\n\n",
    "GET / HTTP/1.1\nHost: foo\n\n",
    "GET / HTTP/1.1\nHost: foo\nConnection: keep-alive\n\n",
}) do
    assert(not process_request_header(input), "wrong for #" .. i)
end
