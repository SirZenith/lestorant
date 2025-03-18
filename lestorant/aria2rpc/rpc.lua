local base64 = require "base64"
local ltn12 = require "ltn12"
local url = require "socket.url"
local fs_util = require "lestorant.utils.fs_util"

local json = require "lestorant.utils.json"
local log_util = require "lestorant.utils.log_util"
local network_util = require "lestorant.utils.network_util"

local M = {}

local log = log_util.Logger:new("rpc")

local TOKEN_PREFIX = "token:"

-- Default http method used for RPC request.
M.DEFAULT_HTTP_METHOD = "POST"

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

---@enum aria2rpc.GlobalOptions
M.GlobalOptions = {
    bt_max_open_files               = "bt-max-open-files",
    download_result                 = "download-result",
    keep_unfinished_download_result = "keep-unfinished-download-result",
    log                             = "log",
    log_level                       = "log-level",
    max_concurrent_downloads        = "max-concurrent-downloads",
    max_download_result             = "max-download-result",
    max_overall_download_linmit     = "max-overall-download-limit",
    max_overall_upload_limit        = "max-overall-upload-limit",
    optimize_concurrent_downloads   = "optimize-concurrent-downloads",
    save_cookies                    = "save-cookies",
    save_session                    = "save-session",
    server_stat_of                  = "server-stat-of",
}

---@enum aria2rpc.TaskInfoKey
M.StatusKey = {
    gid = "gid",
    status = "status",
    total_length = "totalLength",
    completed_length = "completedLength",
    upload_length = "uploadLength",
    bitfield = "bitfield",
    download_speed = "downloadSpeed",
    upload_speed = "uploadSpeed",
    info_hash = "infoHash",
    num_seeders = "numSeeders",
    seeder = "seeder",
    piece_length = "pieceLength",
    num_pieces = "numPieces",
    connections = "connections",
    error_code = "errorCode",
    error_message = "errorMessage",
    followed_by = "followedBy",
    following = "following",
    belongs_to = "belongsTo",
    dir = "dir",
    files = "files",
    bittorrent = "bittorrent",
    verified_length = "verifiedLength",
    verify_integrity_pending = "verifyIntegrityPending",
}

---@enum aria2rpc.TaskStatus
M.TaskStatus = {
    active = "active",
    waiting = "waiting",
    paused = "paused",
    error = "error",
    complete = "complete",
    removed = "removed",
}

---@enum aria2rpc.TorrentFileMode
M.TorrentFileMode = {
    single = "single",
    multi = "multi",
}

---@enum aria2rpc.ChangePosHow
M.ChangePosHow = {
    pos_set = "POS_SET",
    pos_cur = "POS_CUR",
    pos_end = "POS_END",
}

---@class aria2rpc.TorrentInfoDict
---@field name? string

---@class aria2rpc.TaskTorrentInfo
---@field announceList string[][] # List of lists of announce URIs. If the torrent contains announce and no announce-list, announce is converted to the announce-list format.
---@field comment string # The comment of the torrent. comment.utf-8 is used if available.
---@field creationDate integer # The creation time of the torrent. The value is an integer since the epoch, measured in seconds.
---@field mode aria2rpc.TorrentFileMode # File mode of the torrent. The value is either single or multi.
---@field info aria2rpc.TorrentInfoDict

---@class aria2rpc.TaskUriInfo
---@field uri string
---@field status string

---@class aria2rpc.TaskFileInfo
---@field index string # Index of the file, starting at 1, in the same order as files appear in the multi-file torrent.
---@field path string # File path.
---@field length string # File size in bytes.
---@field completedLength string # Completed length of this file in bytes. Please note that it is possible that sum of completedLength is less than the completedLength returned by the aria2.tellStatus() method. This is because completedLength in aria2.getFiles() only includes completed pieces. On the other hand, completedLength in aria2.tellStatus() also includes partially completed pieces.
---@field selected string # true if this file is selected by --select-file option. If --select-file is not specified or this is single-file torrent or not a torrent download at all, this value is always true. Otherwise false.
---@field uris aria2rpc.TaskUriInfo[] # Returns a list of URIs for this file. The element type is the same struct used in the aria2.getUris() method.

