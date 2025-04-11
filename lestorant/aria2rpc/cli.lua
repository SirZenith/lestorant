local argparse = require "argparse"

local rpc = require "lestorant.aria2rpc.rpc"
local format_util = require "lestorant.utils.format_util"
local logger = require "lestorant.utils.log_util"
local lunajson = require "lunajson"

local Command = argparse.Command
local RpcContext = rpc.RpcContext
local ChangePosHow = rpc.ChangePosHow
local UriOptions = rpc.UriOptions
local GlobalOptions = rpc.GlobalOptions

local log = logger.Logger:new("aria2rpc")

---@type argparse.ParameterCfg[]
local COMMON_PARAMS = {
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
    Active = 'active',
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
    cmd:parameter(COMMON_PARAMS)

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

---@param key_tbl table<unknown, string>
---@return argparse.ParameterCfg[]
local function make_option_parameter_list(key_tbl)
    local parameters = {}

    for _, opt_name in pairs(key_tbl) do
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

-- get_options_from_args takes parsed arguments table, generate RPC
-- options table by reading argument values.
---@param args table<string, any>
---@param key_tbl table<unknown, string>
---@return table<string, any>
local function get_options_from_args(args, key_tbl)
    local options = {}

    for arg_name, opt_name in pairs(key_tbl) do
        local value = args[arg_name]
        if value ~= nil then
            options[opt_name] = value
        end
    end

    return options
end

-- simple_result_callback prints basic prompt upon request response.
---@param _ any
---@param err? string
local function simple_result_callback(_, err)
    if err then
        io.stderr:write("operation failed: ", err, "\n")
    else
        print("operation successed")
    end
end

---@param result? any
---@param err? string
local function print_tasks(result, err)
    if err then
        io.stderr:write(err, "\n")
        return
    end

    if type(result) ~= "table" then
        io.stderr:write("can't find valid task list in responded data", "\n")
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

---@param result any
local function print_info_result(result)
    if type(result) ~= "table" then
        io.stderr:write("invalid response data", "\n")
        return
    end

    for k, v in pairs(result) do
        io.write(k, ": ", v, "\n")
    end
end

---@param result any
local function print_list_result(result)
    if type(result) ~= "table" then
        io.stderr:write("invalid response data", "\n")
        return
    end

    for _, value in ipairs(result) do
        print(value)
    end
end

-- ----------------------------------------------------------------------------
-- Command Definition

new_rpc_cmd(
    "add-task",
    "Adds a list of items to download list. Each item in list should be either a URI or path to local file",
    tbl_extend({
        { name = "items", type = "string", required = true, max_cnt = 0 },
    }, make_option_parameter_list(UriOptions)),
    function(context, args)
        local items = args.items
        if not items then
            return
        end

        local options = get_options_from_args(args, UriOptions)

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
    "remove",
    "Remove given task from download queue",
    {
        { long = "force", short = "f",     type = "string", help = "Force task to be removed" },
        { name = "gid",   type = "string", required = true, help = "GID of given task" },
    },
    function(context, args)
        local gid = args.gid or ""

        if args.force then
            context:force_remove(gid, simple_result_callback)
        else
            context:remove(gid, simple_result_callback)
        end
    end
)

new_rpc_cmd(
    "pause",
    "Pause specified or all tasks",
    {
        { long = "force", short = "f",     type = "boolean",                                                              help = "force task to pause" },
        { name = "gid",   type = "string", help = "GID of target task. When no specified, this command affects all task." },
    },
    function(context, args)
        local gid = args.gid

        if gid then
            if args.force then
                context:force_pause(gid, simple_result_callback)
            else
                context:pause(gid, simple_result_callback)
            end
        else
            if args.force then
                context:force_pause_all()
            else
                context:pause_all(simple_result_callback)
            end
        end
    end
)

new_rpc_cmd(
    "unpause",
    "Recover specified or all tasks from paused state",
    {
        { name = "gid", type = "string", help = "GID of target task. When no specified, this command affects all task." },
    },
    function(context, args)
        local gid = args.gid
        if gid then
            context:unpause(gid, simple_result_callback)
        else
            context:unpause_all(simple_result_callback)
        end
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

new_rpc_cmd(
    "get-uris",
    "List all URIs in given gid",
    {
        {
            name = "gid",
            type = "string",
            required = true,
            help = "target GID",
        }
    },
    function(context, args)
        local gid = args.gid
        context:get_uris(gid, function(result, err)
            if err then
                io.write("failed to fetch URI list for '", gid, "': ", err, "\n")
                return
            end

            for _, info in ipairs(result) do
                -- index
                -- length
                -- selected
                -- path
                -- completedLength
                io.write(tostring(info.index), ". ", info.path, "\n")
            end
        end)
    end
)

new_rpc_cmd(
    "get-files",
    "List all files in given gid",
    {
        {
            name = "gid",
            type = "string",
            required = true,
            help = "target GID",
        }
    },
    function(context, args)
        local gid = args.gid
        context:get_files(gid, function(result, err)
            if err then
                io.write("failed to fetch file list for '", gid, "': ", err, "\n")
                return
            end

            for _, info in ipairs(result) do
                -- index
                -- length
                -- selected
                -- path
                -- uris
                -- completedLength
                io.write(tostring(info.index), ". ", info.path, "\n")
            end
        end)
    end
)

new_rpc_cmd(
    "change-pos",
    "Move task to certain position",
    {
        { name = "gid", type = "string", required = true, help = "GID of target task" },
        { name = "pos", type = "number", required = true, help = "0-base index indicating where to move task to" },
        { long = "how", short = "h",     type = "string", default = ChangePosHow.pos_set,                        help = "indicating how does `pos` index get translated, possible values are POS_SET (relative to queue start), POS_CUR (relative to current index), POS_END (relative to queue end)" }
    },
    function(context, args)
        context:change_position(args.gid, args.pos, args.how, simple_result_callback)
    end
)

new_rpc_cmd(
    "task-option",
    "Get download option of given task",
    {
        { name = "gid", type = "string", required = true, help = "GID of target task" },
    },
    function(context, args)
        local gid = args.gid
        context:get_option(gid, function(result, err)
            if err then
                io.write("failed to fetch info for '", gid, "': ", err, "\n")
                return
            end

            print_info_result(result)
        end)
    end
)

new_rpc_cmd(
    "set-task-option",
    "Change download options of given task",
    tbl_extend({
        { name = "gid", type = "string", required = true, help = "GID of target task" },
    }, make_option_parameter_list(UriOptions)),
    function(context, args)
        local gid = args.gid
        local options = get_options_from_args(args, UriOptions)
        context:change_option(gid, options, simple_result_callback)
    end
)

new_rpc_cmd(
    "global-option",
    "Get global options of Aria2",
    nil,
    function(context)
        context:get_global_option(function(result, err)
            if err then
                io.write("operation failed: ", err, "\n")
                return
            end

            print_info_result(result)
        end)
    end
)

new_rpc_cmd(
    "set-global-option",
    "Change global options of Aria2",
    make_option_parameter_list(GlobalOptions),
    function(context, args)
        local options = get_options_from_args(args, GlobalOptions)
        context:change_global_option(options, simple_result_callback)
    end
)

new_rpc_cmd(
    "global-stat",
    "Get Aria2 global status",
    nil,
    function(context)
        context:get_global_stat(function(result, err)
            if err then
                io.write("failed to get data: ", err, "\n")
                return
            end

            print_info_result(result)
        end)
    end
)

new_rpc_cmd(
    "remove-download-result",
    "Remove all download result from memory",
    {
        { name = "gid", type = "string", help = "GID of target task. When missig, this command affects all completed/removed/error tasks." }
    },
    function(context, args)
        local gid = args.gid
        if gid then
            context:remove_download_result(gid, simple_result_callback)
        else
            context:purge_download_result(simple_result_callback)
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

            local out = io.stdout

            out:write("Version: ", result.version or "unknown", "\n")

            local features = result.enabledFeatures
            if type(features) == "table" then
                out:write("Enabled Features:\n")

                if #features <= 0 then
                    out:write("    None\n")
                else
                    for _, feature in ipairs(features) do
                        out:write("    ", feature, "\n")
                    end
                end
            end
        end)
    end
)

new_rpc_cmd(
    "session-info",
    "Get infomation of current session",
    nil,
    function(context)
        context:get_session_info(function(result, err)
            if err then
                io.write("failed to get data: ", err, "\n")
                return
            end

            print_info_result(result)
        end)
    end
)

new_rpc_cmd(
    "shutdown",
    "Shutdown Aria2",
    {
        { long = "force", short = "f", type = "boolean", help = "Force shutdown" },
    },
    function(context, args)
        if args.force then
            context:force_shutdown(simple_result_callback)
        else
            context:shutdown(simple_result_callback)
        end
    end
)

new_rpc_cmd(
    "save-session",
    "Save session data as file",
    nil,
    function(context)
        context:save_session(simple_result_callback)
    end
)

new_rpc_cmd(
    "list-method",
    "List all available methods",
    nil,
    function(context)
        context:list_methods(function(result, err)
            if err then
                io.write("failed to fetch data: ", err, "\n")
                return
            end

            print_list_result(result)
        end)
    end
)

new_rpc_cmd(
    "list-notification",
    "List all notifications",
    nil,
    function(context)
        context:list_notification(function(result, err)
            if err then
                io.write("failed to fetch data: ", err, "\n")
                return
            end

            print_list_result(result)
        end)
    end
)

return root_cmd
