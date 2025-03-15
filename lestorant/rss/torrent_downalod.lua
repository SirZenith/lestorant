local xml2lua = require "xml2lua"
local handler = require "xmlhandler.tree"

local feed_loader = require "lestorant.rss.feed_loader"
local fs_util = require "lestorant.utils.fs_util"
local log_util = require "lestorant.utils.log_util"
local network_util = require "lestorant.utils.network_util"

local M = {}

local log = log_util.Logger:new("torrent_download")

---@class rss.RssSource
---@field name string # Display name of this feed.
---@field url string | string[] # Feed URL. If a list of URL is given, they will be tried in sequence until one of them returns a OK response.
---@field loader_type? string # Feed parser type used to read RSS content. Default value is `basic`.

---@class rss.RssSubscription
---@field name string
---@field pattern string
---@field exclude_pattern? string # Article should not match this pattern.
---@field torrent_dl_dir? string # Path of directory to put its updated torrent.
---@field content_dl_dir? string # Path of directory to downloads torrent's content. When this field is missing, the same value as `torrent_dl_dir` will be used.

local MIMETYPE_TORRENT = "application/x-bittorrent"

M.DEFAULT_OUTPUT_DIR = "."

-- fetch_feed takes URL string or URL list, try those URL in sequence until one
-- of then returns successed response.
---@param target string | string[]
---@param config? network_util.FetchArgs
---@return string? content
---@return string? err
function M.fetch_feed(target, config)
    local resp, resp_err
    local target_type = type(target)

    if target_type == "string" then
        log:traceln("visiting ", target)
        resp, resp_err = network_util.fetch_url(target, config)
    elseif target_type == "table" then
        for _, tgt in ipairs(target) do
            log:traceln("visiting ", tgt)
            resp, resp_err = network_util.fetch_url(tgt, config)
            if resp then
                break
            end
        end
    end

    return resp, resp_err
end

---@param xml string # XML content to be parsed
---@param loader_type? rss.LoaderType # Loader type used to parse XML content, default value is `basic`
---@return rss.Article[]? articles
---@return string? err
function M.load_rss_articles(xml, loader_type)
    loader_type = loader_type or feed_loader.LoaderType.basic

    local rss_handler = handler:new()
    local parser = xml2lua.parser(rss_handler)
    local parse_ok = pcall(parser.parse, parser, xml)
    if not parse_ok then
        return nil, "failed to parse XML content"
    end

    local articles, load_err = feed_loader.load_feed(loader_type, rss_handler.root);
    if not articles then
        return nil, load_err or "failed to load feed content"
    end

    return articles, nil
end

---@class rss.TorrentTask
---@field title string # Title of original article.
---@field url string # Download URL of torrent.
---@field is_uri? boolean # Wheather thi task is a magnet URI instead of downloaded file.
---@field output_name string # Save path of torrent file.
---@field content_dl_dir string # Directory for downloading torrent's content.

-- get_updated_torrent_list reads throung article list, and looks for torrents
-- hasn't been downloaded.
-- New torrent URLs are returned as a list.
---@param articles rss.Article[]
---@param sub_list rss.RssSubscription[]
---@param default_torrent_dl_dir? string # Default download path of torrent file, if not specified by subscription config.
---@return rss.TorrentTask[] tasks
function M.get_updated_torrent_list(articles, sub_list, default_torrent_dl_dir)
    local result = {} ---@type rss.TorrentTask[]

    for _, article in ipairs(articles) do
        local target_type = article.enclosure.type
        local torrent_url = article.enclosure.url

        if target_type == MIMETYPE_TORRENT and torrent_url ~= "" then
            for _, sub in ipairs(sub_list) do
                local title = article.title
                local match = title:match(sub.pattern)
                local exclude = sub.exclude_pattern and title:match(sub.exclude_pattern)

                if match and not exclude then
                    local output_dir = sub.torrent_dl_dir or default_torrent_dl_dir or M.DEFAULT_OUTPUT_DIR
                    local output_title = fs_util.replace_invalid_path_char(title)
                    local output_name = fs_util.join(output_dir, output_title .. ".torrent")

                    local file, err = io.open(output_name, "r")
                    local is_exists = file ~= nil and err == nil
                    if file then file:close() end

                    local is_uri = torrent_url:sub(1, 7) == "magnet:"

                    if not is_exists then
                        ---@type rss.TorrentTask
                        local task = {
                            title = title,
                            url = torrent_url,
                            is_uri = is_uri,
                            output_name = output_name,
                            content_dl_dir = sub.content_dl_dir or output_dir,
                        }
                        table.insert(result, task)
                    end

                    break
                end
            end
        end
    end

    return result
end

---@param task rss.TorrentTask
---@param config? network_util.FetchArgs
---@return string? err
function M.fetch_torrent(task, config)
    if task.is_uri then
        -- raw URI task needs no download
        return
    end

    local file, open_err = io.open(task.output_name, "wb")
    if not file then
        return ("failed to open torrent file %s: %s"):format(task.output_name, open_err)
    end

    local resp, resp_err = network_util.fetch_url(task.url, config)
    if not resp then
        file:close()
        return resp_err or "download failed"
    end

    local _, write_err = file:write(resp)
    if write_err then
        file:close()
        return write_err
    end

    file:close()

    return nil
end

---@param func? function
---@param ... any
local function try_call(func, ...)
    if func then
        func(...)
    end
end

-- download_torrents finds torrent line from articles and download them.
---@param tasks rss.TorrentTask[]
---@param config? network_util.FetchArgs
---@param on_result? fun(task: rss.TorrentTask, err?: string)
function M.fetch_torrent_list(tasks, config, on_result)
    for _, task in ipairs(tasks) do
        local err = M.fetch_torrent(task, config)
        try_call(on_result, task, err)
    end
end

---@param src rss.RssSource
---@param config lestorant.Config
---@param sub_list rss.RssSubscription[]
---@param on_result? fun(task?: rss.TorrentTask, err?: string)
function M.update_source(src, config, sub_list, on_result)
    log:traceln("updating ", src.name)

    local fetch_args = config --[[@as network_util.FetchArgs]]

    local xml, feed_err = M.fetch_feed(src.url, fetch_args)
    if not xml then
        try_call(on_result, nil, feed_err or "unknown feed request error")
        return
    end

    log:traceln("fetch successed")

    local loader_type = src.loader_type or feed_loader.DEFAULT_LOADER_TYPE
    local articles, load_err = M.load_rss_articles(xml, loader_type)
    if not articles then
        try_call(on_result, nil, load_err or "unknown RSS load error")
        return
    end

    local article_cnt = #articles
    log:infoln("source ", src.name, " responded with ", article_cnt, " ", article_cnt > 1 and "articles" or "article")

    local default_torrent_dl_dir = config.output_dir or M.DEFAULT_OUTPUT_DIR
    local tasks = M.get_updated_torrent_list(articles, sub_list, default_torrent_dl_dir)
    local task_cnt = #tasks
    if task_cnt > 0 then
        log:infoln("found ", task_cnt, " new ", task_cnt > 1 and "torrents" or "torrent")
        M.fetch_torrent_list(tasks, fetch_args, on_result)
    end
end

---@param src_list rss.RssSource[]
---@param config lestorant.Config
---@param sub_list rss.RssSubscription[]
---@param on_result? fun(task?: rss.TorrentTask, err?: string)
function M.update_source_list(src_list, config, sub_list, on_result)
    for _, src in ipairs(src_list) do
        M.update_source(src, config, sub_list, on_result)
    end
end

return M
