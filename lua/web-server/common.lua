
local M = {}

function M.cmd_error(...)
    vim.api.nvim_echo({{ string.format(...) }}, true, { err = true })
end

return M
