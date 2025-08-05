# nvim-web-server

This plugin turns Neovim into a web server.
It's written in Lua using only Neovim's API, so no external tools are required.

## Features

- [X] Serve paths from Neovim buffers.
- [X] Natively support the [Djot](https://djot.net) markup language and automatically convert Djot buffers to HTML using [djot.lua](https://github.com/jgm/djot.lua).
- [X] Set custom HTML template for the Djot-to-HTML conversion (also via a Neovim buffer).
- [X] Update content when buffers are written to disk.
- [X] Allow browsers to cache content via [entity tags](https://en.wikipedia.org/wiki/HTTP_ETag).

## Usage

Launch nvim-web-server interactively by typing

```vim
:lua require("web-server").init()
```

You can route paths to buffers by switching to the buffer that you want to serve and using the `:WSAddBuffer` command.
By default, nvim-web-server interprets the buffer content as Djot and automatically converts it to HTML:

```vim
" Serve / from the current buffer and treat the buffer as Djot.
:WSAddBuffer /
```

But you can specify the `Content-Type` to be anything:

```vim
" Serve /rss.xml as an XML file.
:WSAddBuffer /rss.xml text/xml

" Serve /picture.png as a PNG file.
:WSAddBuffer /picture.png image/png
```

You can also set a buffer as the template for the Djot-to-HTML conversion.
Take this template:

```html
<!DOCTYPE html>
<html>
<head>
<title>{{ title }} - Super Duper Website</title>
<style>
body {
    font-family: "Comic Sans MS", sans-serif;
}
</style>
</head>
<body>{{ content }}</body>
</html>
```

`{{ content }}` will be replaced with the result of the conversion, and `{{ title }}` with the content of the first heading (if present).
You can set this as your template using the `:WSSetBufferAsTemplate` command:

```vim
" Set current buffer as the template and automatically update the content for
" every Djot-based path.
:WSSetBufferAsTemplate
```

If you want to see what paths are currently routed and to which buffers, use `:WSPaths`.
If you want to delete a path, use `:WSDeletePath`:

```vim
" No longer serve /picture.png.
:WSDeletePath /picture.png
```

You can configure nvim-web-server by passing a table to the `init` method when you launch the server.
For example, if you want the server log to be periodically saved to a file:

```vim
:lua require("web-server").init({ log_filename = "server.log" })
```

This is the default configuration:

| Option             | Default value |
|--------------------|---------------|
| `host`             | `"127.0.0.1"` |
| `port`             | `4999`        |
| `log_filename`     | `nil`         |
| `log_each_request` | `false`       |
| `keep_alive`       | `false`       |

## Installation

Use your Neovim package manager, or install it manually:

```sh
mkdir -p ~/.config/nvim/pack/gn0/start
cd ~/.config/nvim/pack/gn0/start
git clone https://github.com/gn0/nvim-web-server.git
```

## License

nvim-web-server is distributed under the [MIT](./COPYING.txt) license.
`vim-cheatsheet.lua` and associated source files are Copyright (C) 2025 Gábor Nyéki.
`djot.lua` and its source files are Copyright (C) 2022 John MacFarlane, with the exception of `lua/web-server/djot/json.lua` which is Copyright (C) 2020 rxi.

