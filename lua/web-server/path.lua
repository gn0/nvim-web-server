--- Normalizes paths.
-- @module web-server.path
-- @author Gábor Nyéki
-- @license MIT
--

--- Module class.
-- @field value (string) normalized path
-- @field[opt] query_string (string) the part of the requested path that
--     begins with a `?`
-- @usage
-- -- A path with extra slashes and without a query string.
-- --
--
-- local path_a = Path.new("/foo//bar/")
--
-- assert(path_a.value == "/foo/bar")
-- assert(not path_a.query_string)
--
-- -- A path with a query string.
-- --
--
-- local path_b = Path.new("/foo?bar=baz&asd=f")
--
-- assert(path_b.value == "/foo")
-- assert(path_b.query_string == "?bar=baz&asd=f")
--
local M = {}

function M.new(raw)
    local query_string = raw:match("?.*")
    local normalized = raw:gsub("?.*", ""):gsub("/+", "/")

    if normalized ~= "/" then
        normalized = normalized:gsub("/$", "")
    end

    return setmetatable({
        value = normalized,
        query_string = query_string
    }, {
        __index = M
    })
end

return M
