#!/bin/env lua

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

local log_util = require "lestorant.utils.log_util"

local Application = argparse.Application
local LogLevel = log_util.LogLevel

log_util.set_global_log_level(LogLevel.info)

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
