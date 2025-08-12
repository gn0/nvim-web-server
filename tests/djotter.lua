local M = require("web-server")

for i, case in ipairs({
    { t = "{{ title }}", d = "# foo\n\n## bar\n\nbaz\n", h = "foo" },
    { t = "{{ title }}", d = "x\n\n# foo\n\n## bar\n\nbaz\n", h = "foo" },
    { t = "{{ title }}", d = "# foo\n\n# bar\n\nbaz\n", h = "foo" },
    { t = "{{ content }}",
      d = "# foo\n\n## bar\n\nbaz\n",
      h =
        "<section id=\"foo\">\n"
        .. "<h1>foo</h1>\n"
        .. "<section id=\"bar\">\n"
        .. "<h2>bar</h2>\n"
        .. "<p>baz</p>\n"
        .. "</section>\n"
        .. "</section>\n" },
    { t = "<title>{{ title }}</title>\n<body>{{ content }}</body>",
      d = "# foo\n\n## bar\n\nbaz\n",
      h =
        "<title>foo</title>\n"
        .. "<body><section id=\"foo\">\n"
        .. "<h1>foo</h1>\n"
        .. "<section id=\"bar\">\n"
        .. "<h2>bar</h2>\n"
        .. "<p>baz</p>\n"
        .. "</section>\n"
        .. "</section>\n"
        .. "</body>" },
}) do
    local djotter = M.internal.Djotter.new()

    djotter.template = case.t

    local result = djotter:to_html(case.d)

    assert(result == case.h, "#" .. i .. " -> " .. result)
end
