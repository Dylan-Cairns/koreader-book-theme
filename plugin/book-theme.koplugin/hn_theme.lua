-- Theme model for Book Theme. A theme is a plain table that describes the
-- document's type: the body face and weight, one style per heading role, and a
-- quote role. Everything here is pure Lua and deterministic. Validation is the
-- boundary between stored settings and CSS injection, and the canonical form
-- feeds the per-book cache key (a theme change invalidates cached styles).

local Theme = {}

local ROLE_ORDER = {"part", "chapter", "section", "minor", "quote"}

local TOP_FIELDS = {version = true, body = true, roles = true, toc_hints = true}

-- Allowed fields per role. The role is the unit of validation: a field that
-- would not be rendered by the generator is rejected instead of ignored.
local ROLE_FIELDS = {
    body = {family = true, weight = true},
    part = {family = true, weight = true, style = true, size = true,
        case = true, align = true, spacing = true},
    chapter = {family = true, weight = true, style = true, size = true,
        case = true, align = true, spacing = true},
    section = {family = true, weight = true, style = true, size = true,
        case = true, align = true, spacing = true},
    minor = {family = true, weight = true, style = true, size = true,
        case = true, align = true, spacing = true},
    quote = {family = true, weight = true, style = true},
}

-- Presence requirements. `style` is optional on heading roles and defaults to
-- normal; `spacing` is optional everywhere.
local REQUIRED = {
    body = {"family", "weight"},
    part = {"family", "weight", "size", "case", "align"},
    chapter = {"family", "weight", "size", "case", "align"},
    section = {"family", "weight", "size", "case", "align"},
    minor = {"family", "weight", "size", "case", "align"},
    quote = {"family", "weight", "style"},
}

local WEIGHTS = {normal = true, bold = true}
local STYLES = {normal = true, italic = true}
local CASES = {none = true, upper = true}
local ALIGNS = {left = true, center = true}

local FUNCTION = {
    family = "font family name",
    weight = "font weight",
    style = "font style",
    size = "font size",
    case = "text case",
    align = "text alignment",
    spacing = "letter spacing",
}

function Theme.defaults()
    return {
        version = 1,
        body = {family = "EB Garamond", weight = "normal"},
        roles = {
            part = {family = "Alegreya Sans", weight = "bold", size = "1.45rem",
                case = "none", align = "left"},
            chapter = {family = "Alegreya Sans", weight = "bold", size = "1.30rem",
                case = "none", align = "left"},
            section = {family = "Alegreya Sans", weight = "bold", size = "1.15rem",
                case = "none", align = "left"},
            minor = {family = "Alegreya Sans", weight = "bold", size = "0.95rem",
                case = "upper", align = "left", spacing = "0.05em"},
            quote = {family = "EB Garamond", weight = "normal", style = "italic"},
        },
        toc_hints = true,
    }
end

local function family_problem(value)
    if type(value) ~= "string" or value == "" then
        return "must be a non-empty font family name"
    end
    if #value > 64 then return "must be 64 characters or fewer" end
    if not value:match("^[%w%s%-_%.]+$") then
        return "must contain only letters, digits, spaces, '-', '_' and '.'"
    end
    return nil
end

local function size_problem(value)
    if type(value) ~= "string" then return "must be a rem size string" end
    local number = value:match("^(%d%.%d+)rem$")
    if not number then return "must look like 1.20rem" end
    number = tonumber(number)
    if number < 0.6 or number > 2.5 then
        return "must be between 0.6rem and 2.5rem"
    end
    return nil
end

local function spacing_problem(value)
    if type(value) ~= "string" then return "must be an em spacing string" end
    if not value:match("^%d%.%d+em$") then return "must look like 0.05em" end
    return nil
end

local function enum_problem(value, allowed, description)
    if type(value) ~= "string" or not allowed[value] then
        return "must be " .. description
    end
    return nil
end