---@class aria2rpc.TaskInfo
---@field gid string # GID of the download.
---@field status aria2rpc.TaskStatus # task status
---@field totalLength string # Total length of the download in bytes.
---@field completedLength string # Completed length of the download in bytes.
---@field uploadLength string # Uploaded length of the download in bytes.
---@field bitfield string # Hexadecimal representation of the download progress. The highest bit corresponds to the piece at index 0. Any set bits indicate loaded pieces, while unset bits indicate not yet loaded and/or missing pieces. Any overflow bits at the end are set to zero. When the download was not started yet, this key will not be included in the response.
---@field downloadSpeed string # Download speed of this download measured in bytes/sec.
---@field uploadSpeed string # Upload speed of this download measured in bytes/sec.
---@field infoHash? string # InfoHash. BitTorrent only.
---@field numSeeders? string # The number of seeders aria2 has connected to. BitTorrent only.
---@field seeder? string # true if the local endpoint is a seeder. Otherwise false. BitTorrent only.
---@field pieceLength string # Piece length in bytes.
---@field numPieces string # The number of pieces.
---@field connections string # The number of peers/servers aria2 has connected to.
---@field errorCode string # The code of the last error for this item, if any. The value is a string. The error codes are defined in the EXIT STATUS section. This value is only available for stopped/completed downloads.
---@field errorMessage string # The (hopefully) human readable error message associated to errorCode.
---@field followedBy string[] # List of GIDs which are generated as the result of this download. For example, when aria2 downloads a Metalink file, it generates downloads described in the Metalink (see the --follow-metalink option). This value is useful to track auto-generated downloads. If there are no such downloads, this key will not be included in the response.
---@field following string # The reverse link for followedBy. A download included in followedBy has this object's GID in its following value.
---@field belongsTo string # GID of a parent download. Some downloads are a part of another download. For example, if a file in a Metalink has BitTorrent resources, the downloads of ".torrent" files are parts of that parent. If this download has no parent, this key will not be included in the response.
---@field dir string # Directory to save files.
---@field files aria2rpc.TaskFileInfo[] # Returns the list of files. The elements of this list are the same structs used in aria2.getFiles() method.
---@field bittorrent? aria2rpc.TaskTorrentInfo
---@field verifiedLength integer # The number of verified number of bytes while the files are being hash checked. This key exists only when this download is being hash checked.
---@field verifyIntegrityPending boolean # true if this download is waiting for the hash check in a queue. This key exists only when this download is in the queue.

---@class aria2rpc.MethodCall
---@field methodName string
---@field params any[]

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

---@alias aria2rpc.RpcCallback fun(result?: any, err?: string)

---@class aria2rpc.RpcContext
---@field rpc_url string # RPC server URL
---@field secret? string # RPC secret
---@field proxy? string # proxy used in RPC request
---@field method? string # HTTP method used by RPC call
---@field _id_counter integer
---@field _rpc_callback_map table<string, aria2rpc.RpcCallback>
local RpcContext = {}
M.RpcContext = RpcContext

RpcContext.__index = RpcContext

---@param rpc_url string
---@return aria2rpc.RpcContext
function RpcContext:new(rpc_url)
    local this = setmetatable({}, self)

    this.rpc_url = rpc_url
    this._id_counter = 0
    this._rpc_callback_map = {}

    return this
end

-- new_from_env makes a new RPC context object, and populate its field with environment
-- variable.
---@return aria2rpc.RpcContext
function RpcContext:new_from_env()
    local rpc_url = os.getenv("LESTORANT_RPC_URL") or ""
    local this = self:new(rpc_url)

    this.secret = os.getenv("LESTORANT_RPC_SECRET")
    this.method = os.getenv("LESTORANT_RPC_METHOD") or M.DEFAULT_HTTP_METHOD

    local parsed = url.parse(this.rpc_url)
    local scheme = parsed and parsed.scheme
    if scheme == "http" then
        this.proxy = os.getenv("http_proxy")
    elseif scheme == "https" then
        this.proxy = os.getenv("https_proxy")
    end

    return this
