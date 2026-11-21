-- Orchestration: read the EPUB, parse its navigation and CSS, classify each
-- spine document and generate one stylesheet. All failures are contained in
-- the result so a malformed book can never stop the reader from opening.

local Epub = require("hn_epub")
local Html = require("hn_html")
local Css = require("hn_css")
local Classify = require("hn_classify")
local Generate = require("hn_generate")
local Theme = require("hn_theme")
local Util = require("hn_util")

local Scan = {}

local DEFAULTS = {
    max_documents = 400,
    max_html_bytes = 2 * 1024 * 1024,
    max_css_documents = 24,
    max_css_bytes = 2 * 1024 * 1024,
    min_layout_score = 38,
    max_candidates = 60,
}

-- Deterministic rule budget. A book-wide selector explosion is worse than no
-- styling, but a ToC rule is never dropped: the ToC is the book's own ground
-- truth and its selectors are exact (often one id per rule). The cap therefore
-- applies to inferred layout and semantic rules only, ranked by score and then
-- selector. Output order is preserved so the CSS stays deterministic.
local function limit_candidates(candidates, limit)
    if not limit then return candidates end
    local toc, inferred = {}, {}
    for _, candidate in ipairs(candidates) do
        if Util.table_contains(candidate.reasons, "toc") then
            toc[candidate] = true
        else
            inferred[#inferred + 1] = candidate
        end
    end
    if #inferred <= limit then return candidates end
    table.sort(inferred, function(left, right)
        if left.score ~= right.score then return left.score > right.score end
        return left.selector < right.selector
    end)
    local keep = {}
    for index = 1, limit do keep[inferred[index]] = true end
    local kept = {}
    for _, candidate in ipairs(candidates) do
        if keep[candidate] or toc[candidate] then kept[#kept + 1] = candidate end
    end
    return kept
end

local function read_limited(reader, path, limit, warnings)
    local content = Epub.read(reader, path)
    if not content then return nil end
    if #content > limit then
        warnings[#warnings + 1] = path .. " is larger than the scan limit"
        return nil
    end
    return content
end

function Scan.scan(reader, options)
    options = options or {}
    local settings = {}
    for key, value in pairs(DEFAULTS) do settings[key] = value end
    for key, value in pairs(options) do settings[key] = value end
    local theme = settings.theme
    if type(theme) ~= "table" then theme = Theme.defaults() end
    settings.theme = theme

    -- The hash is reported even for skipped books so the cache can be keyed
    -- before any scan work happens.
    local result = {warnings = {}, stats = {}, theme_hash = Theme.hash(theme)}
    local ok, err = pcall(function()
        local entries = reader:list()
        if not entries or #entries == 0 then
            error("empty archive")
        end

        if Epub.is_encrypted(reader) then
            result.skipped = "encrypted"
            return
        end

        local opf_path = Epub.find_opf(reader)
        if not opf_path then error("no package document") end
        local opf_xml = read_limited(reader, opf_path, 4 * 1024 * 1024, result.warnings)
        if not opf_xml then error("unreadable package document") end
        local opf = Epub.parse_opf(opf_xml, opf_path)

        local documents = Epub.spine_documents(reader, opf)
        if #documents == 0 then error("no content documents") end
        if #documents > settings.max_documents then
            result.warnings[#result.warnings + 1] = "document count capped"
            while #documents > settings.max_documents do table.remove(documents) end
        end

        local rules = {}
        local css_documents = Epub.css_documents(reader, opf)
        local css_bytes = 0
        for index, path in ipairs(css_documents) do
            if index > settings.max_css_documents or css_bytes >= settings.max_css_bytes then
                result.warnings[#result.warnings + 1] = "stylesheet scan capped"
                break
            end
            local css = read_limited(reader, path, settings.max_css_bytes - css_bytes, result.warnings)
            if css then
                css_bytes = css_bytes + #css
                local parsed = Css.parse(css)
                for _, rule in ipairs(parsed) do rules[#rules + 1] = rule end
            end
        end

        local toc = Epub.toc(reader, opf)
        if #toc == 0 then
            result.warnings[#result.warnings + 1] = "no navigation document"
        end

        -- Front matter (cover, title page, copyright, ToC, dedication...) is
        -- classified as furniture, not body text: no pseudo-heading or quote
        -- rules are generated for those documents.
        local front_matter = Epub.front_matter_paths(reader, opf)
        settings.front_matter = front_matter

        local candidates, selector_totals = {}, {}
        for _, path in ipairs(documents) do
            if front_matter[path] then
                result.stats.front_matter_documents =
                    (result.stats.front_matter_documents or 0) + 1
            end
            local html = read_limited(reader, path, settings.max_html_bytes, result.warnings)
            if html then
                local parsed, doc = pcall(Html.parse, html)
                if parsed then
                    local classified, found, totals = pcall(Classify.classify_file,
                        path, doc, rules, toc, settings)
                    if classified then
                        for _, candidate in ipairs(found or {}) do
                            candidates[#candidates + 1] = candidate
                        end
                        for selector, count in pairs(totals or {}) do
                            selector_totals[selector] = (selector_totals[selector] or 0) + count
                        end
                    else
                        result.warnings[#result.warnings + 1] = path .. ": " .. tostring(found)
                    end
                else
                    result.warnings[#result.warnings + 1] = path .. ": " .. tostring(doc)
                end
            end
        end

        local merged = limit_candidates(Classify.merge(candidates, selector_totals),
            settings.max_candidates)
        result.stats.documents = #documents
        result.stats.stylesheets = #css_documents
        result.stats.toc_entries = #toc
        local headings, quotes = 0, 0
        for _, candidate in ipairs(merged) do
            if candidate.role == "quote" then
                quotes = quotes + 1
            else
                headings = headings + 1
                local key = "level" .. tostring(candidate.level)
                result.stats[key] = (result.stats[key] or 0) + 1
            end
        end
        result.stats.pseudo_headings = headings
        result.stats.quote_rules = quotes

        if #merged == 0 then
            result.skipped = "no-pseudo-headings"
        end

        result.candidates = merged
        -- The base stylesheet (body, real headings, quote type) applies even
        -- when no pseudo-heading was found, so CSS is never nil for a book we
        -- could read.
        result.css = Generate.generate(merged, settings)
        if not result.css then result.skipped = "generation-failed" end
    end)
    if not ok then
        result.error = tostring(err)
    end
    return result
end

return Scan
