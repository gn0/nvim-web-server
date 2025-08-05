local M = require("web-server")

function setup()
    M.init()

    vim.cmd.split("tests/files/template.html")
    vim.cmd("WSSetBufferAsTemplate")

    vim.cmd.split("tests/files/index.dj")
    vim.cmd("WSAddBuffer /")

    vim.cmd.split("tests/files/dummy.png")
    vim.cmd("WSAddBuffer /dummy.png image/png")

    vim.cmd.split("tests/files/page.html")
    vim.cmd("WSAddBuffer /page text/html")
end

function test(opts)
    local command = {
        "curl", "-si", "http://127.0.0.1:4999" .. opts.path
    }

    if opts.etag then
        table.insert(command, "-H")
        table.insert(command, "If-None-Match: " .. opts.etag)
    end

    local done = false

    vim.system(command, { text = true }, function(result)
        local first_line = result.stdout:match("^[^\r\n]*")
        local status = tonumber(
            first_line:match("^HTTP/1.[01] ([0-9]+)")
        )
        local content_type = nil
        local content = nil
        local is_content = false

        for line in result.stdout:gmatch("[\r\n]([^\r\n]*)") do
            if line == "" then
                is_content = true
            elseif is_content then
                if not content then
                    content = line
                else
                    content = content .. "\n" .. line
                end
            else
                content_type = (
                    line:match("^Content%-Type: (.*)")
                    or content_type
                )
            end
        end

        opts.callback({
            status = status,
            content_type = content_type,
            content = content,
        })

        done = true
    end)

    vim.wait(1000, function() return done end, 100)

    assert(done)
end

setup()

test({
    path = "/",
    callback = function(result)
        assert(result.status == 200, result.status)
        assert(result.content_type == "text/html", result.content_type)
        assert(
            result.content ==
                "<title>foo</title>\n"
                .. "<body><section id=\"foo\">\n"
                .. "<h1>foo</h1>\n"
                .. "<p><img alt=\"bar\" src=\"./dummy.png\"></p>\n"
                .. "</section>\n"
                .. "</body>",
            result.content
        )
    end
})

test({
    path = "/",
    etag = "6d63a141fe09fc0a7343cedd9e7b6b6456379d8b1f522810988b7faea99f600e",
    callback = function(result)
        assert(result.status == 304, result.status)
        assert(not result.content_type, result.content_type)
        assert(not result.content, result.content)
    end
})

test({
    path = "/dummy.png",
    callback = function(result)
        -- NOTE `test` replaces \r\n and \r with \n, so the magic that
        -- we test for is not the real one:
        --
        --   "\x89PNG\x0d\x0a\x1a\x0a\x00\x00\x00\x0DIHDR"
        --
        local png_magic = "\x89PNG\x0a\x1a\x0a\x00\x00\x00\x0aIHDR"

        assert(result.status == 200, result.status)
        assert(result.content_type == "image/png", result.content_type)
        assert(result.content:match("^" .. png_magic))
    end
})

test({
    path = "/page",
    callback = function(result)
        assert(result.status == 200, result.status)
        assert(result.content_type == "text/html", result.content_type)
        assert(
            result.content ==
                "<h1>page</h1>\n"
                .. "<p>content</p>",
            result.content
        )
    end
})

test({
    path = "/nonexistent",
    callback = function(result)
        assert(result.status == 404, result.status)
        assert(result.content_type == "text/html", result.content_type)
    end
})
