local argparse = require "argparse"
local torrent_dl = require "lestorant.rss.torrent_downalod"

local json = require "lestorant.utils.json"
local fs_util = require "lestorant.utils.fs_util"
local log_util = require "lestorant.utils.log_util"
local network_util = require "lestorant.utils.network_util"

local Command = argparse.Command

local log = log_util.Logger:new("rss")

local root_cmd = Command:new {
    name = "rss",
    help = "RSS subscription update and manage",
}

---@type argparse.ParameterCfg[]
local common_params = {
    { long = "config", short = "c", type = "string", default = "./config.json", help = "path to config JSON" },
}

---@param name string
---@param help? string
---@param parameters? argparse.ParameterCfg[]
---@param operation fun(config: lestorant.Config, args)
local function add_rss_cmd(name, help, parameters, operation)
    local cmd = Command:new { name = name, help = help }
    cmd:parameter(common_params)

    if parameters then
        cmd:parameter(parameters)
    end

    cmd:operation(function(args)
        local config_name = args.config
        if not config_name then
            log:errorln("no config file path is given")
            return
        end

        local data, read_err = fs_util.read_all(config_name)
        if read_err then
            log:errorln("failed to read config file: ", read_err or "Unknown error")
            return
        end

        local ok, result = pcall(json.decode, data)
        if not ok then
            log:errorln("failed to parse config file: ", result)
            return
        end

        operation(result, args)
    end)

    root_cmd:subcommand { cmd }
end

add_rss_cmd(
    "list-source",
    "list all source in config file",
    nil,
    function(config)
        local source = config.sources
        if not source or #source <= 0 then
            log:warnln("no source found in config file")
            return
        end

        local indent = "  "
        local big_indent = "    "

        for i, sub in ipairs(source) do
            if i > 1 then
                io.write("\n")
            end

            io.write("Name: ", sub.name, "\n")

            io.write(indent, "URL:", "\n")

            local url = sub.url
            if type(url) == "string" then
                io.write(big_indent, sub.url, "\n")
            elseif type(url) == "table" then
                for _, u in ipairs(url) do
                    io.write(big_indent, u, "\n")
                end
            else
                io.write(big_indent, "no valid URL found", "\n")
            end
        end
    end
)

add_rss_cmd(
    "list-subs",
    "list all subscriptions in config file",
    nil,
    function(config)
        local subs = config.subscriptions
        if not subs or #subs <= 0 then
            log:warnln("no subscription found in config file")
            return
        end

        local indent = "  "
        local big_indent = "    "

        for i, sub in ipairs(subs) do
            if i > 1 then
                io.write("\n")
            end

            io.write("Name: ", sub.name, "\n")

            io.write(indent, "Pattern:", "\n")
            io.write(big_indent, sub.pattern, "\n")

            io.write(indent, "Exclude Pattern:", "\n")
            io.write(big_indent, sub.exclude_pattern, "\n")

            local torrent_dl_dir = sub.torrent_dl_dir or torrent_dl.DEFAULT_OUTPUT_DIR
            io.write(indent, "Torrent directory:", "\n")
            io.write(big_indent, torrent_dl_dir, "\n")

            io.write(indent, "Content directory:", "\n")
            io.write(big_indent, sub.content_dl_dir or torrent_dl, "\n")
        end
    end
)

---@param config lestorant.Config
---@param args table
---@param on_result fun(task?: rss.TorrentTask, err?: string)
local function update_rss(config, args, on_result)
    local target_set
    if args.name and #args.name > 0 then
        target_set = {}
        for _, name in ipairs(args.name) do
            target_set[name] = true
        end
    end

    local sub_list = {}
    if config.subscriptions then
        for _, sub in ipairs(config.subscriptions) do
            if not target_set or target_set[sub.name] then
                sub.torrent_dl_dir = sub.torrent_dl_dir or config.output_dir
                table.insert(sub_list, sub)
            end
        end
    end

    torrent_dl.update_source_list(config.sources or {}, config, sub_list, on_result)
end

add_rss_cmd(
    "update",
    "update specified or all subscriptions",
    {
        { name = "name", type = "string", max_cnt = 0 },
    },
    function(config, args)
        update_rss(config, args, function(task, err)
            if not task then
                log:warnln(err)
            elseif err then
                log:warnln("torrent download failed: ", task.output_name, " - ", err)
            else
                log:infoln("torrent downloaded: ", task.output_name)
            end
        end)

        local line = ("-"):rep(20)
        log:infoln(line, " RSS update completed ", line)
    end
)

add_rss_cmd(
    "aria2-update",
    "update RSS subscription and add newly found torrent as Aria2 task",
    {
        { name = "name", type = "string", max_cnt = 0 },
    },
    function(config, args)
        local rpc = require "lestorant.aria2rpc.rpc"

        local RpcContext = rpc.RpcContext
        local UriOptions = rpc.UriOptions

        local aria2cfg = config.aria2
        if not aria2cfg then
            log:errorln("no aria2 section found in config")
            return
        end

        local context = RpcContext:new_from_env()

        context.rpc_url = aria2cfg.rpc_url or context.rpc_url
        if not context.rpc_url then
            log:errorln("no RPC URl found in Aria2 config")
            return
        end

        context.proxy = network_util.pick_proxy(
            context.rpc_url,
            aria2cfg.http_proxy or config.http_proxy,
            aria2cfg.https_proxy or config.https_proxy
        )
        context.secret = aria2cfg.secret
        context.method = aria2cfg.rpc_method or rpc.DEFAULT_HTTP_METHOD

        update_rss(config, args, function(task, err)
            if not task then
                log:warnln(err)
                return
            elseif err then
                log:warnln("torrent download failed: ", task.title, " - ", err)
                return
            end

            local target = task.output_name
            if task.is_uri then
                target = task.url
            end

            context:add_task(
                target,
                {
                    [UriOptions.dir] = task.content_dl_dir,
                },
                nil,
                function(_, rpc_err)
                    if err then
                        log:warnln("failed to add Aria2 task ", task.title, ": ", rpc_err or "Unknown Error")
                    else
                        log:infoln("new Aria2 task added: ", task.title)
                    end
                end
            )
        end)

        local line = ("-"):rep(20)
        log:infoln(line, " RSS update completed ", line)
    end
)

return root_cmd
