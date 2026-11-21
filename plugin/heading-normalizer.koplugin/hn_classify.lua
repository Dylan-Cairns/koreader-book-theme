-- Heading detection. TOC targets and EPUB semantics are treated as evidence;
-- layout heuristics only add a candidate when several independent signals
-- agree. The output is a small set of selectors, never a body-text guess.

local Util = require("hn_util")
local Html = require("hn_html")
local Css = require("hn_css")

local Classify = {}

local NAME_TOKENS = {
    "chapter", "chap", "part", "book", "volume", "section", "heading",
    "title", "subtitle", "subhead",
}

local NEGATIVE_TOKENS = {
    "toc", "nav", "footnote", "note", "caption", "byline", "author",
    "copyright", "dedication", "epigraph", "poem", "verse", "dropcap",
    "image", "figure", "table", "header",
}

local FORBIDDEN_ANCESTORS = {
    nav = true, table = true, figure = true, aside = true, form = true, head = true,
}

local FRONT_MATTER = {
    cover = true, ["title page"] = true, copyright = true, contents = true,
    ["table of contents"] = true, toc = true,
}

local function token_in(value, token)
    if not value or value == "" then return false end
    return (" " .. value .. " "):find("[%s_-]" .. token .. "[%s_-]") ~= nil
end

local function any_token_in(value, tokens)
    if not value or value == "" then return false end
    value = value:lower()
    for _, token in ipairs(tokens) do
        if token_in(value, token) then return token end
    end
    return nil
end

local function valid_ident(value)
    return value and value:match("^[%a_][%w_-]*$") ~= nil
end

