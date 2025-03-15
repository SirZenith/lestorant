local base64 = require "base64"
local ltn12 = require "ltn12"
local url = require "socket.url"

local json = require "lestorant.utils.json"
local log_util = require "lestorant.utils.log_util"
local network_util = require "lestorant.utils.network_util"

local M = {}

local log = log_util.Logger:new("rpc")

local TOKEN_PREFIX = "token:"

-- Default http method used for RPC request.
M.DEFAULT_HTTP_METHOD = "POST"

---@class aria2rpc.RpcContext
---@field rpc_url string # RPC server URL
---@field secret? string # RPC secret
---@field proxy? string # proxy used in RPC request
---@field method? string # HTTP method used by RPC call

---@enum aria2rpc.UriOptions
M.UriOptions = {
    all_proxy = "all-proxy",
    all_proxy_passwd = "all-proxy-passwd",
    all_proxy_user = "all-proxy-user",
    allow_overwrite = "allow-overwrite",
    allow_piece_length_change = "allow-piece-length-change",
    always_resume = "always-resume",
    async_dns = "async-dns",
    auto_file_renaming = "auto-file-renaming",
    bt_enable_hook_after_hash_check = "bt-enable-hook-after-hash-check",
    bt_enable_lpd = "bt-enable-lpd",
    bt_exclude_tracker = "bt-exclude-tracker",
    bt_external_ip = "bt-external-ip",
    bt_force_encryption = "bt-force-encryption",
    bt_hash_check_seed = "bt-hash-check-seed",
    bt_load_saved_metadata = "bt-load-saved-metadata",
    bt_max_peers = "bt-max-peers",
    bt_metadata_only = "bt-metadata-only",
    bt_min_crypto_level = "bt-min-crypto-level",
    bt_prioritize_piece = "bt-prioritize-piece",
    bt_remove_unselected_file = "bt-remove-unselected-file",
    bt_request_peer_speed_limit = "bt-request-peer-speed-limit",
    bt_require_crypto = "bt-require-crypto",
    bt_save_metadata = "bt-save-metadata",
    bt_seed_unverified = "bt-seed-unverified",
    bt_stop_timeout = "bt-stop-timeout",
    bt_tracker = "bt-tracker",
    bt_tracker_connect_timeout = "bt-tracker-connect-timeout",
    bt_tracker_interval = "bt-tracker-interval",
    bt_tracker_timeout = "bt-tracker-timeout",
    check_integrity = "check-integrity",
    checksum = "checksum",
    conditional_get = "conditional-get",
    connect_timeout = "connect-timeout",
    content_disposition_default_utf8 = "content-disposition-default-utf8",
    continue = "continue",
    dir = "dir",
    dry_run = "dry-run",
    enable_http_keep_alive = "enable-http-keep-alive",
    enable_http_pipelining = "enable-http-pipelining",
    enable_mmap = "enable-mmap",
    enable_peer_exchange = "enable-peer-exchange",
    file_allocation = "file-allocation",
    follow_metalink = "follow-metalink",
    follow_torrent = "follow-torrent",
    force_save = "force-save",
    ftp_passwd = "ftp-passwd",
    ftp_pasv = "ftp-pasv",
    ftp_proxy = "ftp-proxy",
    ftp_proxy_passwd = "ftp-proxy-passwd",
    ftp_proxy_user = "ftp-proxy-user",
    ftp_reuse_connection = "ftp-reuse-connection",
    ftp_type = "ftp-type",
    ftp_user = "ftp-user",
    gid = "gid",
    hash_check_only = "hash-check-only",
    header = "header",
    http_accept_gzip = "http-accept-gzip",
    http_auth_challenge = "http-auth-challenge",
    http_no_cache = "http-no-cache",
    http_passwd = "http-passwd",
    http_proxy = "http-proxy",
    http_proxy_passwd = "http-proxy-passwd",
    http_proxy_user = "http-proxy-user",
    http_user = "http-user",
    https_proxy = "https-proxy",
    https_proxy_passwd = "https-proxy-passwd",
    https_proxy_user = "https-proxy-user",
    index_out = "index-out",
    lowest_speed_limit = "lowest-speed-limit",
    max_connection_per_server = "max-connection-per-server",
    max_download_limit = "max-download-limit",
    max_file_not_found = "max-file-not-found",
    max_mmap_limit = "max-mmap-limit",
    max_resume_failure_tries = "max-resume-failure-tries",
    max_tries = "max-tries",
    max_upload_limit = "max-upload-limit",
    metalink_base_uri = "metalink-base-uri",
    metalink_enable_unique_protocol = "metalink-enable-unique-protocol",
    metalink_language = "metalink-language",
    metalink_location = "metalink-location",
    metalink_os = "metalink-os",
    metalink_preferred_protocol = "metalink-preferred-protocol",
    metalink_version = "metalink-version",
    min_split_size = "min-split-size",
    no_file_allocation_limit = "no-file-allocation-limit",
    no_netrc = "no-netrc",
    no_proxy = "no-proxy",
    out = "out",
    parameterized_uri = "parameterized-uri",
    pause = "pause",
    pause_metadata = "pause-metadata",
    piece_length = "piece-length",
    proxy_method = "proxy-method",
    realtime_chunk_checksum = "realtime-chunk-checksum",
    referer = "referer",
    remote_time = "remote-time",
    remove_control_file = "remove-control-file",
    retry_wait = "retry-wait",
    reuse_uri = "reuse-uri",
    rpc_save_upload_metadata = "rpc-save-upload-metadata",
    seed_ratio = "seed-ratio",
    seed_time = "seed-time",
    select_file = "select-file",
    split = "split",
    ssh_host_key_md = "ssh-host-key-md",
    stream_piece_selector = "stream-piece-selector",
    timeout = "timeout",
    uri_selector = "uri-selector",
    use_head = "use-head",
    user_agent = "user-agent"
}

