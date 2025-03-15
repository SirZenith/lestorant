local M = {}

local DATA_SIZE_UNIT = { "B", "KiB", "MiB", "GiB", "TiB" }
local DATA_SIZE_SHIFT = 1024 -- conversion factor between successive 2 size units

-- abbrev formats given data size into string using units like B, KiB, etc.
-- A carry threshold can be specified to control when a larger unit should be used.
-- If after conversion, result size is no smaller then threshold value, then larger
-- unit will be taken.
---@param value number # data size in bytes
---@param threshold number # a carry threshold, normally greater then 0 and less than or equal to 1.
---@return string # human readable format of data size
function M.file_size_abbr(value, threshold)
    threshold = threshold or 1
    local result = 0
    local unit = '';

    for i = 1, #DATA_SIZE_UNIT do
        result = value
        unit = DATA_SIZE_UNIT[i]

        value = value / DATA_SIZE_SHIFT
        if value < threshold then
            break;
        end
    end

    local format_str = math.floor(result) == result and "%d%s" or "%.2f%s"

    return format_str:format(result, unit)
end

---@class aria2rpc.TimeConversionInfo
---@field modular integer # modular for unit conversion
---@field optional? boolean # if this value can be omited when its less than zero
---@field need_zero_padding? boolean # if this value needs to be displayed with leading 0 when its less than 10
---@field tail_str string # this value should be displayed followed by this string
---@field tail_str_plural? string # use this stirng instead of `tail_str` when value is larger then 1.

---@type aria2rpc.TimeConversionInfo[]
local TIME_CONVERSION_INFO_LIST = {
    -- seconds
    {
        modular = 60,
        need_zero_padding = true,
        tail_str = ":",
    },
    -- minutes
    {
        modular = 60,
        need_zero_padding = true,
        tail_str = ":",
    },
    -- hours
    {
        modular = 24,
        need_zero_padding = true,
        tail_str = ":",
    },
    -- days
    {
        modular = 60,
        need_zero_padding = true,
        optional = true,
        tail_str = " day ",
        tail_str_plural = " days "
    },
}

-- to_hhmmss convers a duration value into time string in HH:MM:SS format.
---@param time number # time duration in seconds
---@return string
function M.to_hhmmss(time)
    local value = time
    local buffer = {}

    for _, info in ipairs(TIME_CONVERSION_INFO_LIST) do
        local extracted = value % info.modular
        value = (value - extracted) / info.modular

        if info.optional and extracted <= 0 then
            -- pass
        else
            table.insert(buffer, value > 1 and info.tail_str_plural or info.tail_str)
            table.insert(buffer, tostring(extracted))
            if value < 10 and info.need_zero_padding then
                table.insert(buffer, "0")
            end
        end
    end

    local total_cnt = #buffer
    for i = 1, math.floor(total_cnt / 2) do
        local temp = buffer[i]
        local target = total_cnt - i + 1
        buffer[i] = buffer[target]
        buffer[target] = temp
    end

    return table.concat(buffer)
end

-- compute_eta returns format ETA string with given parameters.
---@param download_speed number
---@param remaining_length number
---@return string
function M.compute_eta(download_speed, remaining_length)
    if download_speed <= 0 then
        return 'N/A'
    end

    return M.to_hhmmss(remaining_length / download_speed)
end

return M
