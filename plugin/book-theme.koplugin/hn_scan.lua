-- Orchestration: read the EPUB, parse its navigation and CSS, classify each
-- spine document and generate one stylesheet. All failures are contained in
-- the result so a malformed book can never stop the reader from opening.

local Epub = require("hn_epub")
local Html = require("hn_html")
local Css = require("hn_css")
local Classify = require("hn_classify")
local Generate = require("hn_generate")
local Theme = require("hn_theme")

local Scan = {}

local DEFAULTS = {
    max_documents = 400,
    max_html_bytes = 2 * 1024 * 1024,
    max_css_documents = 24,
    max_css_bytes = 2 * 1024 * 1024,
    min_layout_score = 38,
}

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

        local candidates = {}
        for _, path in ipairs(documents) do
            local html = read_limited(reader, path, settings.max_html_bytes, result.warnings)
            if html then
                local parsed, doc = pcall(Html.parse, html)
                if parsed then
                    local classified, found = pcall(Classify.classify_file,
                        path, doc, rules, toc, settings)
                    if classified then
                        for _, candidate in ipairs(found) do
                            candidates[#candidates + 1] = candidate
                        end
                    else
                        result.warnings[#result.warnings + 1] = path .. ": " .. tostring(found)
                    end
                else
                    result.warnings[#result.warnings + 1] = path .. ": " .. tostring(doc)
                end
            end
        end

        local merged = Classify.merge(candidates)
        result.stats.documents = #documents
        result.stats.stylesheets = #css_documents
        result.stats.toc_entries = #toc
        result.stats.pseudo_headings = #merged
        for _, candidate in ipairs(merged) do
            local key = "level" .. tostring(candidate.level)
            result.stats[key] = (result.stats[key] or 0) + 1
        end

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
