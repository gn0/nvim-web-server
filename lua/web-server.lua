local default_config = {
    host = "127.0.0.1",
    port = 4999,
    log_filename = nil,

    -- NOTE Keep-alive means that we run out of sockets real quick under
    -- load, and clients will begin getting "connection reset by peer"
    -- errors.
    --
    keep_alive = false
}

local M = {}

M.config = vim.deepcopy(default_config)

local djot = require("web-server.djot")

local Logger = {}

function Logger.new(filename)
    local buf_id = vim.api.nvim_create_buf(true, true)
    local timer = nil
    local empty = true

    if filename then
        -- Open `filename`.
        --
        vim.api.nvim_buf_call(buf_id, function()
            vim.cmd.edit(filename)
            empty = vim.fn.wordcount().bytes == 0
        end)

        -- Save the log buffer to `filename` every 5 minutes.
        --
        local dur_5m = 5 * 60 * 1000
        timer = vim.uv.new_timer()
        timer:start(dur_5m, dur_5m, vim.schedule_wrap(function()
            vim.api.nvim_buf_call(buf_id, function()
                vim.cmd.write()
            end)
        end))
    end

    local win_id = vim.api.nvim_open_win(buf_id, 0, { split = "above" })
    local state = {
        buf_id = buf_id,
        win_id = win_id,
        empty = empty,
        timer = timer
    }
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

local response_connection = "Connection: keep-alive\n"

function Response.ok(proto, etag, content_type, content)
    return setmetatable({
        status = 200,
        value = string.format(
            "%s 200 OK\n" ..
            "Server: nvim-web-server\n" ..
            'ETag: "' .. etag .. '"\n' ..
            "Content-Type: %s\n" ..
            "Content-Length: %d\n" ..
            response_connection ..
            "\n" ..
            "%s\n",
            proto, content_type, content:len(), content
        )
    }, {
        __index = Response
    })
end

function Response.not_modified(proto, etag)
    return setmetatable({
        status = 304,
        value = (
            proto .. " 304 Not Modified\n" ..
            "Server: nvim-web-server\n" ..
            'ETag: "' .. etag .. '"\n' ..
            response_connection ..
            "\n"
        )
    }, {
        __index = Response
    })
end

function Response.bad(proto)
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

function Response.not_found(proto)
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
            response_connection ..
            "\n" ..
            content
        )
    }, {
        __index = Response
    })
end

local Path = {}

function Path.new(raw)
    local query_string = raw:match("?.*")
    local normalized = raw:gsub("?.*", ""):gsub("/+", "/")

    if normalized ~= "/" then
        normalized = normalized:gsub("/$", "")
    end

    return setmetatable({
        value = normalized,
        query_string = query_string
    }, {
        __index = Path
    })
end

local Routing = {}

function Routing.new(djotter)
    return setmetatable({
        djotter = djotter,
        paths = {}
    }, {
        __index = Routing
    })
end

function Routing:add_path(path, value)
    local normalized = Path.new(path).value

    if self.paths[normalized] then
        return false
    end

    value.buf_name = (
        vim.api.nvim_buf_get_name(value.buf_id) or "[unnamed]"
    )

    log:print(
        "Routing path '%s' to buffer '%s' (%s).",
        normalized,
        value.buf_name,
        value.buf_type
    )

    self.paths[normalized] = value

    return true
end

function get_buffer_content(buf_id)
    return table.concat(
        vim.api.nvim_buf_get_lines(buf_id, 0, -1, true),
        "\n"
    )
end

function Routing:update_content(buf_id)
    local path = self:get_path_by_buf_id(buf_id)

    assert(path, string.format(
        "Buffer %d has a callback attached but no path routed to it.",
        buf_id
    ))

    local value = self.paths[path]

    log:print(
        "Updating content for path '%s' from buffer '%s'.",
        path,
        value.buf_name
    )

    local buf_type = value.buf_type
    local content
    local content_type = buf_type

    if not buf_type:match("^text/") then
        local file_path = vim.api.nvim_buf_get_name(0)
        content = io.open(file_path):read("*a")
    else
        content = get_buffer_content(buf_id)
    end

    if buf_type == "text/djot" then
        content = self.djotter:to_html(content)
        content_type = "text/html"
    end

    -- For binary files, `content` is a blob, and `vim.fn.sha256`
    -- expects a string.
    --
    if vim.fn.type(content) == vim.v.t_blob then
        self.paths[path].etag = vim.fn.sha256(vim.fn.string(content))
    else
        self.paths[path].etag = vim.fn.sha256(content)
    end

    self.paths[path].content_type = content_type
    self.paths[path].content = content
end

function Routing:update_djot_paths()
    for _, value in pairs(self.paths) do
        if value.buf_type == "text/djot" then
            self:update_content(value.buf_id)
        end
    end
