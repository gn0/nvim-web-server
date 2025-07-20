local djot = require("web-server.djot")

local Logger = {}

function Logger:new()
    local buf_id = vim.api.nvim_create_buf(true, true)
    local win_id = vim.api.nvim_open_win(buf_id, 0, { split = "above" })
    local state = { buf_id = buf_id, win_id = win_id, empty = true }
    return setmetatable(state, { __index = Logger })
end

function Logger:print(...)
    local message = string.format(...)

    vim.schedule(function()
        local line = (
            vim.fn.strftime("[%Y-%m-%d %H:%M:%S] ") .. message:escape()
        )

        vim.api.nvim_buf_set_lines(self.buf_id, -1, -1, true, { line })

        if self.empty then
            -- If the log buffer was empty, then the first message was
            -- appended to an empty line.  We want to delete that empty
            -- line.
            vim.api.nvim_buf_set_lines(self.buf_id, 0, 1, true, {})
            self.empty = false
        end
    end)
end

local log = nil

-- TODO Wrap network I/O calls in `pcall()` in case of failure?

local function create_server(host, port, on_connect)
    log:print("Initializing server at %s:%d.", host, port)

    local server = vim.uv.new_tcp()
    server:bind(host, port)
    server:listen(1024, function(error)
        assert(not error, error)

        local socket = vim.uv.new_tcp()
        server:accept(socket)

        on_connect(socket)
    end)
    return server
end

local Response = { status = nil, value = nil }

function Response:ok(proto, content_type, content)
    return setmetatable({
        status = 200,
        value = string.format(
            "%s 200 OK\n" ..
            "Server: nvim-web-server\n" ..
            "Content-Type: %s\n" ..
            "Content-Length: %d\n" ..
            "Connection: keep-alive\n" ..
            "\n" ..
            "%s\n",
            proto, content_type, content:len(), content
        )
    }, {
        __index = Response
    })
end

function Response:bad(proto)
    local content = (
        "<!DOCTYPE html>" ..
        "<html>" ..
        "<head><title>Bad Request</title></head>" ..
        "<body>" ..
        "<center><h1>Bad Request</h1></center>" ..
        "<hr>" ..
        "<center>nvim-web-server</center>" ..
        "</body>" ..
        "</html>" ..
        "\n"
    )

    return setmetatable({
        status = 400,
        value = (
            proto .. " 400 Bad Request\n" ..
            "Server: nvim-web-server\n" ..
            "Content-Type: text/html\n" ..
            "Content-Length: " .. content:len() .. "\n" ..
            "Connection: close\n" ..
            "\n" ..
            content
        )
    }, {
        __index = Response
    })
end

function Response:not_found(proto)
    local content = (
            "<!DOCTYPE html>" ..
            "<html>" ..
            "<head><title>Not Found</title></head>" ..
            "<body>" ..
            "<center><h1>Not Found</h1></center>" ..
            "<hr>" ..
            "<center>nvim-web-server</center>" ..
            "</body>" ..
            "</html>" ..
            "\n"
    )

    return setmetatable({
        status = 404,
        value = (
            proto .. " 404 Bad Request\n" ..
            "Server: nvim-web-server\n" ..
            "Content-Type: text/html\n" ..
            "Content-Length: " .. content:len() .. "\n" ..
            "Connection: keep-alive\n" ..
            "\n" ..
            content
        )
    }, {
        __index = Response
    })
end

local Routing = {}

function Routing:new()
    return setmetatable({
        paths = {}
    }, {
        __index = Routing
    })
end

function Routing:add_path(path, buf_id, content_type, content)
    if self.paths[path] then
        return false
    end

    self.paths[path] = {
        buf_id = buf_id,
        content_type = content_type,
        content = content
    }
    return true
end

function Routing:delete_path(path)
    self.paths[path] = nil
end

function Routing:has_path(path)
    return self.paths[path] ~= nil
end

function Routing:has_buf_id(buf_id)
    for _, value in pairs(self.paths) do
        if value.buf_id == buf_id then
            return true
        end
    end
    return false
end

function Routing:get_path_by_buf_id(buf_id)
    for path, value in pairs(self.paths) do
        if value.buf_id == buf_id then
            return path
        end
    end
    return nil
end

local routing = nil

local function process_request(chunk)
    local method = nil
    local path = nil
    local proto = nil
    local first_line = chunk:match("[^\r\n]*")
    local response = nil

    for index, word in ipairs(vim.split(first_line, "%s+")) do
        if index == 1 then
            method = word
        elseif index == 2 then
            path = word
        elseif index == 3 then
            proto = word
        else
            response = Response:bad(proto)
            break
        end
    end

    if proto == nil then
        response = Response:bad("HTTP/1.1")
    end

    if response == nil then
        if routing:has_path(path) then
            local value = routing.paths[path]

            response = Response:ok(
                proto,
                value.content_type,
                value.content
            )
        else
            response = Response:not_found(proto)
        end
    end

    return {
        proto = proto,
        request = first_line,
        response = response
    }
