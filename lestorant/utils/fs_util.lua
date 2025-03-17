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

-- read_all reads all content of given file.
---@param path string
---@return string? content
---@return string? err
function M.read_all(path)
    local file, io_err = io.open(path, "rb")
    if not file then
        return nil, io_err or "I/O error"
    end

    local read_flag = (_VERSION == "Lua 5.1" or _VERSION == "Lua 5.2") and "*a" or "a"
    local data = file:read(read_flag)
    file:close()

    return data, nil
end

return M