local function enum_names(allowed)
    local names = {}
    for name in pairs(allowed) do names[#names + 1] = name end
    table.sort(names)
    return table.concat(names, " or ")
end

local function field_problem(field, value)
    if field == "family" then return family_problem(value) end
    if field == "weight" then return enum_problem(value, WEIGHTS, enum_names(WEIGHTS)) end
    if field == "style" then return enum_problem(value, STYLES, enum_names(STYLES)) end
    if field == "size" then return size_problem(value) end
    if field == "case" then return enum_problem(value, CASES, enum_names(CASES)) end
    if field == "align" then return enum_problem(value, ALIGNS, enum_names(ALIGNS)) end
    -- `spacing = nil` is the documented way to clear the field.
    if field == "spacing" then
        if value == nil then return nil end
        return spacing_problem(value)
    end
    return "is not a " .. (FUNCTION[field] or "theme") .. " field"
end

local function check_role(problems, path, values, role)
    local allowed = ROLE_FIELDS[role]
    for field, value in pairs(values) do
        if not allowed[field] then
            problems[#problems + 1] = "unknown field '" .. path .. "." .. tostring(field) .. "'"
        else
            local problem = field_problem(field, value)
            if problem then
                problems[#problems + 1] = path .. "." .. field .. " " .. problem
            end
        end
    end
    for _, field in ipairs(REQUIRED[role]) do
        if values[field] == nil then
            problems[#problems + 1] = path .. "." .. field .. " is missing"
        end
    end
    return problems
end

-- Returns a list of problems, never throws. An empty list means the theme is
-- safe to serialise into CSS.
function Theme.validate(theme)
    local problems = {}
    if type(theme) ~= "table" then
        return {"theme must be a table"}
    end
    for key in pairs(theme) do
        if not TOP_FIELDS[key] then
            problems[#problems + 1] = "unknown theme field '" .. tostring(key) .. "'"
        end
    end
    local version = theme.version
    if type(version) ~= "number" or version < 1 or version % 1 ~= 0 then
        problems[#problems + 1] = "version must be a positive integer"
    end
    if type(theme.toc_hints) ~= "boolean" then
        problems[#problems + 1] = "toc_hints must be true or false"
    end
    if type(theme.body) ~= "table" then
        problems[#problems + 1] = "body must be a table"
    else
        check_role(problems, "body", theme.body, "body")
    end
    if type(theme.roles) ~= "table" then
        problems[#problems + 1] = "roles must be a table"
    else
        for role in pairs(theme.roles) do
            if role == "body" or not ROLE_FIELDS[role] then
                problems[#problems + 1] = "unknown role '" .. tostring(role) .. "'"
            end
        end
        for _, role in ipairs(ROLE_ORDER) do
            local values = theme.roles[role]
            if type(values) ~= "table" then
                problems[#problems + 1] = "roles." .. role .. " must be a table"
            else
                check_role(problems, "roles." .. role, values, role)
            end
        end
    end
    return problems
end

local function merge_role(target, stored, path, role, problems)
    local allowed = ROLE_FIELDS[role]
    -- Sorted so the first reported problem is stable.
    local fields = {}
    for field in pairs(stored) do fields[#fields + 1] = field end
    table.sort(fields)
    for _, field in ipairs(fields) do
        local value = stored[field]
        if not allowed[field] then
            problems[#problems + 1] = "unknown field '" .. path .. "." .. tostring(field) .. "'"
        else
            local problem = field_problem(field, value)
            if problem then
                problems[#problems + 1] = path .. "." .. field .. " " .. problem
            else
                target[field] = value
            end
        end
    end
end

-- Merge a stored settings table over the defaults. Every invalid leaf is
-- reported and replaced by its default, so the returned theme is always safe
-- to generate CSS from. Never throws.
function Theme.load(stored)
    local theme = Theme.defaults()
    local problems = {}
    if stored == nil then return theme, problems end
    if type(stored) ~= "table" then
        return theme, {"stored theme must be a table"}
    end

    local keys = {}
    for key in pairs(stored) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        if not TOP_FIELDS[key] then
            problems[#problems + 1] = "unknown theme field '" .. tostring(key) .. "'"
        end
    end

    local version = stored.version
    if version ~= nil then
        if type(version) == "number" and version >= 1 and version % 1 == 0 then
            theme.version = version
        else
            problems[#problems + 1] = "version must be a positive integer"
        end
    end
    if stored.toc_hints ~= nil then
        if type(stored.toc_hints) == "boolean" then
            theme.toc_hints = stored.toc_hints
        else
            problems[#problems + 1] = "toc_hints must be true or false"
        end
    end
    if stored.body ~= nil then
        if type(stored.body) == "table" then
            merge_role(theme.body, stored.body, "body", "body", problems)
        else
            problems[#problems + 1] = "body must be a table"
        end
    end
    if stored.roles ~= nil then
        if type(stored.roles) == "table" then
            for role in pairs(stored.roles) do
                if role == "body" or not ROLE_FIELDS[role] then
                    problems[#problems + 1] = "unknown role '" .. tostring(role) .. "'"
                end
            end
            for _, role in ipairs(ROLE_ORDER) do
                local values = stored.roles[role]
                if values ~= nil then
                    if type(values) == "table" then
                        merge_role(theme.roles[role], values, "roles." .. role, role, problems)
                    else
                        problems[#problems + 1] = "roles." .. role .. " must be a table"
                    end
                end
            end
        else
            problems[#problems + 1] = "roles must be a table"
        end
    end
    return theme, problems
end

-- One `k=v;` line per leaf, sorted by key. Values are already strings, so this
-- is byte-stable and independent of table insertion order.
function Theme.canonical(theme)
    local lines = {}
    local body = theme.body or {}
    for field in pairs(ROLE_FIELDS.body) do
        if body[field] ~= nil then
            lines[#lines + 1] = "body." .. field .. "=" .. tostring(body[field]) .. ";"
        end
    end
    local roles = theme.roles or {}
    for _, role in ipairs(ROLE_ORDER) do
        local values = roles[role] or {}
        local fields = {}
        for field in pairs(ROLE_FIELDS[role]) do fields[#fields + 1] = field end
        table.sort(fields)
        for _, field in ipairs(fields) do
            local value = values[field]
            -- A heading role without an explicit style renders as normal.
            if field == "style" and value == nil and role ~= "quote" then
                value = "normal"
            end
            if value ~= nil then
                lines[#lines + 1] = "roles." .. role .. "." .. field .. "=" .. tostring(value) .. ";"
            end
        end
    end
    lines[#lines + 1] = "toc_hints=" .. tostring(theme.toc_hints ~= false) .. ";"
    lines[#lines + 1] = "version=" .. tostring(theme.version or 1) .. ";"
    table.sort(lines)
    return table.concat(lines, "\n")
end

local FNV_OFFSET = 2166136261
local FNV_PRIME = 16777619
local MODULO = 4294967296

-- XOR two 8-bit values without the LuaJIT bit library.
local function xor_byte(left, right)
    local result, place = 0, 1
    for _ = 1, 8 do
        local left_bit = left % 2
        local right_bit = right % 2
        if left_bit ~= right_bit then result = result + place end
        left = (left - left_bit) / 2
        right = (right - right_bit) / 2
        place = place * 2
    end
    return result
end

-- FNV-1a 32-bit. The multiplication is split into 16-bit halves so every
-- intermediate value stays exactly representable in a double.
local function fnv1a(text)
    local hash = FNV_OFFSET
    for index = 1, #text do
        local low = hash % 256
        hash = hash - low + xor_byte(low, text:byte(index))
        local high = math.floor(hash / 65536)
        hash = ((high * FNV_PRIME) % 65536 * 65536 + (hash % 65536) * FNV_PRIME) % MODULO
    end
    return hash
end

function Theme.hash(theme)
    return string.format("%08x", fnv1a(Theme.canonical(theme)))
end

local LEVEL_ROLES = {
    [1] = "part", [2] = "chapter", [3] = "section",
    [4] = "minor", [5] = "minor", [6] = "minor",
}

function Theme.role_for_level(level)
    if type(level) ~= "number" then return "chapter" end
    level = math.floor(level)
    if level < 1 then level = 1 elseif level > 6 then level = 6 end
    return LEVEL_ROLES[level]
end

-- Body is edited through the same call as a heading role, but it lives at the
-- top level of the theme rather than under `roles`.
local function role_path(role)
    return role == "body" and "body" or ("roles." .. role)
end

-- Return a new validated theme with one role field changed, or nil and a
-- problem list when the role, field or value is not allowed. This is the only
-- write path for the UI; it never mutates the theme it was given.
function Theme.set_role(theme, role, field, value)
    local fields = ROLE_FIELDS[role]
    if not fields then
        return nil, {"unknown role '" .. tostring(role) .. "'"}
    end
    if not fields[field] then
        return nil, {"unknown field '" .. role_path(role) .. "." .. tostring(field) .. "'"}
    end
    local problem = field_problem(field, value)
    if problem then
        return nil, {role_path(role) .. "." .. field .. " " .. problem}
    end
    local result = Theme.load(theme)
    if role == "body" then
        result.body[field] = value
    else
        result.roles[role][field] = value
    end
    return result
end

-- Ordered as the menu presents them; body is edited separately.
Theme.ROLE_ORDER = ROLE_ORDER

-- Plain English labels, deliberately without gettext: this module has no
-- KOReader dependency. main.lua passes them through `_()` when displaying.
Theme.ROLE_LABELS = {
    body = "Body",
    part = "Part heading",
    chapter = "Chapter heading",
    section = "Section heading",
    minor = "Minor heading",
    quote = "Quote / epigraph",
}

-- One-line summary of a role for the status screen. Optional fields are only
-- mentioned when they differ from the generator's defaults, so a default theme
-- stays short and the output is stable for tests.
function Theme.describe(theme, role)
    if type(theme) ~= "table" then return "" end
    if role == "body" then
        local body = theme.body
        if type(body) ~= "table" then return "" end
        return tostring(body.family or "?") .. ", " .. tostring(body.weight or "?")
    end
    if not ROLE_FIELDS[role] then return "" end
    local values = type(theme.roles) == "table" and theme.roles[role] or nil
    if type(values) ~= "table" then return "" end
    local parts = {
        tostring(values.family or "?"),
        tostring(values.weight or "?"),
    }
    if values.size then parts[#parts + 1] = values.size end
    if values.style and (role == "quote" or values.style ~= "normal") then
        parts[#parts + 1] = values.style
    end
    if values.case == "upper" then parts[#parts + 1] = "uppercase" end
    if values.align == "center" then parts[#parts + 1] = "centered" end
    return table.concat(parts, ", ")
end

return Theme