end

---@param context aria2rpc.RpcContext
---@param id string # ID for this RPC call
---@param method string # RPC method name
---@param params? any[] # RPC parameter list
---@param on_result fun(context: aria2rpc.RpcContext, id: string, result?: any, err?: string)
local function call_method_inner(context, id, method, params, on_result)
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
        id = id,
        method = method,
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
        on_result(context, id, nil, "failed to make request to url: " .. req.url)
        return
    end

    if not req_ok then
        on_result(context, id, nil, "request failed with: " .. tostring(code))
        return
    end

    if code ~= 200 then
        on_result(context, id, nil, ("request status: %s"):format(status))
        return
    end

    local resp_data = table.concat(resp_tbl)
    local parse_ok, data = pcall(json.decode, resp_data)
    if not parse_ok then
        on_result(context, id, nil, "invalid JSON response: " .. (data or "unknown error"))
        return
    end

    on_result(context, id, data and data.result, nil)
end

-- call_method sends a RPC request then returns parsed response body and a possible
-- error message.
---@param method string # RPC method name
---@param params? any[] # RPC parameter list
---@param on_result? aria2rpc.RpcCallback
function RpcContext:call_method(method, params, on_result)
    local new_count = self._id_counter + 1
    self._id_counter = new_count
    local id = tostring(new_count)

    self._rpc_callback_map[id] = on_result

    call_method_inner(self, id, method, params, self._on_rpc_result)
end

---@param id string
---@param result? any
---@param err? string
function RpcContext:_on_rpc_result(id, result, err)
    local on_result = self._rpc_callback_map[id]
    if on_result then
        on_result(result, err)
    end
end

-- ----------------------------------------------------------------------------
-- Primitive Methods

-- ensure_options_tbl adds a dummy key to option table, incase it gets serialized
-- as JSON array.
---@param options? table
local function ensure_options_tbl(options)
    if not options then
        return
    end
    options.__is_tbl = true
end

---@param uris string[] # A list of URIs.
---@param options? table<aria2rpc.UriOptions, any> # a table of download options.
---@param position? integer # 0-base integer, new task will be inserted ot task queue at this index.
---@param on_result? aria2rpc.RpcCallback
function RpcContext:add_uri(uris, options, position, on_result)
    ensure_options_tbl(options)
    self:call_method("aria2.addUri", { uris, options, position }, on_result)
end

---@param torrent string # base64 encoded torrent file content.
---@param uris? string[] # URIs for Web-seeding.
---@param options? table<aria2rpc.UriOptions, any> # a table of download options.
---@param position? integer # 0-base integer, new task will be inserted ot task queue at this index.
---@param on_result? aria2rpc.RpcCallback
function RpcContext:add_torrent(torrent, uris, options, position, on_result)
    ensure_options_tbl(options)
    self:call_method("aria2.addTorrent", { torrent, uris, options, position }, on_result)
end

---@param metalink string # base64 encoded metalink file content.
---@param options? table<aria2rpc.UriOptions, any> # a table of download options.
---@param position? integer # 0-base integer, new task will be inserted ot task queue at this index.
---@param on_result? aria2rpc.RpcCallback
function RpcContext:add_metalink(metalink, options, position, on_result)
    ensure_options_tbl(options)
    self:call_method("aria2.addMetalink", { metalink, options, position }, on_result)
end

---@param gid string
---@param on_result? aria2rpc.RpcCallback
function RpcContext:remove(gid, on_result)
    self:call_method("aria2.remove", { gid }, on_result)
end

---@param gid string
---@param on_result? aria2rpc.RpcCallback
function RpcContext:force_remove(gid, on_result)
    self:call_method("aria2.forceRemove", { gid }, on_result)
end

---@param gid string
---@param on_result? aria2rpc.RpcCallback
function RpcContext:pause(gid, on_result)
    self:call_method("aria2.pause", { gid }, on_result)
