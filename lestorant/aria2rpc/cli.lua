local argparse = require "argparse"

local rpc = require "lestorant.aria2rpc.rpc"
local format_util = require "lestorant.utils.format_util"
local logger = require "lestorant.utils.log_util"

local Command = argparse.Command

local log = logger.Logger:new("aria2rpc")

local MAX_NAME_LEN = 50
local ELLIPSIS = '...'

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
        local context = rpc.get_rpc_context_from_env()

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
            local resp, resp_err = rpc.add_task(context, item, options)

            if resp then
                log:infoln(resp.result or "")
            else
                log:warnln("failed to add item ", item, ": ", resp_err or "unknown error")
            end
        end
    end
)

new_rpc_cmd(
    "version",
    "Queries version infomation of running aria2 instance",
    nil,
    function(context)
        rpc.call_method(
            context,
            "getVersion",
            nil,
            function(result)
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
            end,
            function(err)
                print("failed to get version info: ", err or "unknown")
            end)
    end
)

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

        local resp, method_err
        if task_type == TaskStateType.Active then
            resp, method_err = rpc.call_method(context, "tellActive")
        elseif task_type == TaskStateType.Waiting then
            resp, method_err = rpc.call_method(context, 'tellWaiting', { 0, 666 })
        elseif task_type == TaskStateType.Stopped then
            resp, method_err = rpc.call_method(context, 'tellStopped', { 0, 666 })
        else
            method_err = "unknown task state type: " .. task_type
        end

        if not resp then
            print(method_err)
            return
        end

        local list = resp.result
        if not list then
            print("failed to find task list in response data")
            return
        end

        for _, task in ipairs(list) do
            local completed_length = tonumber(task.completedLength) or 0
            local total_length = tonumber(task.totalLength) or 0
            local remaining_length = total_length - completed_length
            local download_speed = tonumber(task.downloadSpeed) or 0

            local eta = format_util.compute_eta(download_speed, remaining_length)

            local percent = 100
            if (total_length > 0) then
                percent = 100 * completed_length / total_length
            end
        end
    end
)

return root_cmd