local function selector_for(element)
    if not element or element.tag == "body" or element.tag == "html" then return nil end
    if Html.is_heading(element.tag) then return nil end
    if not Html.is_block(element.tag) then
        element = Html.climb_to_block(element)
        if not element or Html.is_heading(element.tag) then return nil end
    end
    local classes = {}
    for _, class_name in ipairs(element.classes) do
        if valid_ident(class_name) then classes[#classes + 1] = class_name end
    end
    if #classes > 0 then
        return element.tag .. "." .. table.concat(classes, ".")
    end
    if valid_ident(element.id) then
        return element.tag .. "#" .. element.id
    end
    return nil
end

local function text_ok(text)
    if not text then return false end
    text = Util.trim(text)
    if #text == 0 or #text > 140 then return false end
    if text:find("http://", 1, true) or text:find("https://", 1, true) then return false end
    if #text > 30 and text:match("%.%s*$") then return false end
    local visible = text:gsub("[%s%p%d]", "")
    return visible ~= ""
end

local function forbidden(doc, element)
    if element.in_head then return true end
    if FORBIDDEN_ANCESTORS[element.tag] then return true end
    if Html.ancestor_tag(element, FORBIDDEN_ANCESTORS) then return true end
    if Html.ancestor_class_token(element, "toc") or Html.ancestor_class_token(element, "nav")
        or Html.ancestor_class_token(element, "footnote") then
        return true
    end
    local identity = ((element.attrs.class or "") .. " " .. (element.id or "")):lower()
    if any_token_in(identity, NEGATIVE_TOKENS) then return true end
    return false
end

local function has_bold_descendant(element)
    for _, child in ipairs(element.children) do
        if child.tag == "b" or child.tag == "strong" then return true end
    end
    return false
end

local function is_first_block(doc, element, page_break)
    local first = Html.first_block_in_body(doc)
    if not first then return false end
    if first.index == element.index then return true end
    if Html.is_ancestor(first, element) then
        return #first.text <= 140 or page_break == true
    end
    return false
end

local function toc_level(entry)
    local title = (entry.title or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if FRONT_MATTER[title] then return nil end
    if title:match("^part%f[%W]") or title:match("^book%f[%W]")
        or title:match("^volume%f[%W]") or title:match("^act%f[%W]") then
        return 1
    end
    if (entry.depth or 1) <= 1 then return 2 end
    if entry.depth == 2 then return 3 end
    return 4
end

local function semantic_level(element)
    local kind = ((element.epub_type or "") .. " " .. (element.role or "")):lower()
    if kind:find("part", 1, true) or kind:find("volume", 1, true) or kind:find("book", 1, true) then
        return 1
    end
    if kind:find("chapter", 1, true) or kind:find("preface", 1, true)
        or kind:find("foreword", 1, true) or kind:find("introduction", 1, true)
        or kind:find("prologue", 1, true) or kind:find("epilogue", 1, true)
        or kind:find("afterword", 1, true) or kind:find("acknowledg", 1, true) then
        return 2
    end
    if kind:find("section", 1, true) or kind:find("subchapter", 1, true) then
        return 3
    end
    if element.aria_level then
        return math.max(1, math.min(4, element.aria_level))
    end
    if kind:find("heading", 1, true) then return 2 end
    return 2
end

local function layout_level(element, ratio, upper, name_hint)
    if name_hint == "part" or name_hint == "book" or name_hint == "volume" then return 1 end
    if name_hint == "chapter" or name_hint == "chap" then return 2 end
    if name_hint == "section" or name_hint == "heading" or name_hint == "subhead" then
        return 3
    end
    if name_hint == "title" or name_hint == "subtitle" then
        if ratio >= 1.3 then return 2 end
        return 3
    end
    if ratio >= 1.45 then return 2 end
    if ratio >= 1.22 then return 3 end
    if upper then return 4 end
    return 4
end

local function resolve_toc_target(doc, entry)
    local element
    if entry.fragment and entry.fragment ~= "" then
        element = doc.by_id[entry.fragment]
    end
    if not element then element = Html.first_block_in_body(doc) end
    if not element then return nil end
    element = Html.climb_to_block(element)
    if not element then return nil end
    if element.tag == "body" or element.tag == "html" then
        element = Html.first_block_child(element)
    end
    if not element then return nil end
    if Html.has_block_children(element) then
        local child = Html.first_block_child(element)
        if child and text_ok(child.text) then element = child end
    end
    if not text_ok(element.text) then return nil end
    if forbidden(doc, element) then return nil end
    return element
end

local function add_candidate(list, by_selector, element, level, score, reason, page_break)
    local selector = selector_for(element)
    if not selector then return end
    local existing = by_selector[selector]
    if existing then
        existing.count = existing.count + 1
        existing.score = math.max(existing.score, score)
        existing.level_scores[level] = (existing.level_scores[level] or 0) + score
        if page_break then existing.page_break = true end
        if not Util.table_contains(existing.reasons, reason) then
            existing.reasons[#existing.reasons + 1] = reason
        end
        return
    end
    local candidate = {
        selector = selector,
        level = level,
        score = score,
        count = 1,
        text = element.text:sub(1, 80),
        reasons = {reason},
        page_break = page_break == true,
        level_scores = {[level] = score},
    }
    by_selector[selector] = candidate
    list[#list + 1] = candidate
end

function Classify.classify_file(path, doc, rules, toc_entries, options)
    options = options or {}
    local list, by_selector = {}, {}

    local class_counts = {}
    for _, element in ipairs(doc.elements) do
        for _, class_name in ipairs(element.classes) do
            class_counts[class_name] = (class_counts[class_name] or 0) + 1
        end
    end

    for _, entry in ipairs(toc_entries or {}) do
        if Util.normalize_path(entry.path) == Util.normalize_path(path) then
            local level = toc_level(entry)
            if level then
                local element = resolve_toc_target(doc, entry)
                if element then
                    add_candidate(list, by_selector, element, level, 100, "toc", false)
                end
            end
        end
    end

    for _, element in ipairs(doc.elements) do
        if not Html.is_heading(element.tag) and not element.in_head
            and (element.epub_type or element.role) then
            local target = element
            if Html.has_block_children(element) then
                target = Html.first_block_child(element) or element
            end
            if text_ok(target.text) and not forbidden(doc, target) then
                add_candidate(list, by_selector, target, semantic_level(element), 80, "epub-semantics", false)
            end
        end
    end

    for _, element in ipairs(doc.elements) do
        if not element.in_head and Html.is_block(element.tag)
            and not Html.is_heading(element.tag)
            and element.tag ~= "body" and element.tag ~= "html"
            and not Html.has_block_children(element)
            and text_ok(element.text)
            and not forbidden(doc, element) then
            local selector = selector_for(element)
            if selector and not by_selector[selector] then
                local style = Css.compute(element, rules)
                local ratio = Css.font_size_ratio(style["font-size"]) or 1.0
                local bold = Css.is_bold(style["font-weight"])
                local centered = Css.is_centered(style["text-align"])
                local upper = Css.is_upper(style["text-transform"])
                local page_break = Css.page_break_before(style["page-break-before"])
                    or Css.page_break_before(style["break-before"])
                local margin = Css.margin_top(style["margin-top"])

                if not page_break then
                    local ancestor = element.parent
                    while ancestor and not page_break do
                        local ancestor_style = Css.compute(ancestor, rules)
                        page_break = Css.page_break_before(ancestor_style["page-break-before"])
                            or Css.page_break_before(ancestor_style["break-before"])
                        ancestor = ancestor.parent
                    end
                end

                local identity = ((element.attrs.class or "") .. " " .. (element.id or "")):lower()
                local name_hint = any_token_in(identity, NAME_TOKENS)
                local count = 0
                for _, class_name in ipairs(element.classes) do
                    count = math.max(count, class_counts[class_name] or 0)
                end
                local first = is_first_block(doc, element, page_break)
                local score, signals = 0, 0

                if page_break then score = score + 25; signals = signals + 1 end
                if ratio >= 1.5 then
                    score = score + 25
                    signals = signals + 1
                elseif ratio >= 1.25 then
                    score = score + 18
                    signals = signals + 1
                elseif ratio >= 1.12 then
                    score = score + 8
                    signals = signals + 1
                end
                if bold then score = score + 12; signals = signals + 1 end
                if centered then score = score + 8; signals = signals + 1 end
                if first then score = score + 18; signals = signals + 1 end
                if name_hint then score = score + 15; signals = signals + 1 end
                if count == 1 then
                    score = score + 12
                    signals = signals + 1
                elseif count >= 4 then
                    score = score - 20
                end
                if upper then score = score + 4; signals = signals + 1 end
                if margin >= 1.5 then score = score + 5; signals = signals + 1 end
                if has_bold_descendant(element) then score = score + 6; signals = signals + 1 end
                if not bold and ratio < 1.05 and not page_break then score = score - 10 end

                if signals >= 2 and score >= (options.min_layout_score or 38)
                    and (name_hint or ratio >= 1.12 or page_break) then
                    local level = layout_level(element, ratio, upper, name_hint)
                    add_candidate(list, by_selector, element, level, score, "layout", page_break)
                end
            end
        end
    end

    local result = {}
    for _, candidate in ipairs(list) do
        local best_level, best_score = 2, -1
        for level, score in pairs(candidate.level_scores) do
            if score > best_score then
                best_level, best_score = level, score
            end
        end
        candidate.level = best_level
        result[#result + 1] = candidate
    end
    return result
end

function Classify.merge(candidates)
    local by_selector = {}
    for _, candidate in ipairs(candidates) do
        local existing = by_selector[candidate.selector]
        if existing then
            existing.count = existing.count + candidate.count
            existing.score = math.max(existing.score, candidate.score)
            existing.level_scores[candidate.level] =
                (existing.level_scores[candidate.level] or 0) + candidate.score
            if candidate.page_break then existing.page_break = true end
            for _, reason in ipairs(candidate.reasons) do
                if not Util.table_contains(existing.reasons, reason) then
                    existing.reasons[#existing.reasons + 1] = reason
                end
            end
        else
            by_selector[candidate.selector] = {
                selector = candidate.selector,
                level = candidate.level,
                score = candidate.score,
                count = candidate.count,
                text = candidate.text,
                reasons = Util.shallow_copy(candidate.reasons),
                page_break = candidate.page_break,
                level_scores = Util.shallow_copy(
                    candidate.level_scores or {[candidate.level] = candidate.score}),
            }
        end
    end

    local merged = {}
    for _, candidate in pairs(by_selector) do
        local best_level, best_score = 2, -1
        for level, score in pairs(candidate.level_scores) do
            if score > best_score then
                best_level, best_score = level, score
            end
        end
        candidate.level = best_level
        candidate.level_scores = nil
        merged[#merged + 1] = candidate
    end
    table.sort(merged, function(left, right)
        if left.level ~= right.level then return left.level < right.level end
        return left.selector < right.selector
    end)
    return merged
end

return Classify
