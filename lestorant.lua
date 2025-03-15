local path_sep = package.config:sub(1, 1)
local source_patt = ("@?(.*%s)"):format(path_sep)
local source_path = debug.getinfo(1).source:match(source_patt)
if source_path then
    package.path = table.concat({
        source_path .. path_sep .. "?.lua",
        source_path .. path_sep .. "?" .. path_sep .. "?.lua",
        package.path
    }, ";")
end

local argparse = require "argparse"

local Application = argparse.Application

local app = Application:new {
    name = "lestorant",
    version = "0.1.0",
    help = "A script for managing torrent RSS subscription",
}

app:subcommand {
    [1] = require "lestorant.aria2rpc.cli",
    [2] = require "lestorant.rss.cli",
}

app:run()
