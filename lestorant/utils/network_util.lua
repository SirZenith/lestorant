local ltn12 = require "ltn12"
local socket = require "socket"
local http = require "socket.http"
local url = require "socket.url"
local ssl = require "ssl"
local https = require "ssl.https"

local log_util = require "lestorant.utils.log_util"

local try = socket.try

local M = {}

local log = log_util.Logger:new("network_util")

local DEFAULT_SSL_CFG = {
    protocol = "any",
    options  = { "all", "no_sslv2", "no_sslv3", "no_tlsv1" },
    verify   = "none",
}
local DEFAULT_RETRY_CNT = 3

---@param target LuaSocket.URL
local function create_https_behind_proxy(target)
    local target_port = target.port or "443"
    local host_uri = ("%s:%s"):format(target.host, target_port)

    return function()
        local conn = {
            sock = socket.try(socket.tcp())
        }

        local st = getmetatable(conn.sock).__index.settimeout
        function conn:settimeout()
            return st(self.sock, https.TIMEOUT)
        end

        function conn:close()
            conn.sock:close()
        end

        -- Replace TCP's connection function
        function conn:connect(host, port)
            -- send CONNECT request to proxy server

            local sock = self.sock
            if not sock then
                return nil, "TCP socket not available"
            end

            try(sock:connect(host, port))

            local connect_request = string.format("CONNECT %s HTTP/1.1\r\nHost: %s\r\n\r\n", host_uri, host_uri)
            try(sock:send(connect_request))

            local response = socket.try(sock:receive())
            if not response or not response:match("HTTP/%d.%d 200") then
                return nil, "response from proxy server is invalid"
            end

            -- Upgrade connection to HTTPS

            local cfg = {}
            for key, value in pairs(DEFAULT_SSL_CFG) do
                cfg[key] = cfg[key] or value
            end
            cfg.mode = "client"

            local ssl_sock = try(ssl.wrap(sock, cfg))
            if not ssl_sock then
                return nil, "failed to create SSL wrapping"
            end

            ssl_sock:sni(host)
            ssl_sock:settimeout(https.TIMEOUT)
            try(ssl_sock:dohandshake())

            self.sock = ssl_sock

            local mt = getmetatable(ssl_sock)
            for name, method in pairs(mt.__index) do
                if type(method) == "function" then
                    conn[name] = function(s, ...)
                        return method(s.sock, ...)
                    end
                end
            end

            return 1
        end

        return conn
    end
end

---@param args LuaSocket.HTTPRequest
---@return string | number | nil ok
---@return string | number err_or_code
---@return table<string, string>? headers
---@return string? status
function M.request(args)
    local target, err = url.parse(args.url)
    if not target then
        return nil, err or "invalid URL", nil, nil
    end

    local req = {}
    for k, v in pairs(args) do
        req[k] = v
    end

    if target.scheme == "https" and req.proxy then
        req.create = create_https_behind_proxy(target)
    end

    return http.request(req)
end

---@param target string | LuaSocket.URL
---@param http_proxy? string
---@param https_proxy? string
---@return string? # picked proxy
function M.pick_proxy(target, http_proxy, https_proxy)
    if type(target) == "string" then
        local parsed = url.parse(target)
        if not parsed then
            return nil
        end

        target = parsed
    end

    local proxy
    local scheme = target.scheme
    if scheme == "http" then
        proxy = http_proxy
    elseif scheme == "https" then
        proxy = https_proxy
    end

    return proxy
end

---@class network_util.FetchArgs
---@field retry_cnt? integer
---@field http_proxy? string
---@field https_proxy? string

-- fetch_feed_single tries request RSS content from given URL
---@param target string
---@param config? network_util.FetchArgs
---@return string? content
---@return string? err
function M.fetch_url(target, config)
    local retry_cnt = config and config.retry_cnt
    if type(retry_cnt) ~= "number" or retry_cnt <= 0 then
        retry_cnt = DEFAULT_RETRY_CNT
    end

    local proxy = M.pick_proxy(
        target,
        config and config.http_proxy,
        config and config.https_proxy
    )

    if proxy then
        log:traceln("fetching ", target, " with proxy ", proxy)
    end

    local resp, resp_err
    for i = 1, retry_cnt do
        log:traceln(target, ", try cnt: ", i)

        local resp_tbl = {};
        ---@type LuaSocket.HTTPRequest
        local req = {
            url = target,
            sink = ltn12.sink.table(resp_tbl),
            proxy = proxy,
        }

        local ok, req_ok, err = pcall(M.request, req)

        if not ok then
            resp_err = "request paniced"
        elseif not req_ok then
            resp_err = type(err) == "string" and err or "request failed"
        else
            resp, resp_err = table.concat(resp_tbl), nil
            break
        end
    end

    return resp, resp_err
end

return M
