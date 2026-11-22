-- Heading detection. Navigation targets and a small allow-list of EPUB
-- semantic kinds are evidence; layout heuristics only add a candidate when
-- several independent signals agree. Epigraphs and verse are detected
-- separately with role "quote". The output is a small set of selectors, never a
-- body-text guess.

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

-- Furniture containers. Embedded title pages inside a chapter document are
-- common, so a heading inside a title page, cover, dedication or epigraph is
-- furniture even when the document itself was not recognised as front matter.
-- A generic `frontmatter` container is deliberately not listed: some
-- publishers use it for genuine front-matter headings ("Note on the Text").
local FURNITURE_KINDS = {
    titlepage = true, ["title-page"] = true, halftitlepage = true,
    ["half-title-page"] = true, cover = true, dedication = true,
    copyright = true, ["copyright-page"] = true, colophon = true,
    imprint = true, epigraph = true,
}


local HEADING_TAGS = {
    h1 = true, h2 = true, h3 = true, h4 = true, h5 = true, h6 = true,
}

local FRONT_MATTER = {
    cover = true, ["title page"] = true, halftitle = true, ["half title"] = true,
    copyright = true, contents = true, ["table of contents"] = true, toc = true,
    dedication = true, imprint = true, colophon = true, epigraph = true,
    ["also by"] = true,
}

-- EPUB semantics answer "what is this markup for", not "is this a heading".
-- In a reference-heavy library most `epub:type` blocks are notes, so only an
-- explicit allow-list counts. A deny token wins even if another token matches.
local SEMANTIC_KINDS = {
    title = true, subtitle = true, chapter = true, part = true, section = true,
    division = true, volume = true, book = true, preface = true, foreword = true,
    introduction = true, prologue = true, epilogue = true, afterword = true,
    acknowledgements = true, acknowledgments = true, appendix = true,
    conclusion = true, interlude = true, coda = true,
}

local DENY_KINDS = {
    epigraph = true, dedication = true, biblioentry = true, bibliography = true,
    index = true, ["index-entry"] = true, endnote = true, footnote = true,
    noteref = true, backlink = true, pagebreak = true, caption = true,
    cover = true, titlepage = true, ["title-page"] = true,
    ["copyright-page"] = true, colophon = true, imprint = true, glossary = true,
    errata = true, toc = true, nav = true, landmark = true, rearnote = true,
    note = true, annotation = true, poem = true, verse = true,
}

local PART_KINDS = {part = true, book = true, volume = true, division = true}
local CHAPTER_KINDS = {
    chapter = true, preface = true, foreword = true, introduction = true,
    prologue = true, epilogue = true, afterword = true, acknowledgements = true,
    acknowledgments = true, appendix = true, conclusion = true,
    interlude = true, coda = true, title = true,
}
local SECTION_KINDS = {section = true, subtitle = true}

local QUOTE_KINDS = {epigraph = true, verse = true, poem = true}
local QUOTE_TOKENS = {"epigraph", "quote", "verse", "poem", "stanza", "poetry"}
local QUOTE_BLOCKED_TOKENS = {
    "note", "footnote", "endnote", "biblio", "index", "caption", "byline",
    "copyright", "dedication", "toc", "nav",
}
local QUOTE_MAX_CHARS = 300

