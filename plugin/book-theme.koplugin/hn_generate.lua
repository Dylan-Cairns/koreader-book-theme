-- Turn the theme plus classified candidates into one deterministic stylesheet.
-- The same book, theme and candidate set always produce byte-identical CSS, so
-- KOReader's rendering hash does not churn between openings.
--
-- The theme owns body and heading type; KOReader keeps base size, line spacing,
-- margins and contrast. That is why no rule here sets a body font size.

local Theme = require("hn_theme")

local Generate = {}

-- Vertical metrics are fixed per role. Relative sizes come from the theme; a
-- role's line height and margins stay stable so a font change alone does not
-- reflow the page beyond the intended family.
local ROLE_METRICS = {
    part = {line_height = "1.2", margin = "1.6rem 0 0.8rem"},
    chapter = {line_height = "1.25", margin = "1.7rem 0 0.65rem"},
    section = {line_height = "1.3", margin = "1.5rem 0 0.45rem"},
    minor = {line_height = "1.35", margin = "1.35rem 0 0.35rem"},
}

local REAL_HEADINGS = {
    {selectors = {"h1"}, level = 1},
    {selectors = {"h2"}, level = 2},
    {selectors = {"h3"}, level = 3},
    {selectors = {"h4", "h5", "h6"}, level = 4},
}

local DESCENDANT_RESET = {
    "    font-size: inherit !important;",
    "    font-weight: inherit !important;",
    "    line-height: inherit !important;",
}

local function unique_sorted(selectors)
    local seen, result = {}, {}
    for _, selector in ipairs(selectors) do
        if not seen[selector] then
            seen[selector] = true
            result[#result + 1] = selector
        end
    end
    table.sort(result)
    return result
end

local function family_declaration(role)
    return "    font-family: \"" .. role.family .. "\" !important;"
end

local function quote_declarations(role)
    return {
        family_declaration(role),
        "    font-weight: " .. role.weight .. " !important;",
        "    font-style: " .. (role.style or "normal") .. " !important;",
    }
end

local function heading_declarations(level, role)
    local metrics = ROLE_METRICS[Theme.role_for_level(level)]
    return {
        family_declaration(role),
        "    font-weight: " .. role.weight .. " !important;",
        "    font-style: " .. (role.style or "normal") .. " !important;",
        "    font-size: " .. role.size .. " !important;",
        "    line-height: " .. metrics.line_height .. " !important;",
        "    margin: " .. metrics.margin .. " !important;",
        "    text-align: " .. (role.align or "left") .. " !important;",
        "    text-transform: " .. (role.case == "upper" and "uppercase" or "none") .. " !important;",
        "    letter-spacing: " .. (role.spacing or "normal") .. " !important;",
        "    text-indent: 0 !important;",
        "    hyphens: none !important;",
        "    page-break-after: avoid !important;",
    }
end

local function append_rule(lines, selectors, declarations, hint)
    lines[#lines + 1] = table.concat(selectors, ",\n") .. " {"
    for _, declaration in ipairs(declarations) do
        lines[#lines + 1] = declaration
    end
    if hint then lines[#lines + 1] = hint end
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""
end

function Generate.generate(candidates, options)
    options = options or {}
    local theme = options.theme
    if type(theme) ~= "table" then theme = Theme.defaults() end
    candidates = candidates or {}

    local body = theme.body or {}
    local roles = theme.roles or {}
    local quote_role = roles.quote or {}
    local toc_hints = theme.toc_hints ~= false

    local heading_selectors = {}
    local quote_selectors = {}
    local page_break_selectors = {}
    local seen_heading, seen_quote = {}, {}

    for _, candidate in ipairs(candidates) do
        local selector = candidate.selector
        if selector and selector ~= "" then
            if candidate.role == "quote" then
                if not seen_quote[selector] then
                    seen_quote[selector] = true
                    quote_selectors[#quote_selectors + 1] = selector
                end
            elseif not seen_heading[selector] then
                seen_heading[selector] = true
                local level = tonumber(candidate.level) or 2
                level = math.max(1, math.min(6, math.floor(level)))
                heading_selectors[level] = heading_selectors[level] or {}
                heading_selectors[level][#heading_selectors[level] + 1] = selector
                if candidate.page_break and options.include_page_break ~= false then
                    page_break_selectors[#page_break_selectors + 1] = selector
                end
            end
        end
    end

    local lines = {
        "/* book-theme v2: per-book typography; theme " .. Theme.hash(theme) .. ". */",
        "",
        "body {",
        family_declaration(body),
        "    font-weight: " .. body.weight .. " !important;",
        "}",
        "",
        "*, *::before, *::after {",
        "    font-family: inherit !important;",
        "}",
        "",
        "pre, code, kbd, samp, tt {",
        "    font-family: monospace !important;",
        "}",
        "",
        "p, li, dd, dt, blockquote {",
        "    font-family: inherit !important;",
        "    font-weight: inherit !important;",
        "    line-height: inherit !important;",
        "}",
        "",
        "blockquote {",
    }
    for _, declaration in ipairs(quote_declarations(quote_role)) do
        lines[#lines + 1] = declaration
    end
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""

    -- Real headings are always themed, even in a book with no pseudo-headings.
    for _, heading in ipairs(REAL_HEADINGS) do
        local role = roles[Theme.role_for_level(heading.level)]
        append_rule(lines, heading.selectors, heading_declarations(heading.level, role))

        -- Publisher spans inside a real heading get the same reset as detected
        -- pseudo-headings, so a clean book and a converted book behave alike.
        local descendants = {}
        for _, selector in ipairs(heading.selectors) do
            descendants[#descendants + 1] = selector .. " *"
        end
        append_rule(lines, descendants, DESCENDANT_RESET)
    end

    -- Detected pseudo-headings share the role declarations; only they get a
    -- ToC hint, because the hint would not be valid on a real heading.
    for level = 1, 6 do
        local selectors = unique_sorted(heading_selectors[level] or {})
        if #selectors > 0 then
            local role = roles[Theme.role_for_level(level)]
            local hint = toc_hints and ("    -cr-hint: toc-level" .. level .. ";") or nil
            append_rule(lines, selectors, heading_declarations(level, role), hint)

            -- Publisher spans inside a title must not keep their own size or
            -- weight. The selector itself keeps the theme declarations.
            local descendants = {}
            for _, selector in ipairs(selectors) do
                descendants[#descendants + 1] = selector .. " *"
            end
            append_rule(lines, descendants, DESCENDANT_RESET)
        end
    end

    quote_selectors = unique_sorted(quote_selectors)
    if #quote_selectors > 0 then
        append_rule(lines, quote_selectors, quote_declarations(quote_role))
        local descendants = {}
        for _, selector in ipairs(quote_selectors) do
            descendants[#descendants + 1] = selector .. " *"
        end
        append_rule(lines, descendants, {
            "    font-weight: inherit !important;",
        })
    end

    page_break_selectors = unique_sorted(page_break_selectors)
    if #page_break_selectors > 0 then
        append_rule(lines, page_break_selectors, {
            "    page-break-before: always !important;",
        })
    end

    return table.concat(lines, "\n")
end

return Generate
