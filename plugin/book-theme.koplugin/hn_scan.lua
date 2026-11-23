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

-- The next block element after `index`. Inline anchors are common inside and
-- between headings, so a plain `index + 1` would land on the wrong node.
local function next_block_element(elements, index)
    for later = index + 1, #elements do
        local candidate = elements[later]
        if Html.is_block(candidate.tag)
            and candidate.tag ~= "body" and candidate.tag ~= "html" then
            return candidate, later
        end
    end
    return nil
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
        local markers = {}
        local number_selectors, title_selectors = {}, {}
        local title_followers = {}
        for _, path in ipairs(documents) do
            if front_matter[path] then
                result.stats.front_matter_documents =
                    (result.stats.front_matter_documents or 0) + 1
            end
            local html = read_limited(reader, path, settings.max_html_bytes, result.warnings)
            if html then
                local parsed, doc = pcall(Html.parse, html)
                if parsed then
                    -- A heading that opens with a bare, glued chapter number
                    -- needs a gap even when the publisher CSS is off. A number
                    -- that is its own heading before the title needs the two
                    -- blocks tightened into one title block instead.
                    local numbers, number_titles = {}, {}
                    local first_heading_index
                    local pair_title_indexes = {}
                    for index, element in ipairs(doc.elements) do
                        local token = Classify.heading_marker(element)
                        if token then
                            markers[element.tag .. " ." .. token] = true
                        end
                        local following, following_index =
                            next_block_element(doc.elements, index)
                        local number_selector, title_selector =
                            Classify.heading_number(element, following)
                        if number_selector then
                            numbers[number_selector] = true
                            number_titles[title_selector] = true
                            pair_title_indexes[#pair_title_indexes + 1] = following_index
                        end
                        if not first_heading_index and Html.is_heading(element.tag) then
                            first_heading_index = index
                        end
                    end
                    -- Publishers often pull the opening block up under the
                    -- chapter title with a negative top margin. Remember that
                    -- block so the generator can cancel the pull-up; without it
                    -- the title's own bottom margin disappears on device.
                    if not front_matter[path] then
                        local function record_follower(index)
                            if not index then return end
                            local follower = next_block_element(doc.elements, index)
                            if follower and not Html.is_heading(follower.tag) then
                                local selector = Classify.selector(follower)
                                if selector then title_followers[selector] = true end
                            end
                        end
                        record_follower(first_heading_index)
                        for _, index in ipairs(pair_title_indexes) do
                            record_follower(index)
                        end
                    end
                    for selector in pairs(numbers) do
                        if not number_titles[selector] then
                            number_selectors[selector] = true
                        end
                    end
                    for selector in pairs(number_titles) do
                        if not numbers[selector] then
                            title_selectors[selector] = true
                        end
                    end
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
        -- Sorted so the generated stylesheet stays byte-identical between scans.
        local marker_list = {}
        for selector in pairs(markers) do
            marker_list[#marker_list + 1] = selector
        end
        table.sort(marker_list)
        result.stats.heading_markers = #marker_list
        settings.markers = marker_list
        local numbers, titles = {}, {}
        for selector in pairs(number_selectors) do numbers[#numbers + 1] = selector end
        for selector in pairs(title_selectors) do titles[#titles + 1] = selector end
        table.sort(numbers)
        table.sort(titles)
        result.stats.heading_numbers = #numbers
        settings.number_headings = numbers
        settings.number_titles = titles
        local followers = {}
        for selector in pairs(title_followers) do
            followers[#followers + 1] = selector
        end
        table.sort(followers)
        settings.title_followers = followers
        -- Everything the generator needs, kept compact in the per-book cache so
        -- a theme change can rebuild the stylesheet without re-reading the
        -- EPUB. Only fields the generator consumes are stored.
        local generation_candidates = {}
        for _, candidate in ipairs(merged) do
            generation_candidates[#generation_candidates + 1] = {
                selector = candidate.selector,
                level = candidate.level,
                role = candidate.role,
                page_break = candidate.page_break,
            }
        end
        result.generation = {
            candidates = generation_candidates,
            markers = marker_list,
            number_headings = numbers,
            number_titles = titles,
            title_followers = followers,
        }
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