end

---@param on_result? aria2rpc.RpcCallback
function RpcContext:pause_all(on_result)
    self:call_method("aria2.pauseAll", nil, on_result)
end

---@param gid string
---@param on_result? aria2rpc.RpcCallback
function RpcContext:force_pause(gid, on_result)
    self:call_method("aria2.forcePause", { gid }, on_result)
end

---@param on_result? aria2rpc.RpcCallback
function RpcContext:force_pause_all(on_result)
    self:call_method("aria2.forcePauseAll", nil, on_result)
end

---@param gid string
---@param on_result? aria2rpc.RpcCallback
function RpcContext:unpause(gid, on_result)
    self:call_method("aria2.unpause", { gid }, on_result)
end

---@param on_result? aria2rpc.RpcCallback
function RpcContext:unpause_all(on_result)
    self:call_method("aria2.unpauseAll", nil, on_result)
end

---@param gid string
---@param keys? aria2rpc.TaskInfoKey[]
---@param on_result? aria2rpc.RpcCallback
function RpcContext:tell_status(gid, keys, on_result)
    self:call_method("aria2.tellStatus", { gid, keys }, on_result)
end

---@param gid string
---@param on_result? aria2rpc.RpcCallback
function RpcContext:get_uris(gid, on_result)
    self:call_method("aria2.getUris", { gid }, on_result)
end

---@param gid string
---@param on_result? aria2rpc.RpcCallback
function RpcContext:get_files(gid, on_result)
    self:call_method("aria2.getFiles", { gid }, on_result)
end

---@param gid string
---@param on_result? aria2rpc.RpcCallback
function RpcContext:get_peers(gid, on_result)
    self:call_method("aria2.getPeers", { gid }, on_result)
end

---@param gid string
---@param on_result? aria2rpc.RpcCallback
function RpcContext:get_servers(gid, on_result)
    self:call_method("aria2.getServers", { gid }, on_result)
end

---@param keys? aria2rpc.TaskInfoKey[]
---@param on_result? aria2rpc.RpcCallback
function RpcContext:tell_active(keys, on_result)
    self:call_method("aria2.tellActive", { keys }, on_result)
end

---@param offset integer # Offset to the start of waiting queue. Negative values are allowed.
---@param num integer # Maxium entry to return.
---@param keys? aria2rpc.TaskInfoKey[]
---@param on_result? aria2rpc.RpcCallback
function RpcContext:tell_waiting(offset, num, keys, on_result)
    self:call_method("aria2.tellWaiting", { offset, num, keys }, on_result)
end

---@param offset integer # Offset to the start of waiting queue. Negative values are allowed.
---@param num integer # Maxium entry to return.
---@param keys? aria2rpc.TaskInfoKey[]
---@param on_result? aria2rpc.RpcCallback
function RpcContext:tell_stopped(offset, num, keys, on_result)
    self:call_method("aria2.tellStopped", { offset, num, keys }, on_result)
end

---@param gid string
---@param pos integer
---@param how aria2rpc.ChangePosHow
---@param on_result? aria2rpc.RpcCallback
function RpcContext:change_position(gid, pos, how, on_result)
    self:call_method("aria2.changePosition", { gid, pos, how }, on_result)
end

---@param gid any
---@param fileIndex integer
---@param del_uris string[]
---@param addUris string[]
---@param position? integer
---@param on_result? aria2rpc.RpcCallback
function RpcContext:change_uri(gid, fileIndex, del_uris, addUris, position, on_result)
    self:call_method("aria2.changeUri", { gid, fileIndex, del_uris, addUris, position }, on_result)
end

---@param gid string
---@param on_result? aria2rpc.RpcCallback
function RpcContext:get_option(gid, on_result)
    self:call_method("aria2.getOption", { gid }, on_result)
end

---@param gid any
---@param options table<aria2rpc.UriOptions, any>
---@param on_result? aria2rpc.RpcCallback
function RpcContext:change_option(gid, options, on_result)
    self:call_method("aria2.changeOption", { gid, options }, on_result)
