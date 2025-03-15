local M = {}

local FORBIDDEN_CHAR_REPLACEMENT = {
    ["<"] = "〈",
    [">"] = "〉",
    [":"] = "：",
    ["\""] = "“",
    ["/"] = "／",
    ["\\"] = "＼",
    ["|"] = "｜",
    ["?"] = "？",
    ["*"] = "＊",
}

local forbidden_list = {}
local need_escape = { ["?"] = true, ["*"] = true }
for k in pairs(FORBIDDEN_CHAR_REPLACEMENT) do
    if need_escape[k] then
        table.insert(forbidden_list, "%")
    end
    table.insert(forbidden_list, k)
end

local FORBIDDEN_PATT = "[" .. table.concat(forbidden_list) .. "]"

local PATH_SEP = package.config:sub(1, 1)

-- replace_invalid_path_char replace all forbidden characters in path with its
-- full width version.
---@param str string
function M.replace_invalid_path_char(str)
    return str:gsub(FORBIDDEN_PATT, function(c)
        return FORBIDDEN_CHAR_REPLACEMENT[c] or ""
    end)
end

---@param base string
---@param ... string
function M.join(base, ...)
    return table.concat({ base, ... }, PATH_SEP)
end

return M
