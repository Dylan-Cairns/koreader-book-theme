-- Pure helpers shared by the parser, classifier and CSS generator.
-- No KOReader dependencies: this file runs under the host LuaJIT tests too.

local Util = {}

function Util.trim(text)
    if not text then return "" end
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Util.split_whitespace(text)
    local parts = {}
    for part in (text or ""):gmatch("%S+") do
        parts[#parts + 1] = part
    end
    return parts
end

function Util.starts_with(text, prefix)
    return text:sub(1, #prefix) == prefix
end

function Util.ends_with(text, suffix)
    return suffix == "" or text:sub(-#suffix) == suffix
end

function Util.dirname(path)
    return (path or ""):match("^(.*)/[^/]*$") or ""
end

function Util.basename(path)
    return (path or ""):match("([^/]*)$") or ""
end

function Util.join_path(base, relative)
    if not relative then return "" end
    if relative:sub(1, 1) == "/" then
        return Util.normalize_path(relative)
    end
    return Util.normalize_path((base or "") .. "/" .. relative)
end

-- Normalise an archive path: forward slashes, no empty or "." segments,
-- and ".." resolved without climbing above the archive root.
function Util.normalize_path(path)
    if not path or path == "" then return "" end
    path = path:gsub("\\", "/")
    local absolute = path:sub(1, 1) == "/"
    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part == ".." then
            if #parts > 0 and parts[#parts] ~= ".." then
                table.remove(parts)
            elseif not absolute then
                parts[#parts + 1] = ".."
            end
        elseif part ~= "." and part ~= "" then
            parts[#parts + 1] = part
        end
    end
    local result = table.concat(parts, "/")
    if absolute then return "/" .. result end
    return result
end

function Util.url_decode(text)
    if not text then return "" end
    return (text:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

local ENTITIES = {
    amp = "&", lt = "<", gt = ">", quot = '"', apos = "'",
    nbsp = " ", ndash = "-", mdash = "-", hellip = "...",
    lsquo = "'", rsquo = "'", ldquo = '"', rdquo = '"',
}

local function codepoint_to_utf8(codepoint)
    if codepoint < 0x80 then
        return string.char(codepoint)
    elseif codepoint < 0x800 then
        return string.char(0xC0 + math.floor(codepoint / 0x40), 0x80 + codepoint % 0x40)
    elseif codepoint < 0x10000 then
        return string.char(
            0xE0 + math.floor(codepoint / 0x1000),
            0x80 + math.floor(codepoint / 0x40) % 0x40,
            0x80 + codepoint % 0x40)
    elseif codepoint <= 0x10FFFF then
        return string.char(
            0xF0 + math.floor(codepoint / 0x40000),
            0x80 + math.floor(codepoint / 0x1000) % 0x40,
            0x80 + math.floor(codepoint / 0x40) % 0x40,
            0x80 + codepoint % 0x40)
    end
    return "?"
end

function Util.decode_entities(text)
    if not text then return "" end
    text = text:gsub("&#x(%x+);", function(hex)
        return codepoint_to_utf8(tonumber(hex, 16))
    end)
    text = text:gsub("&#(%d+);", function(decimal)
        return codepoint_to_utf8(tonumber(decimal, 10))
    end)
    text = text:gsub("&([%a]+);", function(name)
        return ENTITIES[name:lower()] or ("&" .. name .. ";")
    end)
    return text
end

-- Parse the attributes in an opening tag. The input may be the whole tag
-- ("<p class=\"x\">") or just its inside ("p class=\"x\"").
function Util.parse_attrs(tag)
    local attrs = {}
    if not tag then return attrs end
    local text = tag
    if text:sub(1, 1) == "<" then text = text:sub(2, -2) end
    local tag_name = text:match("^%s*([%w_:.-]+)")
    local pos = 1
    if tag_name then pos = (text:find(tag_name, 1, true) or 1) + #tag_name end
    while pos <= #text do
        local start_pos, end_pos, name = text:find("([%w_:.-]+)%s*=%s*", pos)
        if not start_pos then break end
        local quote = text:sub(end_pos + 1, end_pos + 1)
        local value
        if quote == '"' or quote == "'" then
            local close = text:find(quote, end_pos + 2, true)
            if not close then break end
            value = text:sub(end_pos + 2, close - 1)
            pos = close + 1
        else
            local value_end = text:find("%s", end_pos + 1) or (#text + 1)
            value = text:sub(end_pos + 1, value_end - 1)
            pos = value_end
        end
        attrs[name:lower()] = Util.decode_entities(value)
    end
    return attrs
end

function Util.table_contains(list, value)
    for _, item in ipairs(list or {}) do
        if item == value then return true end
    end
    return false
end

function Util.shallow_copy(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

return Util