M.ErrorCodeTbl = {
    [1] = "unknown",
    [2] = "timeout",
    [3] = "resource not found",
    [4] = "resources not found",
    [5] = "download speed too slow",
    [6] = "network problem",
    [7] = "unfinished downloads",
    [8] = "resume not supported",
    [9] = "not enough disk space",
    [10] = "piece length differ",
    [11] = "was downloading the same file",
    [12] = "was downloading the same info hash",
    [13] = "file already existed",
    [14] = "renaming failed",
    [15] = "could not open existing file",
    [16] = "could not create new or truncate existing",
    [17] = "file I/O",
    [18] = "could not create directory",
    [19] = "name resolution failed",
    [20] = "could not parse metalink",
    [21] = "FTP command failed",
    [22] = "HTTP response header was bad or unexpected",
    [23] = "too many redirections",
    [24] = "HTTP authorization failed",
    [25] = "could not parse bencoded file",
    [26] = "torrent was corrupted or missing informations",
    [27] = "bad magnet URI",
    [28] = "bad/unrecognized option or unexpected option argument",
    [29] = "the remote server was unable to handle the request",
    [30] = 'could not parse JSON-RPC request'
}

-- get_rpc_context_from_env reads RPC context table from environment variable.
---@return aria2rpc.RpcContext
function M.get_rpc_context_from_env()
    local rpc_url = os.getenv("LESTORANT_RPC_URL") or ""
    local secret = os.getenv("LESTORANT_RPC_SECRET")
    local method = os.getenv("LESTORANT_RPC_METHOD") or M.DEFAULT_HTTP_METHOD

    local proxy = nil
    local parsed = url.parse(rpc_url)
    local scheme = parsed and parsed.scheme
    if scheme == "http" then
        proxy = os.getenv("http_proxy")
    elseif scheme == "https" then
        proxy = os.getenv("https_proxy")
    end

    return {
        rpc_url = rpc_url,
        secret = secret,
        proxy = proxy,
        method = method,
    } --[[@as aria2rpc.RpcContext]]
end

---@param context aria2rpc.RpcContext
---@param method string # RPC method name
---@param params? any[] # RPC parameter list
---@return table? resp
---@return string? err
local function call_method_inner(context, method, params)
    local copy_param = {}

    if context.secret then
        table.insert(copy_param, TOKEN_PREFIX .. context.secret)
    end

    if params then
        for _, value in ipairs(params) do
            table.insert(copy_param, value)
        end
    end

    local json_body = json.encode {
        jsonrpc = "2.0",
        id = "foo",
        method = 'aria2.' .. method,
        params = copy_param,
    }

    log:traceln("send RPC to ", context.rpc_url, context.proxy and (" with proxy " .. context.proxy) or "")

    local resp_tbl = {} ---@type string[]

    ---@type LuaSocket.HTTPRequest
    local req = {
        url = context.rpc_url,
        sink = ltn12.sink.table(resp_tbl),
        source = ltn12.source.string(json_body),
        method = context.method or M.DEFAULT_HTTP_METHOD,
        proxy = context.proxy,
        headers = {
            ["content-length"] = tostring(#json_body),
            ["content-type"] = "application/x-www-form-urlencoded",
        }
    }

    local ok, req_ok, code, _, status = pcall(network_util.request, req)
    if not ok then
        return nil, "failed to make request to url: " .. req.url
    end

    if not req_ok then
        return nil, "request failed with: " .. tostring(code)
    end

    if code ~= 200 then
        return nil, ("request status: %s"):format(status)
    end

    local resp_data = table.concat(resp_tbl)
    local parse_err = nil
    local parse_ok, data = xpcall(json.decode, function(err) parse_err = err end, resp_data)
    if not parse_ok then
        return nil, "invalid JSON response: " .. (parse_err or "unknown error")
    end

    return data, nil
end

-- call_method sends a RPC request then returns parsed response body and a possible
-- error message.
---@param context aria2rpc.RpcContext # Meta data for RPC request
---@param method string # RPC method name
---@param params? any[] # RPC parameter list
---@param on_result? fun(result: any) # Optional callback that gets called with `result` field in response JSON when request successed.
---@param on_error? fun(err: string) # Optional callback that gets called with error message when request failed.
---@return table? resp
---@return string? err
function M.call_method(context, method, params, on_result, on_error)
    local resp, err = call_method_inner(context, method, params)

    if on_result and resp then
        on_result(resp and resp.result)
    end

    if on_error and not resp then
        on_error(err or "unknown")
    end

    return resp, err
end

---@param context aria2rpc.RpcContext
---@param target string # URI or path to local file
---@param options table<aria2rpc.UriOptions, string> # Download option for this task
---@return table? resp
---@return string? err
function M.add_task(context, target, options)
    local resp, resp_err

    if target:match("^%S-://") or target:sub(1, 7) == "magnet:" then
        resp, resp_err = M.call_method(context, "addUri", { { target }, options })
    else
        local file, io_err = io.open(target, "rb")
        if not file then
            resp_err = io_err or "I/O error"
        else
            local read_flag = (_VERSION == "Lua 5.1" or _VERSION == "Lua 5.2") and "*a" or "a"
            local data = file:read(read_flag)
            file:close()

            local encoded = base64.encode(data)

            if target:sub(-8) == ".torrent" then
                resp, resp_err = M.call_method(context, "addTorrent", { encoded, {}, options })
            elseif target:sub(-6) == ".meta4" or target:sub(-9) == ".metalink" then
                resp, resp_err = M.call_method(context, "addMetalink", { encoded, options })
            end
        end
    end

    return resp, resp_err
end

return M