end

---@param on_result? aria2rpc.RpcCallback
function RpcContext:get_global_option(on_result)
    self:call_method("aria2.getGlobalOption", nil, on_result)
end

---@param options table<aria2rpc.GlobalOptions, any>
---@param on_result? aria2rpc.RpcCallback
function RpcContext:change_global_option(options, on_result)
    self:call_method("aria2.changeGlobalOption", { options }, on_result)
end

---@param on_result? aria2rpc.RpcCallback
function RpcContext:get_global_stat(on_result)
    self:call_method("aria2.getGlobalStat", nil, on_result)
end

---@param on_result? aria2rpc.RpcCallback
function RpcContext:purge_download_result(on_result)
    self:call_method("aria2.purgeDownloadResult", nil, on_result)
end

---@param gid string
---@param on_result? aria2rpc.RpcCallback
function RpcContext:remove_download_result(gid, on_result)
    self:call_method("aria2.removeDownloadResult", { gid }, on_result)
end

---@param on_result? aria2rpc.RpcCallback
function RpcContext:get_version(on_result)
    self:call_method("aria2.getVersion", nil, on_result)
end

---@param on_result? aria2rpc.RpcCallback
function RpcContext:get_session_info(on_result)
    self:call_method("aria2.getSessionInfo", nil, on_result)
end

---@param on_result? aria2rpc.RpcCallback
function RpcContext:shutdown(on_result)
    self:call_method("aria2.shutdown", nil, on_result)
end

---@param on_result? aria2rpc.RpcCallback
function RpcContext:force_shutdown(on_result)
    self:call_method("aria2.forceShutdown", nil, on_result)
end

---@param on_result? aria2rpc.RpcCallback
function RpcContext:save_session(on_result)
    self:call_method("aria2.saveSession", nil, on_result)
end

---@param methods aria2rpc.MethodCall[]
---@param on_result? aria2rpc.RpcCallback
function RpcContext:multicall(methods, on_result)
    self:call_method("system.multicall", { methods }, on_result)
end

---@param on_result? aria2rpc.RpcCallback
function RpcContext:list_methods(on_result)
    self:call_method("system.listMethods", nil, on_result)
end

---@param on_result? aria2rpc.RpcCallback
function RpcContext:list_notification(on_result)
    self:call_method("system.listNotifications", nil, on_result)
end

-- ----------------------------------------------------------------------------
-- Secondary Methods

---@param path string # path to torrent file
---@param uris? any
---@param options? any
---@param position? any
---@param on_result? aria2rpc.RpcCallback
function RpcContext:add_torrent_file(path, uris, options, position, on_result)
    local data, io_err = fs_util.read_all(path)
    if not data then
        if on_result then on_result(nil, io_err or "I/O error") end
        return
    end

    self:add_torrent(base64.encode(data), uris, options, position, on_result)
end

---@param path string # path to torrent file
---@param options? any
---@param position? any
---@param on_result? aria2rpc.RpcCallback
function RpcContext:add_metalink_file(path, options, position, on_result)
    local data, io_err = fs_util.read_all(path)
    if not data then
        if on_result then on_result(nil, io_err or "I/O error") end
        return
    end

    self:add_metalink(base64.encode(data), options, position, on_result)
end

---@param target string # URI or path to local file
---@param options table<aria2rpc.UriOptions, string> # Download option for this task
---@param position? integer # 0-base integer, new task will be inserted ot task queue at this index
---@param on_result? aria2rpc.RpcCallback
function RpcContext:add_task(target, options, position, on_result)
    if target:match("^%S-://") or target:sub(1, 7) == "magnet:" then
        self:add_uri({ target }, options, position, on_result)
    elseif target:sub(-8) == ".torrent" then
        self:add_torrent_file(target, {}, options, position, on_result)
    elseif target:sub(-6) == ".meta4" or target:sub(-9) == ".metalink" then
        self:add_metalink_file(target, options, position, on_result)
    end
end

return M