-- Documents whose whole purpose is notes or an index never carry quotes.
local NOTES_STEMS = {
    note = true, notes = true, endnote = true, endnotes = true,
    footnote = true, footnotes = true, bibliography = true, biblio = true,
    index = true, glossary = true,
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

-- A heading that opens with a bare number and runs straight into the title
-- ("<h1><span class=\"chapter-number\">19</span>Philosophy</h1>") relies on the
-- publisher's CSS for the break or gap. With publisher CSS disabled the number
-- is welded to the title, and the heading descendant reset renders it at full
-- heading size. Return the marker's class token so the generator can give that
-- one class its own line; nil for every other shape. The class exclusions are
-- deliberate: footnote markers, page numbers, list bullets and ToC numbers
-- share the same markup but must stay inline (corpus audit 2026-11-21).
local MARKER_CLASS_BLOCKED = {
    "page", "note", "ref", "bullet", "marker", "toc", "index",
}

local function marker_class(child)
    for _, class_name in ipairs(child.classes) do
        if valid_ident(class_name) then
            local lowered = class_name:lower()
            local blocked = false
            for _, token in ipairs(MARKER_CLASS_BLOCKED) do
                if lowered:find(token, 1, true) then
                    blocked = true
                    break
                end
            end
            if not blocked then return class_name end
        end
    end
    return nil
end

function Classify.heading_marker(element)
    if not element or not HEADING_TAGS[element.tag] then return nil end

    -- The first element child that actually has text. Empty <a id> anchors
    -- are extremely common at the start of a heading and must not hide the
    -- marker behind them.
    local marker
    for _, child in ipairs(element.children) do
        if Util.trim(child.text or "") ~= "" then
            marker = child
            break
        end
    end
    if not marker then return nil end
    if Html.is_block(marker.tag) then return nil end

    -- A number that follows title text belongs to the sentence.
    if (marker.lead_text or "") ~= "" then return nil end

    local text = Util.trim(marker.text)
    if not text:match("^%d%d?%d?[%.:%)]?$") then return nil end

    -- Only the glued shape needs help: existing whitespace already separates.
    local own = element.own_text or ""
    if own == "" or own:match("^%s") then return nil end

    return marker_class(marker)
end

-- Layout candidates are short. Navigation targets are allowed to be a little
-- longer (chapter subtitles), but not a whole paragraph.
local function text_ok(text)
    if not text then return false end
    text = Util.trim(text)
    if #text == 0 or #text > 140 then return false end
    if text:find("http://", 1, true) or text:find("https://", 1, true) then return false end
    if #text > 30 and text:match("%.%s*$") then return false end
    local visible = text:gsub("[%s%p%d]", "")
    return visible ~= ""
end

local function toc_text_ok(text)
    if not text then return false end
    text = Util.trim(text)
    if #text == 0 or #text > 140 then return false end
    if text:find("http://", 1, true) or text:find("https://", 1, true) then return false end
    -- A long sentence ending in a full stop is prose reached through a ToC
    -- entry (an e-mail sign-up blurb), not a chapter title. Short titles with
    -- a trailing period stay allowed for numbered chapters.
    if #text > 60 and text:match("%.%s*$") then return false end
    local visible = text:gsub("[%s%p%d]", "")
    return visible ~= ""
end

local function quote_text_ok(text)
    if not text then return false end
    text = Util.trim(text)
    if #text == 0 or #text > QUOTE_MAX_CHARS then return false end
    if text:find("http://", 1, true) or text:find("https://", 1, true) then return false end
    local visible = text:gsub("[%s%p%d]", "")
    return visible ~= ""
end

-- One normalised token per `epub:type` / `role` value: lowercase, no namespace
-- prefix, no `doc-` prefix. `z3998:chapter` and `doc-chapter` both become
-- `chapter`.
local function kind_tokens(element)
    local tokens, seen = {}, {}
    for _, field in ipairs({element.epub_type, element.role}) do
        for token in (field or ""):lower():gmatch("%S+") do
            local name = token:match("([^:]+)$") or token
            if name:sub(1, 4) == "doc-" then name = name:sub(5) end
            if name ~= "" and not seen[name] then
                seen[name] = true
                tokens[#tokens + 1] = name
            end
        end
    end
    return tokens
end

local function denied_kind(element)
    for _, name in ipairs(kind_tokens(element)) do
        if DENY_KINDS[name] then return name end
    end
    return nil
end

local function semantic_kind(element)
    local tokens = kind_tokens(element)
    if #tokens == 0 then return nil end
    for _, name in ipairs(tokens) do
        if DENY_KINDS[name] then return nil end
    end
    for _, name in ipairs(tokens) do
        if SEMANTIC_KINDS[name] then return name end
    end
    return nil
end

-- Walk the element's ancestors for a furniture `epub:type`/`role`. The
-- element's own kind is handled by the deny list: an element that *is* an
-- epigraph must still become a quote.
local function furniture_kind(element)
    local current = element.parent
    while current do
        for _, name in ipairs(kind_tokens(current)) do
            if FURNITURE_KINDS[name] then return name end
        end
        current = current.parent
    end
    return nil
end

-- A real heading anywhere inside the wrapper already gets the global heading
-- CSS. Adding a pseudo rule for the wrapper would restyle the heading and its
-- furniture (chapter number block) a second time.
local function contains_heading(element)
    for _, child in ipairs(element.children) do
        if Html.is_heading(child.tag) then return true end
        if contains_heading(child) then return true end
    end
    return false
end

local function forbidden(doc, element)
    if element.in_head then return true end
    if FORBIDDEN_ANCESTORS[element.tag] then return true end
    if Html.ancestor_tag(element, FORBIDDEN_ANCESTORS) then return true end
    if furniture_kind(element) then return true end
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

local function starts_document(doc, element)
    local first = Html.first_block_in_body(doc)
    if not first then return false end
    return first.index == element.index
        or Html.is_ancestor(first, element)
        or Html.is_ancestor(element, first)
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

local function semantic_level(element, kind)
    if PART_KINDS[kind] then return 1 end
    if SECTION_KINDS[kind] then return 3 end
    if CHAPTER_KINDS[kind] then return 2 end
    if element.aria_level then
        return math.max(1, math.min(4, element.aria_level))
    end
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

-- Follow the first visible block child until a leaf. A real heading ends the
-- walk: the global heading CSS already covers it, so no pseudo candidate is
-- added. Depth is capped so a pathological tree cannot run away.
local function descend_leaf(element, max_depth)
    local current = element
    local depth = 0
    while depth < max_depth do
        if Html.is_heading(current.tag) then return current, true end
        if not Html.has_block_children(current) then return current, false end
        local child = Html.first_block_child(current)
        if not child then return current, false end
        current = child
        depth = depth + 1
    end
    return current, Html.is_heading(current.tag)
end

-- A ToC target is often a wrapper. Descend while the first visible block child
-- is itself a long wrapper; stop at the first short block, which is the title.
local function descend_wrapper(element, max_depth)
    local current = element
    for _ = 1, max_depth do
        if Html.is_heading(current.tag) then return current, true end
        if not Html.has_block_children(current) then break end
        local child = Html.first_block_child(current)
        if not child then break end
        current = child
        if Html.is_heading(current.tag) then return current, true end
        if not Html.has_block_children(current) then break end
        if #Util.trim(current.text) <= 140 then break end
    end
    return current, Html.is_heading(current.tag)
end

local function long_block_children(element)
    local count = 0
    for _, child in ipairs(element.children) do
        if Html.is_block(child.tag) and #Util.trim(child.text) > 140 then
            count = count + 1
        end
    end
    return count
end

local function resolve_toc_target(doc, entry)
    local element
    if entry.fragment and entry.fragment ~= "" then
        element = doc.by_id[entry.fragment]
    end
    -- A file-only entry means "the start of this document".
    if not element then element = Html.first_block_in_body(doc) end
    if not element then return nil end
    element = Html.climb_to_block(element)
    if not element then return nil end

    -- body/html may be the starting point (an id on <body> is common), but it
    -- is only ever a wrapper: the descent must end at a text block, never at
    -- the document itself.
    local target, real_heading = descend_wrapper(element, 3)
    if not target or real_heading or Html.is_heading(target.tag) then return nil end
    if target.tag == "body" or target.tag == "html" then return nil end
    if not toc_text_ok(target.text) then return nil end
    if long_block_children(target) >= 2 then return nil end
    if forbidden(doc, target) then return nil end
    if denied_kind(target) or denied_kind(element) then return nil end
    return target
end

-- `selector_override` is used by the ToC tier: the entry already names one
-- exact element, so an id selector can replace a class selector that is shared
-- with body text.
local function add_candidate(list, by_selector, element, level, score, reason, page_break,
    occurrences, selector_override)
    local selector = selector_override or selector_for(element)
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
        doc_text = Util.trim(element.text):gsub("%s+", " "),
        reasons = {reason},
        page_break = page_break == true,
        level_scores = {[level] = score},
        occurrences = occurrences,
    }
    by_selector[selector] = candidate
    list[#list + 1] = candidate
end

local function add_quote(list, by_selector, element, selector, signal)
    local existing = by_selector[selector]
    if existing then
        if existing.role == "quote" then
            existing.count = existing.count + 1
        end
        return
    end
    local candidate = {
        selector = selector,
        level = 3,
        score = 60,
        count = 1,
        text = element.text:sub(1, 80),
        doc_text = Util.trim(element.text):gsub("%s+", " "),
        reasons = {"quote"},
        page_break = false,
        role = "quote",
        level_scores = {[3] = 60},
        quote_signal = signal,
    }
    by_selector[selector] = candidate
    list[#list + 1] = candidate
end

local function normalise_path_key(path)
    return (path or ""):lower():gsub("\\", "/")
end

-- `45_notes1.xhtml` and `notes.xhtml` are both a notes document. Only quotes are
-- suppressed there; a Notes section heading is still a heading.
local function notes_document(path)
    local name = Util.basename(normalise_path_key(path))
    name = name:gsub("%.[%a0-9]+$", "")
    name = name:gsub("[%d_%-%.]+$", "")
    name = name:gsub("^[%d_%-%.]+", "")
    return NOTES_STEMS[name] == true
end

local function quote_identity(element)
    for _, name in ipairs(kind_tokens(element)) do
        if QUOTE_KINDS[name] then return name end
    end
    local identity = ((element.attrs.class or "") .. " " .. (element.id or "")):lower()
    return any_token_in(identity, QUOTE_TOKENS)
end

local function quote_forbidden(element)
    if element.in_head then return true end
    if FORBIDDEN_ANCESTORS[element.tag] then return true end
    if Html.ancestor_tag(element, FORBIDDEN_ANCESTORS) then return true end
    if Html.ancestor_tag(element, HEADING_TAGS) then return true end
    if furniture_kind(element) then return true end
    if Html.ancestor_class_token(element, "toc") or Html.ancestor_class_token(element, "nav")
        or Html.ancestor_class_token(element, "footnote") then
        return true
    end
    for _, name in ipairs(kind_tokens(element)) do
        if DENY_KINDS[name] and not QUOTE_KINDS[name] then return true end
    end
    local identity = ((element.attrs.class or "") .. " " .. (element.id or "")):lower()
    if any_token_in(identity, QUOTE_BLOCKED_TOKENS) then return true end
    return false
end

local function visible_block_children(element)
    local count = 0
    for _, child in ipairs(element.children) do
        if Html.is_block(child.tag) and Util.trim(child.text) ~= "" then
            count = count + 1
        end
    end
    return count
end

-- A blockquote is always quote-shaped; a div is quote-shaped only when it holds
-- a few short blocks (an epigraph), never a whole chapter.
local function quote_shape_ok(element)
    if not quote_text_ok(element.text) then return false end
    if element.tag == "blockquote" then return true end
    if Html.has_block_children(element) then
        local count = visible_block_children(element)
        return count >= 1 and count <= 6
    end
    return element.tag == "p" or element.tag == "div"
end

function Classify.classify_file(path, doc, rules, toc_entries, options)
    options = options or {}
    local list, by_selector = {}, {}

    -- Front matter (cover, title page, copyright, ToC, dedication, colophon...)
    -- is furniture. Its real headings still get the global heading CSS, but no
    -- pseudo-heading or quote rule is generated for it.
    local front_matter = options.front_matter or {}
    if front_matter[path] then return list, {} end

    local class_counts, selector_totals = {}, {}
    for _, element in ipairs(doc.elements) do
        for _, class_name in ipairs(element.classes) do
            class_counts[class_name] = (class_counts[class_name] or 0) + 1
        end
        -- Occurrence count per selector: every block with visible text that
        -- would be restyled if this selector became a rule. Empty spacing
        -- blocks are invisible and therefore not counted.
        if not element.in_head and Html.is_block(element.tag)
            and not Html.is_heading(element.tag)
            and element.tag ~= "body" and element.tag ~= "html"
            and Util.trim(element.text) ~= "" then
            local selector = selector_for(element)
            if selector then
                selector_totals[selector] = (selector_totals[selector] or 0) + 1
            end
        end
    end

    -- The ToC is the book's own ground truth: each entry's fragment names one
    -- element. Count the entries per class selector first, so a selector that is
    -- shared with ordinary body text can be judged once for the whole document
    -- instead of accidentally restyling hundreds of paragraphs.
    local toc_targets, toc_totals = {}, {}
    for _, entry in ipairs(toc_entries or {}) do
        if Util.normalize_path(entry.path) == Util.normalize_path(path) then
            local level = toc_level(entry)
            if level then
                local element = resolve_toc_target(doc, entry)
                if element then
                    toc_targets[#toc_targets + 1] = {element = element, level = level}
                    local selector = selector_for(element)
                    if selector then
                        toc_totals[selector] = (toc_totals[selector] or 0) + 1
                    end
                end
            end
        end
    end

    local toc_elements = {}
    for _, target in ipairs(toc_targets) do
        local element, level = target.element, target.level
        toc_elements[element.index] = true
        local selector = selector_for(element)
        local occurrences = selector_totals[selector] or 1
        local exact
        if selector and occurrences >= 3
            and (toc_totals[selector] or 1) * 2 < occurrences
            and valid_ident(element.id) then
            -- The class selector is shared, but the ToC fragment gives this one
            -- element its own id. An id rule restyles exactly that element and
            -- cannot leak into body text, so it is always preferable to dropping
            -- a real heading or to restyling the shared class.
            exact = element.tag .. "#" .. element.id
        end
        if exact and exact ~= selector then
            add_candidate(list, by_selector, element, level, 100, "toc", false, 1, exact)
        else
            add_candidate(list, by_selector, element, level, 100, "toc", false, occurrences)
        end
    end

    for _, element in ipairs(doc.elements) do
        if not Html.is_heading(element.tag) and not element.in_head
            and (element.epub_type or element.role) then
            local kind = semantic_kind(element)
            if kind then
                local block = Html.climb_to_block(element) or element
                local target, real_heading = descend_leaf(block, 3)
                if target and not real_heading and not Html.is_heading(target.tag)
                    and not contains_heading(target)
                    and text_ok(target.text) and not forbidden(doc, target)
                    and not denied_kind(target) then
                    add_candidate(list, by_selector, target, semantic_level(element, kind),
                        80, "epub-semantics", false,
                        selector_totals[selector_for(target)])
                end
            end
        end
    end

    for _, element in ipairs(doc.elements) do
        if not element.in_head and Html.is_block(element.tag)
            and not Html.is_heading(element.tag)
            and element.tag ~= "body" and element.tag ~= "html"
            and not Html.has_block_children(element)
            and not denied_kind(element)
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

                -- A page break alone is not a heading shape: a first page in a
                -- document has one too. It may add score, but some independent
                -- shape signal must also be present.
                local shape = name_hint or ratio >= 1.12 or (bold and centered)
                if signals >= 2 and score >= (options.min_layout_score or 38) and shape then
                    local level = layout_level(element, ratio, upper, name_hint)
                    add_candidate(list, by_selector, element, level, score, "layout",
                        page_break, selector_totals[selector])
                end
            end
        end
    end

    -- Quotes and epigraphs. Separate list, role "quote", never a heading hint.
    if not notes_document(path) then
        for _, element in ipairs(doc.elements) do
            local signal = quote_identity(element)
            local blockquote = element.tag == "blockquote"
            if (signal or blockquote) and Html.is_block(element.tag)
                and not Html.is_heading(element.tag)
                and not element.in_head
                and not toc_elements[element.index]
                and not starts_document(doc, element)
                and quote_shape_ok(element)
                and not quote_forbidden(element) then
                local selector = selector_for(element)
                if selector and not by_selector[selector] then
                    add_quote(list, by_selector, element, selector, signal or "blockquote")
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
    return result, selector_totals
end

-- Merge per-document candidates into one rule list.
--
-- `selector_totals` is the book-wide count of visible blocks per selector; it
-- bounds the blast radius of a rule. A candidate whose selector matches many
-- more blocks than were judged heading-like is rejected: one short trigger must
-- not restyle a whole section (`div#thework`, `li.Biblio`).
--
-- A layout candidate whose text repeats verbatim across three or more documents
-- under the same selector is a running head. ToC and semantic candidates are
-- kept: the book's own navigation outranks repetition.
function Classify.merge(candidates, selector_totals)
    selector_totals = selector_totals or {}
    candidates = candidates or {}

    local heading_selectors = {}
    for _, candidate in ipairs(candidates) do
        if candidate.role ~= "quote" then heading_selectors[candidate.selector] = true end
    end

    local totals = {}
    for _, candidate in ipairs(candidates) do
        local selector = candidate.selector
        if selector_totals[selector] then
            totals[selector] = selector_totals[selector]
        else
            totals[selector] = (totals[selector] or 0) + (candidate.occurrences or candidate.count)
        end
    end

    local by_selector = {}
    local order = {}
    for _, candidate in ipairs(candidates) do
        -- A selector that is both a heading and a quote somewhere is a heading.
        if not (candidate.role == "quote" and heading_selectors[candidate.selector]) then
            local existing = by_selector[candidate.selector]
            if existing then
                existing.count = existing.count + candidate.count
                existing.score = math.max(existing.score, candidate.score)
                existing.level_scores[candidate.level] =
                    (existing.level_scores[candidate.level] or 0) + candidate.score
                if candidate.page_break then existing.page_break = true end
                for _, reason in ipairs(candidate.reasons or {}) do
                    if not Util.table_contains(existing.reasons, reason) then
                        existing.reasons[#existing.reasons + 1] = reason
                    end
                end
                if candidate.doc_text then
                    existing.texts[candidate.doc_text] = (existing.texts[candidate.doc_text] or 0) + 1
                end
            else
                local texts = {}
                if candidate.doc_text then texts[candidate.doc_text] = 1 end
                local record = {
                    selector = candidate.selector,
                    level = candidate.level,
                    score = candidate.score,
                    count = candidate.count,
                    text = candidate.text,
                    reasons = Util.shallow_copy(candidate.reasons or {}),
                    page_break = candidate.page_break == true,
                    role = candidate.role,
                    texts = texts,
                    level_scores = Util.shallow_copy(
                        candidate.level_scores or {[candidate.level] = candidate.score}),
                }
                by_selector[candidate.selector] = record
                order[#order + 1] = candidate.selector
            end
        end
    end

    local merged = {}
    for _, selector in ipairs(order) do
        local candidate = by_selector[selector]
        local occurrences = totals[selector] or candidate.count
        local shared = not (occurrences >= 3 and candidate.count * 2 < occurrences)

        local repeated = 0
        for _, count in pairs(candidate.texts) do
            if count > repeated then repeated = count end
        end
        local layout_only = Util.table_contains(candidate.reasons, "layout")
            and not Util.table_contains(candidate.reasons, "toc")
            and not Util.table_contains(candidate.reasons, "epub-semantics")
        local running_head = layout_only and repeated >= 3

        if shared and not running_head then
            local best_level, best_score = 2, -1
            for level, score in pairs(candidate.level_scores) do
                if score > best_score then
                    best_level, best_score = level, score
                end
            end
            candidate.level = best_level
            candidate.level_scores = nil
            candidate.texts = nil
            candidate.occurrences = occurrences
            merged[#merged + 1] = candidate
        end
    end

    table.sort(merged, function(left, right)
        if left.level ~= right.level then return left.level < right.level end
        return left.selector < right.selector
    end)
    return merged
end

return Classify
