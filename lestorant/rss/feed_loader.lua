local log_util = require "lestorant.utils.log_util"

local log = log_util.Logger:new("feed_loader");

local M = {}

---@class rss.GUID
---@field id string
---@field is_perma_link boolean

---@class rss.Enclosure
---@field url string
---@field type string

---@class rss.Article
---@field title string
---@field link string
---@field guid rss.GUID
---@field enclosure rss.Enclosure

---@alias rss.LoaderFunc fun(root: table): rss.Article[]?, string?

---@enum rss.LoaderType
local LoaderType = {
    basic = "basic",
}

M.LoaderType = LoaderType
M.DEFAULT_LOADER_TYPE = LoaderType.basic

-- get_node tries to get target node with a sequences of child path.
---@param root table
---@param ... string
---@return any?
---@return string? err
local function get_node(root, ...)
    local node = root ---@type any
    local err = nil ---@type string?

    for _, name in ipairs { ... } do
        if type(node) ~= "table" then
            node = nil
            err = "child " .. name .. "is not indexable"
            break;
        end

        local child = node[name]
        if not child then
            node = nil
            err = "cannot find child named " .. name
            break
        end

        node = child
    end

    return node, err
end

---@generic T
---@param node table
---@param attr string
---@param default T
---@return T
local function try_get_attr(node, attr, default)
    local tbl = node._attr
    if type(tbl) ~= "table" then
        return default
    end

    local value = tbl[attr]

    if type(value) == "nil" then
        return default
    end

    return value
end

---@param item table
---@return rss.Article?
---@return string? err
local function parse_article_item_basic(item)
    local guid, err = get_node(item, "guid")
    if type(guid) ~= "table" then
        return nil, err or "child guid is not a table"
    end

    local enclosure = get_node(item, "enclosure")
    if type(enclosure) ~= "table" then
        return nil, err or "child enclosure is not a table"
    end

    ---@type rss.Article
    local article = {
        title = item.title or "unknown",
        link = item.link or "unknown",
        guid = {
            id = guid[1] or "",
            is_perma_link = try_get_attr(guid, "isPermaLink", false)
        },
        enclosure = {
            url = try_get_attr(enclosure, "url", ""),
            type = try_get_attr(enclosure, "type", ""),
        },
    }

    return article, nil
end

---@type table<rss.LoaderType, rss.LoaderFunc>
local loader_tbl = {
    [LoaderType.basic] = function(root)
        local item_list, node_err = get_node(root, "rss", "channel", "item")
        if not item_list then
            return nil, node_err
        end

        if type(item_list) ~= "table" then
            return nil, "`item` node is not a list"
        end

        ---@type rss.Article[]
        local articles = {};
        for i, item in ipairs(item_list) do
            if type(item) == "table" then
                local article, item_err = parse_article_item_basic(item)
                if article then
                    table.insert(articles, article)
                else
                    log:warnln("failed parsing #", i, " with error: ", item_err or "unknown")
                end
            else
                log:warnln("invalid item at index #", i, " is skipped")
            end
        end

        return articles, nil
    end
}

-- load_feed reads parsed XML tree and extract article infos from feed content.
---@param loader_type rss.LoaderType # loader type for given feead content
---@param root table # root table of parsed feed XML
---@return rss.Article[]? articles
---@return string? err
function M.load_feed(loader_type, root)
    local loader = loader_tbl[loader_type]
    if not loader then
        return nil, "unknown loader type"
    end

    return loader(root)
end

return M
