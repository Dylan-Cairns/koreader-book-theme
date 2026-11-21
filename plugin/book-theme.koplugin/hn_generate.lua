-- Turn classified candidates into a deterministic stylesheet. The same book
-- and plugin version always produce byte-identical CSS, so KOReader's
-- rendering hash does not churn between openings.

local Generate = {}

local DEFAULT_FONT = '"Alegreya Sans", "Noto Sans", sans-serif'

local LEVELS = {
    [1] = {size = "1.45rem", weight = "500", line = "1.2", margin = "1.6rem 0 0.8rem",
        upper = false, spacing = nil},
    [2] = {size = "1.28rem", weight = "500", line = "1.25", margin = "1.7rem 0 0.65rem",
        upper = false, spacing = nil},
    [3] = {size = "1.1rem", weight = "500", line = "1.3", margin = "1.5rem 0 0.45rem",
        upper = false, spacing = nil},
    [4] = {size = "0.98rem", weight = "500", line = "1.35", margin = "1.35rem 0 0.35rem",
        upper = true, spacing = "0.05em"},
    [5] = {size = "0.9rem", weight = "500", line = "1.4", margin = "1.2rem 0 0.3rem",
        upper = true, spacing = "0.07em"},
    [6] = {size = "0.9rem", weight = "500", line = "1.4", margin = "1.2rem 0 0.3rem",
        upper = true, spacing = "0.07em"},
}

local function sorted_unique(selectors)
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

function Generate.generate(candidates, options)
    options = options or {}
    if not candidates or #candidates == 0 then return nil end

    local font_family = options.font_family or DEFAULT_FONT
    local by_level = {}
    local page_break_selectors = {}
    for _, candidate in ipairs(candidates) do
        local level = math.max(1, math.min(6, candidate.level or 2))
        by_level[level] = by_level[level] or {}
        by_level[level][#by_level[level] + 1] = candidate.selector
        if candidate.page_break and options.include_page_break ~= false then
            page_break_selectors[#page_break_selectors + 1] = candidate.selector
        end
    end

    local all_selectors = {}
    for _, selectors in pairs(by_level) do
        for _, selector in ipairs(selectors) do
            all_selectors[#all_selectors + 1] = selector
        end
    end
    all_selectors = sorted_unique(all_selectors)
    if #all_selectors == 0 then return nil end

    local lines = {
        "/* heading-normalizer v1: generated per-book heading styles.",
        "   Body text is styled by KOReader; this file only targets detected headings. */",
        "",
    }

    local reset = {}
    for _, selector in ipairs(all_selectors) do
        reset[#reset + 1] = selector
        reset[#reset + 1] = selector .. " *"
    end
    lines[#lines + 1] = table.concat(reset, ",\n") .. " {"
    lines[#lines + 1] = "    font-family: " .. font_family .. " !important;"
    lines[#lines + 1] = "    font-style: normal !important;"
    lines[#lines + 1] = "    text-indent: 0 !important;"
    lines[#lines + 1] = "    hyphens: none !important;"
    lines[#lines + 1] = "    page-break-after: avoid !important;"
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""

    local descendant_reset = {}
    for _, selector in ipairs(all_selectors) do
        descendant_reset[#descendant_reset + 1] = selector .. " *"
    end
    lines[#lines + 1] = table.concat(descendant_reset, ",\n") .. " {"
    lines[#lines + 1] = "    font-size: inherit !important;"
    lines[#lines + 1] = "    font-weight: inherit !important;"
    lines[#lines + 1] = "    line-height: inherit !important;"
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""

    for level = 1, 6 do
        local selectors = by_level[level]
        if selectors and #selectors > 0 then
            local style = LEVELS[level]
            selectors = sorted_unique(selectors)
            lines[#lines + 1] = table.concat(selectors, ",\n") .. " {"
            lines[#lines + 1] = "    font-size: " .. style.size .. " !important;"
            lines[#lines + 1] = "    font-weight: " .. style.weight .. " !important;"
            lines[#lines + 1] = "    line-height: " .. style.line .. " !important;"
            lines[#lines + 1] = "    margin: " .. style.margin .. " !important;"
            lines[#lines + 1] = "    text-align: left !important;"
            if style.upper then
                lines[#lines + 1] = "    text-transform: uppercase !important;"
            end
            if style.spacing then
                lines[#lines + 1] = "    letter-spacing: " .. style.spacing .. " !important;"
            end
            if options.toc_hints ~= false then
                lines[#lines + 1] = "    -cr-hint: toc-level" .. level .. ";"
            end
            lines[#lines + 1] = "}"
            lines[#lines + 1] = ""
        end
    end

    if #page_break_selectors > 0 then
        page_break_selectors = sorted_unique(page_break_selectors)
        lines[#lines + 1] = table.concat(page_break_selectors, ",\n") .. " {"
        lines[#lines + 1] = "    page-break-before: always !important;"
        lines[#lines + 1] = "}"
        lines[#lines + 1] = ""
    end

    return table.concat(lines, "\n")
end

return Generate
