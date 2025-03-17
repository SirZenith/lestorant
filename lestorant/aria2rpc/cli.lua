local argparse = require "argparse"

local rpc = require "lestorant.aria2rpc.rpc"
local format_util = require "lestorant.utils.format_util"
local json = require "lestorant.utils.json"
local logger = require "lestorant.utils.log_util"

local Command = argparse.Command
local RpcContext = rpc.RpcContext

local log = logger.Logger:new("aria2rpc")

-- tbl_extend takes a destination table `dst` and several other tables. Modifies
-- `dst` in place, appending elements of all other tables to it.
-- Return value of this function will be `dst`.
---@generic T
---@param dst T[]
---@param ... T[]
---@return T[]
local function tbl_extend(dst, ...)
    for _, other in ipairs { ... } do
        for _, element in ipairs(other) do
            table.insert(dst, element)
        end
    end

    return dst
end

---@return argparse.ParameterCfg[]
local function make_uri_option_parameter_list()
    local parameters = {}

    for _, opt_name in pairs(rpc.UriOptions) do
        ---@type argparse.ParameterCfg
        local param = {
            long = opt_name,
            type = "string",
            is_hidden = true,
        }
        table.insert(parameters, param)
    end

    return parameters
end

-- get_uri_options_from_args takes parsed arguments table, generate RPC
-- options table by reading argument values.
---@return table<aria2rpc.UriOptions, string>
local function get_uri_options_from_args(args)
    local options = {}

    for _, opt_name in pairs(rpc.UriOptions) do
        local value = args[opt_name]
        if value ~= nil then
            options[opt_name] = value
        end
    end

    return options
end

---@type argparse.ParameterCfg[]
local common_params = {
    { long = "rpc-url", type = "string" },
    { long = "secret",  type = "string" },
    -- TODO: add support for legacy authentication method
    -- { long = "username", short = "u", type = "string" },
    -- { long = "password", short = "p", type = "string" },
    { long = "proxy",   type = "string" },
    { long = "method",  type = "string" },
}

---@enum aria2rpc.TaskStateType
local TaskStateType = {
    Active = 'Active',
    Waiting = 'waiting',
    Stopped = 'stopped',
}

local root_cmd = Command:new { name = "aria2rpc", help = "Aria2 RPC client" }

-- new_rpc_cmd creates a new RPC command and adds it to `commands` list.
---@param name string # command name
---@param help string # help mesage of this command.
---@param params? argparse.ParameterCfg[] # command's parameter list
---@param operation fun(context: aria2rpc.RpcContext, args: table<string, any>)
local function new_rpc_cmd(name, help, params, operation)
    local cmd = Command:new { name = name, help = help }
    cmd:parameter(common_params)

    if params then
        cmd:parameter(params)
    end

    cmd:operation(function(args)
        local context = RpcContext:new_from_env()

        if args.rpc_url then
            context.rpc_url = args.rpc_url
        end
        if args.secret then
            context.secret = args.secret
        end
        if args.proxy then
            context.proxy = args.proxy
        end
        if args.method then
            context.method = args.method
        end

        operation(context, args)
    end)

    root_cmd:subcommand { cmd }
end

new_rpc_cmd(
    "add-task",
    "Adds a list of items to download list. Each item in list should be either a URI or path to local file",
    tbl_extend({
        { name = "items", type = "string", required = true, max_cnt = 0 },
    }, make_uri_option_parameter_list()),
    function(context, args)
        local items = args.items
        if not items then
            return
        end

        local options = get_uri_options_from_args(args)

        for _, item in ipairs(items --[[@as string[] ]]) do
            context:add_task(item, options, nil, function(result, err)
                if err then
                    log:warnln("failed to add item ", item, ": ", err or "unknown error")
                else
                    log:infoln(result)
                end
            end)
        end
    end
)

new_rpc_cmd(
    "version",
    "Queries version infomation of running aria2 instance",
    nil,
    function(context)
        context:get_version(function(result, err)
            if err then
                log:errorln("failed to get version info: ", err or "unknown")
                return
            end

            local buffer = {}

            table.insert(buffer, "Version: ")
            table.insert(buffer, result.version or "unknown")
            table.insert(buffer, "\n")

            local features = result.enabledFeatures
            if type(features) == "table" then
                table.insert(buffer, "Enabled Features:\n")

                if #features <= 0 then
                    table.insert(buffer, "    None\n")
                else
                    for _, feature in ipairs(features) do
                        table.insert(buffer, "    ")
                        table.insert(buffer, feature)
                        table.insert(buffer, "\n")
                    end
                end
            end

            print(table.concat(buffer))
        end)
    end
)

---@param result? any
---@param err? string
local function print_tasks(result, err)
    if err then
        print(err)
        return
    end

    if type(result) ~= "table" then
        print("can't find valid task list in responded data")
        return
    end

    for _, task in ipairs(result --[[@as aria2rpc.TaskInfo[] ]]) do
        local completed_length = tonumber(task.completedLength) or 0
        local total_length = tonumber(task.totalLength) or 0
        local remaining_length = total_length - completed_length
        local download_speed = tonumber(task.downloadSpeed) or 0

        local eta = format_util.compute_eta(download_speed, remaining_length)

        local percent = 100
        if (total_length > 0) then
            percent = 100 * completed_length / total_length
        end

        local name

        local bittorrent = task.bittorrent
        local info_dict = bittorrent and bittorrent.info
        local info_name = info_dict and info_dict.name
        if info_name then
            name = info_name
        end

        if not name then
            local files_list = task.files
            if type(files_list) == "table" then
                for _, file in ipairs(files_list --[[@as aria2rpc.TaskFileInfo[] ]]) do
                    local uri_list = file.uris
                    if type(uri_list) == "table" and #uri_list > 0 then
                        name = uri_list[1].uri
                    else
                        name = file.path
                    end
                end
            end
        end

        if name then
            name = format_util.truncate_string(name, 50)
        end

        local file_size_threshold = 0.8
        local msg = ('%s %s %.1f%% (%s / %s) %s/s %s/s (%s/%s) %s'):format(
            task.gid or "-",
            name or "Unknown",
            percent,
            format_util.file_size_abbr(completed_length, file_size_threshold),
            format_util.file_size_abbr(total_length, file_size_threshold),
            format_util.file_size_abbr(download_speed, file_size_threshold),
            format_util.file_size_abbr(tonumber(task.uploadSpeed) or 0, file_size_threshold),
            task.numSeeders,
            task.connections,
            eta
        )

        print(msg)
    end
end

new_rpc_cmd(
    "list",
    "Lists all tasks of certain state",
    {
        {
            name = "task_type",
            type = "string",
            default = TaskStateType.Active,
            help =
                "list tasks of certain state, possible values are: " ..
                table.concat({ TaskStateType.Active, TaskStateType.Waiting, TaskStateType.Stopped }, ", ")
        }
    },
    function(context, args)
        local task_type = args.task_type

        if task_type == TaskStateType.Active then
            context:tell_active(nil, print_tasks)
        elseif task_type == TaskStateType.Waiting then
            context:tell_waiting(0, 666, nil, print_tasks)
        elseif task_type == TaskStateType.Stopped then
            context:tell_stopped(0, 666, nil, print_tasks)
        else
            print_tasks(nil, "unknown task state type: " .. task_type)
        end
    end
)

return root_cmd
