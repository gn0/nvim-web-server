--- Converts Djot markup to HTML.  It wraps John MacFarlane's
-- "djot.lua".
-- @module web-server.djotter
-- @author Gábor Nyéki
-- @license MIT
--

local djot = require("web-server.djot")
local cmd_error = require("web-server.common").cmd_error

--- Module class.
-- @field template (string)
local M = {}

function M.new()
    local state = {
        template = (
            "<html>" ..
            "<head>" ..
            "<title>{{ title }}</title>" ..
            "</head>" ..
            "<body>{{ content }}</body>" ..
            "</html>"
        )
    }
    return setmetatable(state, { __index = M })
end

--- Converts the input string from Djot to HTML.
-- @param input (string)
-- @return (string)
function M:to_html(input)
    local ast = djot.parse(input, false, function(warning)
        cmd_error(
            "Djot parse error: %s at byte position %d",
            warning.message,
            warning.pos
        )
    end)

    local content = djot.render_html(ast)
    local content_escaped = content:gsub("%%", "%%%%")

    local title = content:match("<h[1-9]>([^<]*)</h[1-9]>") or ""
    local title_escaped = title:gsub("%%", "%%%%")

    return (
        self.template
        :gsub("{{ title }}", title_escaped)
        :gsub("{{ content }}", content_escaped)
    )
end

return M
