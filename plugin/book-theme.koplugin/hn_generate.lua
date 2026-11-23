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
-- reflow the page beyond the intended family. The space below a chapter or
-- part title is roughly a blank line, because the opening text must not look
-- glued to it (a real defect seen on device 2026-11-22); section and minor
-- headings sit inside prose and stay tighter. Values are stored per side so
-- the chapter-number pair can reuse the top margin of one and the bottom
-- margin of the other.
local ROLE_METRICS = {
    part = {line_height = "1.2", margin_top = "2.8rem", margin_bottom = "1.8rem"},
    chapter = {line_height = "1.25", margin_top = "2.4rem", margin_bottom = "1.5rem"},
    section = {line_height = "1.3", margin_top = "1.9rem", margin_bottom = "0.8rem"},
    minor = {line_height = "1.35", margin_top = "1.5rem", margin_bottom = "0.5rem"},
}

-- A chapter number -- whether it is a standalone heading or glued inside the
-- title's own heading -- is one style: a secondary line above the title, in
-- the heading face, larger than body text but clearly smaller than the title.
-- The owner saw two treatments on device (a block line for standalone numbers,
-- an inline one for glued numbers) and asked for one; the supplied book-design
-- reference also requires the title to dominate the number.
local NUMBER_SIZE = "1.05rem"
local NUMBER_GAP = "0.3rem"

-- Old-style (text) figures are the default in EB Garamond and Cormorant
-- Garamond, and they look wrong on a chapter number. crengine does not support
-- font-feature-settings, but it does map font-variant-numeric: lining-nums to
-- HarfBuzz +lnum, so this is the one form that works on device.
local LINING_FIGURES = "    font-variant-numeric: lining-nums !important;"

local ROLE_ORDER = {"part", "chapter", "section", "minor"}

local function role_metrics(level)
    return ROLE_METRICS[Theme.role_for_level(level)]
end

local function margin_value(metrics)
    return metrics.margin_top .. " 0 " .. metrics.margin_bottom
end

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
    local metrics = role_metrics(level)
    return {
        family_declaration(role),
        "    font-weight: " .. role.weight .. " !important;",
        "    font-style: " .. (role.style or "normal") .. " !important;",
        "    font-size: " .. role.size .. " !important;",
        LINING_FIGURES,
        "    line-height: " .. metrics.line_height .. " !important;",
        "    margin: " .. margin_value(metrics) .. " !important;",
        "    text-align: " .. (role.align or "left") .. " !important;",
        "    text-transform: " .. (role.case == "upper" and "uppercase" or "none") .. " !important;",
        "    letter-spacing: " .. (role.spacing or "normal") .. " !important;",
        "    text-indent: 0 !important;",
        "    hyphens: none !important;",
        "    page-break-after: avoid !important;",
    }
end

-- The heading tag in a selector ("h2.ch_title1" -> 2) is enough to pick the
-- matching role metrics; a selector without one is treated as a chapter.
local function selector_level(selector)
    local tag = selector:match("^(h%d)")
    return tag and tonumber(tag:sub(2)) or 2
end

local function group_selectors(selectors, groups)
    for _, selector in ipairs(selectors) do
        local role = Theme.role_for_level(selector_level(selector))
        groups[role] = groups[role] or {}
        groups[role][#groups[role] + 1] = selector
    end
    return groups
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
        -- Publisher CSS usually carries these; when it is disabled a note
        -- reference would otherwise render at full body size on the baseline.
        "sup, sub {",
        "    font-size: 0.7em !important;",
        "    line-height: 0 !important;",
        "}",
        "",
        "sup { vertical-align: super !important; }",
        "",
        "sub { vertical-align: sub !important; }",
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

    -- Chapter-number rules come after the heading rules on purpose: a number
    -- pair can itself be a detected pseudo-heading, and these declarations must
    -- win the tie. Both forms of number -- a standalone heading and a span
    -- glued inside the title's heading -- get the same treatment: a secondary
    -- line above the title, in the heading face, larger than body text but
    -- clearly smaller than the title.
    local markers = options.markers or {}
    if #markers > 0 then
        append_rule(lines, unique_sorted(markers), {
            "    display: block !important;",
            "    font-family: inherit !important;",
            "    font-size: " .. NUMBER_SIZE .. " !important;",
            "    line-height: 1.15 !important;",
            "    margin: 0 0 " .. NUMBER_GAP .. " 0 !important;",
            LINING_FIGURES,
        })
    end

    -- A chapter number set as its own heading, immediately above the title
    -- heading. Both are one title block: keep the number's own top margin and
    -- its smaller size, remove the double gap between them, and leave the
    -- space below the title intact so the opening text does not crowd it. Both
    -- rules repeat the full margin shorthand, so later rules cannot leave one
    -- side at its default.
    local number_groups = group_selectors(options.number_headings or {}, {})
    local title_groups = group_selectors(options.number_titles or {}, {})
    for _, role in ipairs(ROLE_ORDER) do
        local metrics = ROLE_METRICS[role]
        if number_groups[role] then
            append_rule(lines, unique_sorted(number_groups[role]), {
                "    font-size: " .. NUMBER_SIZE .. " !important;",
                "    line-height: 1.15 !important;",
                "    margin: " .. metrics.margin_top .. " 0 " .. NUMBER_GAP .. " 0 !important;",
                LINING_FIGURES,
            })
        end
        if title_groups[role] then
            append_rule(lines, unique_sorted(title_groups[role]), {
                "    margin: 0 0 " .. metrics.margin_bottom .. " 0 !important;",
            })
        end
    end

    -- Some publishers pull the opening paragraph up under the chapter title
    -- with a negative top margin on that block (OUP uses `div.top { margin:
    -- -1em ... }`), which silently eats the space the title rule just set. The
    -- scan records the block after each chapter title; zeroing its top margin
    -- keeps the title's own bottom margin intact without touching other blocks.
    local followers = unique_sorted(options.title_followers or {})
    if #followers > 0 then
        append_rule(lines, followers, {
            "    margin-top: 0 !important;",
        })
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

-- Rebuild a stylesheet from the compact inputs the scan stored in the cache
-- (`result.generation`). This is what lets a font change reach the open book
-- without reading the EPUB again; it must produce byte-identical CSS to the
-- scan that recorded those inputs. A damaged cache yields nil, never an error.
local function selector_list(value)
    if value == nil then return {} end
    if type(value) ~= "table" then return nil end
    return value
end

function Generate.from_generation(generation, theme)
    if type(generation) ~= "table" or type(generation.candidates) ~= "table" then
        return nil
    end
    local markers = selector_list(generation.markers)
    local number_headings = selector_list(generation.number_headings)
    local number_titles = selector_list(generation.number_titles)
    local title_followers = selector_list(generation.title_followers)
    if not markers or not number_headings or not number_titles or not title_followers then
        return nil
    end
    return Generate.generate(generation.candidates, {
        theme = theme,
        markers = markers,
        number_headings = number_headings,
        number_titles = number_titles,
        title_followers = title_followers,
    })
end

return Generate