end

function Routing:delete_path(path)
    log:print("Deleting path '%s'.", path)

    local value = self.paths[path]

    vim.api.nvim_del_autocmd(value.autocmd_id)

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

local function process_request_line(request)
    local request_line = request:match("[^\r\n]*")
    local method = nil
    local path = nil
    local proto = nil
    local bad = false

    for word in request_line:gmatch("[^ ]+") do
        if not method then
            method = word
        elseif not path then
            path = word
        elseif not proto then
            proto = word
        else
            bad = true
            break
        end
    end

    if method ~= "GET" or not proto then
        bad = true
    end

    return request_line, method, path, proto, bad
end

local function process_request_header(request)
    for line in string.gmatch(request, "[^\r\n]+") do
        local field_name = line:match("^If%-None%-Match: *")

        if field_name then
            local value = line:sub(field_name:len() + 1):gsub('"', "")

            if value then
                return value
            end

            break
        end
    end
end

local function process_request(request)
    local request_line, _, path, proto, bad = process_request_line(
        request
    )
    local response

    if bad then
        response = Response.bad(proto or "HTTP/1.1")
    else
        local if_none_match = process_request_header(request)
        local normalized = Path.new(path).value

        if not routing:has_path(normalized) then
            response = Response.not_found(proto)
        else
            local value = routing.paths[normalized]

            if if_none_match and if_none_match == value.etag then
                response = Response.not_modified(proto, value.etag)
            else
                response = Response.ok(
                    proto,
                    value.etag,
                    value.content_type,
                    value.content
                )
            end
        end
    end

    return {
        proto = proto,
        request = request_line,
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

local Djotter = {}

function Djotter.new()
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
    return setmetatable(state, { __index = Djotter })
end

function Djotter:to_html(input)
    local ast = djot.parse(input, false, function(warning)
        cmd_error(
            "Djot parse error: %s at byte position %d",
            warning.message,
            warning.pos
        )
    end)

    local content = djot.render_html(ast)
    local content_escaped = content:gsub("%%", "%%%%")

    local title = get_first_header(content) or ""
    local title_escaped = title:gsub("%%", "%%%%")

    return (
        self.template
        :gsub("{{ title }}", title_escaped)
        :gsub("{{ content }}", content_escaped)
    )
end

local djotter = nil

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
    local buf_type = opts.fargs[2] or "text/djot"
    local content_type = buf_type
    local content = nil
    local autocmd_id = vim.api.nvim_create_autocmd("BufWrite", {
        buffer = buf_id,
        callback = function(arg) routing:update_content(arg.buf) end
    })

    routing:add_path(path, {
        buf_id = buf_id,
        buf_type = opts.fargs[2] or "text/djot",
        content_type = content_type,
        content = content,
        autocmd_id = autocmd_id
    })

    routing:update_content(buf_id)
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
        local length = 0
        if value.content then
            length = value.content:len()
        end

        log:print(
            "Path '%s' is routed to '%s' (%s, length %d).",
            path,
            value.buf_name,
            value.content_type,
            length
        )
    end
end

local function ws_set_buffer_as_template()
    if djotter.template_buf_name then
        log:print(
            "Unsetting '%s' as template.", djotter.template_buf_name
        )

        vim.api.nvim_del_autocmd(djotter.template_autocmd_id)
    end

    local buf_id = vim.fn.bufnr()
    local buf_name = vim.api.nvim_buf_get_name(buf_id)

    log:print("Setting '%s' as template.", buf_name)

    local function update_template()
        djotter.template = get_buffer_content(buf_id)
        routing:update_djot_paths()
    end

    local autocmd_id = vim.api.nvim_create_autocmd("BufWrite", {
        buffer = buf_id,
        callback = update_template
    })

    djotter.template_buf_name = buf_name
    djotter.template_autocmd_id = autocmd_id

    update_template()
end

function M.init(config)
    M.config = vim.tbl_extend("force", default_config, config or {})

    log = Logger.new(M.config.log_filename)
    djotter = Djotter.new()
    routing = Routing.new(djotter)

    if not M.config.keep_alive then
        response_connection = "Connection: close\n"
    end

    local new_cmd = vim.api.nvim_create_user_command
    new_cmd("WSAddBuffer", ws_add_buffer, { nargs = "*" })
    new_cmd("WSDeletePath", ws_delete_path, { nargs = "*" })
    new_cmd("WSPaths", ws_paths, { nargs = 0 })
    new_cmd(
        "WSSetBufferAsTemplate",
        ws_set_buffer_as_template,
        { nargs = 0 }
    )

    local host = M.config.host
    local port = M.config.port

    create_server(host, port, function(socket)
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
                    response = Response.bad("HTTP/1.1")
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
                    M.config.keep_alive
                    and result.proto ~= "HTTP/1.0"
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
