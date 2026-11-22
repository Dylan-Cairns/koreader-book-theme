-- Theme model for Book Theme. The reader-facing settings are just two font
-- families: the body face and the heading face. Weights, sizes, case,
-- alignment and spacing are fixed, tested defaults -- a reader who does not
-- want to tinker gets a good document, and there is no per-role control that
-- can produce an unrenderable combination. Everything here is pure Lua and
-- deterministic. Validation is the boundary between stored settings and CSS
-- injection, and the canonical form feeds the per-book cache key (a font
-- change invalidates cached styles).

local Theme = {}

local ROLE_ORDER = {"part", "chapter", "section", "minor", "quote"}
local HEADING_ROLES = {"part", "chapter", "section", "minor"}

-- Stored settings are exactly these two keys.
local FONT_FIELDS = {body_font = true, heading_font = true}

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

Theme.DEFAULT_FONTS = {body = "EB Garamond", heading = "Alegreya Sans"}

-- The resolved theme the generator consumes. `roles` is the whole typographic
-- spec: only `family` is ever changed by the UI. Part and chapter titles are
-- centred because that is the book convention (Standard Ebooks centres every
-- heading; a chapter opener that starts at the left margin reads as body text
-- on a small screen). Section and minor headings stay at the left margin,
-- where they function as in-text subheads.
function Theme.defaults()
    return {
        version = 1,
        body = {family = Theme.DEFAULT_FONTS.body, weight = "normal"},
        roles = {
            part = {family = Theme.DEFAULT_FONTS.heading, weight = "bold", size = "1.45rem",
                case = "none", align = "center"},
            chapter = {family = Theme.DEFAULT_FONTS.heading, weight = "bold", size = "1.30rem",
                case = "none", align = "center"},
            section = {family = Theme.DEFAULT_FONTS.heading, weight = "bold", size = "1.15rem",
                case = "none", align = "left"},
            minor = {family = Theme.DEFAULT_FONTS.heading, weight = "bold", size = "0.95rem",
                case = "upper", align = "left", spacing = "0.05em"},
            quote = {family = Theme.DEFAULT_FONTS.body, weight = "normal", style = "italic"},
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
    return nil
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

-- Read the two families a resolved theme encodes. A malformed table yields
-- nil values rather than an error; the menu simply shows nothing checked.
function Theme.fonts(theme)
    theme = theme or Theme.defaults()
    local body = type(theme.body) == "table" and theme.body or {}
    local roles = type(theme.roles) == "table" and theme.roles or {}
    local chapter = type(roles.chapter) == "table" and roles.chapter or {}
    return {body = body.family, heading = chapter.family}
end

-- Build a resolved theme from the two families. A missing family keeps its
-- default; an invalid one is reported and keeps its default too, so the
-- caller never gets a theme it cannot render.
function Theme.from_fonts(fonts)
    local theme = Theme.defaults()
    local problems = {}
    fonts = type(fonts) == "table" and fonts or {}

    if fonts.body ~= nil then
        local problem = family_problem(fonts.body)
        if problem then
            problems[#problems + 1] = "body font " .. problem
        else
            theme.body.family = fonts.body
            -- Quotes and epigraphs read in the body face.
            theme.roles.quote.family = fonts.body
        end
    end

    if fonts.heading ~= nil then
        local problem = family_problem(fonts.heading)
        if problem then
            problems[#problems + 1] = "heading font " .. problem
        else
            for _, role in ipairs(HEADING_ROLES) do
                theme.roles[role].family = fonts.heading
            end
        end
    end

    return theme, problems
end

-- The settings table to persist: only the two choices, never the derived
-- sizes and weights, so the stored shape stays small and readable.
function Theme.settings(theme)
    local fonts = Theme.fonts(theme)
    return {body_font = fonts.body, heading_font = fonts.heading}
end

-- Older builds stored a full role table. Read the body face and any heading
-- face that differs from the default so an existing customisation survives the
-- simplification; sizes, weights and the rest are intentionally dropped.
local function load_legacy(stored, theme, problems)
    if type(stored.body) == "table" and stored.body.family ~= nil then
        local problem = family_problem(stored.body.family)
        if problem then
            problems[#problems + 1] = "body.family " .. problem
        else
            theme.body.family = stored.body.family
            theme.roles.quote.family = stored.body.family
        end
    end
    if type(stored.roles) ~= "table" then return end
    for _, role in ipairs(HEADING_ROLES) do
        local values = stored.roles[role]
        if type(values) == "table" and values.family ~= nil
            and values.family ~= Theme.DEFAULT_FONTS.heading then
            local problem = family_problem(values.family)
            if problem then
                problems[#problems + 1] = "roles." .. role .. ".family " .. problem
            else
                for _, target in ipairs(HEADING_ROLES) do
                    theme.roles[target].family = values.family
                end
            end
        end
    end
end

-- Merge stored settings over the defaults. Every invalid value is reported and
-- replaced by its default, so the returned theme is always safe to generate
-- CSS from. Never throws.
function Theme.load(stored)
    if stored == nil then return Theme.defaults(), {} end
    if type(stored) ~= "table" then
        return Theme.defaults(), {"stored theme must be a table"}
    end

    if stored.body_font ~= nil or stored.heading_font ~= nil then
        local problems = {}
        local keys = {}
        for key in pairs(stored) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do
            if not FONT_FIELDS[key] then
                problems[#problems + 1] = "unknown theme field '" .. tostring(key) .. "'"
            end
        end
        local theme, font_problems = Theme.from_fonts({
            body = stored.body_font,
            heading = stored.heading_font,
        })
        for _, problem in ipairs(font_problems) do
            problems[#problems + 1] = problem
        end
        return theme, problems
    end

    local theme = Theme.defaults()
    local problems = {}
    load_legacy(stored, theme, problems)
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

return Theme