end

function string:truncate(max_len)
    if self:len() > max_len then
        return self:sub(1, max_len) .. "..."
    end

    return self
end

function string:escape()
    return self:gsub("\r", "\\r"):gsub("\n", "\\n")
end

local function cmd_error(...)
    vim.api.nvim_echo({{ string.format(...) }}, true, { err = true })
end

local function get_first_header(html)
    local snippet = html:match("<h[1-9]>[^<]*</h[1-9]>")
    if snippet then
        return snippet:sub(5, -6)
    end
    return nil
end

local function djot_to_html(input)
    local ast = djot.parse(input, false, function(warning)
        cmd_error(
            "Djot parse error: %s at byte position %d",
            warning.message,
            warning.pos
        )
    end)

    local body = "<body>" .. djot.render_html(ast) .. "</body>"
    local title = get_first_header(body) or ""

    return (
        "<html>" ..
        "<head>" ..
        "<title>" .. title .. "</title>" ..
        "</head>" ..
        body ..
        "</html>"
    )
end

local function ws_add_buffer(opts)
    if #opts.fargs == 0 or #opts.fargs > 2 then
        cmd_error("Usage: :WSAddBuffer <path> [content-type]")
        return
    end

    local path = opts.fargs[1]

    if not path:match("^/") then
        cmd_error("Path '%s' is not absolute.", path)
        return
    end

    local buf_id = vim.fn.bufnr()
    local content_type = opts.fargs[2] or "text/djot"
    local content = nil

    if not content_type:match("^text/") then
        local file_path = vim.api.nvim_buf_get_name(0)
        content = io.open(file_path):read("*a")
    else
        content = table.concat(
            vim.api.nvim_buf_get_lines(buf_id, 0, -1, true),
            "\n"
        )
    end

    if content_type == "text/djot" then
        content = djot_to_html(content)
        content_type = "text/html"
    end

    if routing:has_path(path) then
        cmd_error("Path '%s' already exists.", path)
        return
    else
        local buf_path = routing:get_path_by_buf_id(buf_id)
        if buf_path then
            cmd_error("Buffer is already bound to path '%s'.", buf_path)
            return
        end
    end

    routing:add_path(path, buf_id, content_type, content)

    -- TODO Set up event handler to update `content` when the buffer
    -- changes.
end

local function ws_delete_path(opts)
    if #opts.fargs ~= 1 then
        cmd_error("Usage: :WSDeletePath <path>")
        return
    end

    local path = opts.fargs[1]

    if not routing:has_path(path) then
        cmd_error("Path '%s' does not exist.", path)
    else
        routing:delete_path(path)
    end
end

local function ws_paths()
    for path, value in pairs(routing.paths) do
        log:print(
            "Path '%s' is routed to %s (length %d).",
            path,
            value.content_type,
            value.content:len()
        )
    end
end

local M = {}

-- TODO Log into a file specified by the user.  `M.init` should accept a
-- table of options, with the log filename being an optional thing that
-- they can specify.
function M.init()
    log = Logger:new()
    routing = Routing:new()

    local new_cmd = vim.api.nvim_create_user_command
    new_cmd("WSAddBuffer", ws_add_buffer, { nargs = "*" })
    new_cmd("WSDeletePath", ws_delete_path, { nargs = "*" })
    new_cmd("WSPaths", ws_paths, { nargs = 0 })

    -- TODO Add a command to set a CSS style file.

    local server = create_server("127.0.0.1", 4999, function(socket)
        local request = ""
        local result = nil

        socket:read_start(function(error, chunk)
            if error then
                log:print("Read error: '%s'.", error)
                socket:close()
                return
            elseif not chunk then
                socket:close()
                return
            end

            request = request .. chunk

            if request:len() > 2048 then
                result = {
                    proto = "HTTP/1.1",
                    request = request,
                    response = Response:bad("HTTP/1.1")
                }
            elseif request:match("\r?\n\r?\n$") then
                result = process_request(request)
            end

            if result ~= nil then
                log:print(
                    "%d %s %d %d '%s'",
                    result.response.status,
                    socket:getsockname().ip,
                    request:len(),
                    result.response.value:len(),
                    result.request:truncate(40)
                )
                socket:write(result.response.value)

                local keep_alive = (
                    result.proto ~= "HTTP/1.0"
                    and result.response.status ~= 400
                )

                if keep_alive then
                    request = ""
                    result = nil
                else
                    socket:read_stop()
                    socket:close()
                end
            end
        end)
    end)
end

return M
