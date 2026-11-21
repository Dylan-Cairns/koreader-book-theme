-- Run the repository's real heading classifier (hn_scan) over an extracted EPUB
-- corpus and write a JSON summary for the corpus audit. This is a reporting
-- tool, not part of the plugin: it never touches the reader and never writes
-- book text. Book text is only measured (length, word count, shape flags).
--
-- The extraction tree is prepared by tools/corpus_audit.py, which writes one
-- <id>\t<root> line per book to the manifest. Each root holds a _entries.tsv
-- with "<archive path>\t<disk path>\t<size>" lines; the directory-backed
-- reader below exposes the same list()/read() interface as Archiver.Reader.
--
-- Usage:
--   luajit tools/corpus_classify.lua [--manifest FILE] [--out FILE]
--                                    [--plugin DIR] [--limit N]

local function fail(message)
    io.stderr:write("corpus_classify: " .. message .. "\n")
    os.exit(2)
end

local options = {
    manifest = "local/corpus-audit/extraction.tsv",
    out = "local/corpus-audit/classifier.json",
    plugin = nil,
    limit = 0,
}

local index = 1
while index <= #arg do
    local name = arg[index]
    local value = arg[index + 1]
    if name == "--manifest" then
        options.manifest = value
        index = index + 2
    elseif name == "--out" then
        options.out = value
        index = index + 2
    elseif name == "--plugin" then
        options.plugin = value
        index = index + 2
    elseif name == "--limit" then
        options.limit = tonumber(value) or 0
        index = index + 2
    else
        fail("unknown argument: " .. tostring(name))
    end
end

-- Locate the plugin directory. The product rename (work unit A) moves the
-- directory, so try both names unless one was given explicitly.
local function find_plugin()
    if options.plugin then return options.plugin end
    local candidates = {"plugin/book-theme.koplugin", "plugin/heading-normalizer.koplugin"}
    for _, path in ipairs(candidates) do
        local handle = io.open(path .. "/hn_scan.lua", "rb")
        if handle then
            handle:close()
            return path
        end
    end
    fail("no plugin directory with hn_scan.lua; pass --plugin DIR")
end

local plugin_dir = find_plugin()
package.path = plugin_dir .. "/?.lua;tests/?.lua;" .. package.path
local Scan = require("hn_scan")
local Epub = require("hn_epub")
local Html = require("hn_html")

local function read_file(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local content = handle:read("*a")
    handle:close()
    return content
end

local function split_lines(text)
    local lines = {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        if line ~= "" then lines[#lines + 1] = line end
    end
    return lines
end

local function split_tabs(line)
    local fields = {}
    for field in (line .. "\t"):gmatch("([^\t]*)\t") do
        fields[#fields + 1] = field
    end
    return fields
end

local function unescape_field(value)
    if not value:find("\\", 1, true) then return value end
    return (value:gsub("\\(.)", function(char)
        if char == "t" then return "\t" end
        if char == "n" then return "\n" end
        if char == "r" then return "\r" end
        return char
    end))
end

local function new_reader(root)
    local index_text = read_file(root .. "/_entries.tsv")
    if not index_text then return nil end
    local entries, disk_paths = {}, {}
    for _, line in ipairs(split_lines(index_text)) do
        local archive, disk, size = line:match("^([^\t]+)\t([^\t]+)\t(%d+)$")
        if archive then
            archive = unescape_field(archive)
            disk = unescape_field(disk)
            entries[#entries + 1] = {path = archive, size = tonumber(size)}
            disk_paths[archive] = disk
        end
    end
    table.sort(entries, function(left, right) return left.path < right.path end)
    return {
        list = function(self) return self.entries end,
        read = function(self, path)
            local disk = disk_paths[path]
            if not disk then return nil end
            return read_file(root .. "/" .. disk)
        end,
        entries = entries,
    }
end

-- JSON output -------------------------------------------------------------

local JSON_ESCAPES = {['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n",
    ["\r"] = "\\r", ["\t"] = "\\t"}

local function json_string(value)
    local text = tostring(value)
    text = text:gsub('[%z\1-\31\\"]', function(char)
        return JSON_ESCAPES[char] or string.format("\\u%04x", char:byte())
    end)
    return '"' .. text .. '"'
end

local function json_number(value)
    if value ~= value or value == math.huge or value == -math.huge then return "0" end
    if value == math.floor(value) then return string.format("%d", value) end
    return string.format("%.3f", value)
end

local function json_value(value)
    local kind = type(value)
    if kind == "string" then return json_string(value) end
    if kind == "number" then return json_number(value) end
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "table" then
        if #value > 0 then
            local parts = {}
            for _, item in ipairs(value) do parts[#parts + 1] = json_value(item) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local keys = {}
        for key in pairs(value) do keys[#keys + 1] = key end
        table.sort(keys)
        local parts = {}
        for _, key in ipairs(keys) do
            parts[#parts + 1] = json_string(key) .. ":" .. json_value(value[key])
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

local function median(values)
    if #values == 0 then return 0 end
    table.sort(values)
    local middle = math.floor((#values + 1) / 2)
    if #values % 2 == 1 then return values[middle] end
    return (values[middle] + values[middle + 1]) / 2
end

-- Reporting context -------------------------------------------------------

local MAX_CONTEXTS = 5

local function selector_of(element)
    if not element or element.tag == "body" or element.tag == "html" then return nil end
    if Html.is_heading(element.tag) then return nil end
    if not Html.is_block(element.tag) then
        element = Html.climb_to_block(element)
        if not element or Html.is_heading(element.tag) then return nil end
    end
    local classes = {}
    for _, class_name in ipairs(element.classes) do
        if class_name:match("^[%a_][%w_-]*$") then classes[#classes + 1] = class_name end
    end
    if #classes > 0 then return element.tag .. "." .. table.concat(classes, ".") end
    if element.id and element.id:match("^[%a_][%w_-]*$") then
        return element.tag .. "#" .. element.id
    end
    return nil
end

local function shape_of(tag, classes)
    local text = tag or ""
    if classes and classes[1] then text = text .. "." .. classes[1] end
    return text
end

local function ancestor_shape(element, levels)
    local parts = {}
    local current = element.parent
    while current and #parts < levels do
        if current.tag == "body" or current.tag == "html" then break end
        parts[#parts + 1] = shape_of(current.tag, current.classes)
        current = current.parent
    end
    local reversed = {}
    for position = #parts, 1, -1 do reversed[#reversed + 1] = parts[position] end
    if #reversed == 0 then return "body" end
    return table.concat(reversed, "<")
end

local function sibling_shape(element, direction)
    if not element.parent then return nil end
    local siblings = {}
    for _, child in ipairs(element.parent.children) do
        if Html.is_block(child.tag) then siblings[#siblings + 1] = child end
    end
    local position
    for sibling_index, sibling in ipairs(siblings) do
        if sibling.index == element.index then position = sibling_index end
    end
    if not position then return nil end
    local other = siblings[position + direction]
    if not other then return nil end
    return shape_of(other.tag, other.classes)
end

local function count_words(text)
    local total = 0
    for _ in text:gmatch("%S+") do total = total + 1 end
    return total
end

local function doc_kind(path)
    local lower = path:lower()
    local markers = {
        {"contents", "toc"}, {"toc", "toc"}, {"titlepage", "front"},
        {"title_page", "front"}, {"copyright", "front"}, {"halftitle", "front"},
        {"cover", "front"}, {"dedication", "front"}, {"colophon", "front"},
        {"notes", "notes"}, {"endnote", "notes"}, {"footnote", "notes"},
        {"bibliography", "bibliography"}, {"workscited", "bibliography"},
        {"index", "index"}, {"poem", "poem"}, {"epigraph", "epigraph"},
        {"acknowledg", "front"},
    }
    for _, marker in ipairs(markers) do
        if lower:find(marker[1], 1, true) then return marker[2] end
    end
    return "body"
end

local function element_shape(element)
    local text = element.text or ""
    local words = count_words(text)
    local letters = text:gsub("[^%a]", "")
    return {
        text_len = #text,
        words = words,
        all_caps = #letters > 2 and letters == letters:upper(),
        ends_period = text:sub(-1) == ".",
        digits = text:find("%d") ~= nil,
    }
end

local function child_tags(element)
    local tags, counts = {}, {}
    for _, child in ipairs(element.children) do
        if not tags[child.tag] then
            tags[child.tag] = true
            counts[#counts + 1] = child.tag
        end
    end
    table.sort(counts)
    return table.concat(counts, ",")
end

local function context_for(element, doc_index, occurrences, kind)
    local shape = element_shape(element)
    local br_count = 0
    local links = 0
    for _, child in ipairs(element.children) do
        if child.tag == "br" then br_count = br_count + 1 end
        if child.tag == "a" then links = links + 1 end
    end
    local in_list = false
    local current = element.parent
    while current do
        if current.tag == "li" or current.tag == "ul" or current.tag == "ol"
            or current.tag == "dl" or current.tag == "dd" then
            in_list = true
            break
        end
        current = current.parent
    end
    return {
        doc_index = doc_index,
        doc_kind = kind,
        text_len = shape.text_len,
        words = shape.words,
        all_caps = shape.all_caps,
        ends_period = shape.ends_period,
        digits = shape.digits,
        br = br_count,
        links = links,
        in_list = in_list,
        ancestors = ancestor_shape(element, 3),
        previous = sibling_shape(element, -1),
        next = sibling_shape(element, 1),
        children = child_tags(element),
        occurrences = occurrences,
    }
end

local function tally(counts, key)
    if not key or key == "" then return end
    counts[key] = (counts[key] or 0) + 1
end

local function top(counts, limit)
    local keys = {}
    for key in pairs(counts) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        if counts[left] ~= counts[right] then return counts[left] > counts[right] end
        return left < right
    end)
    local result = {}
    for position = 1, math.min(limit, #keys) do result[#result + 1] = keys[position] end
    return result
end

local ROLE_TOKENS = {
    footnote = {"footnote", "endnote", "noteref", "fnref", "sidenote"},
    caption = {"caption", "figcaption", "credit"},
    byline = {"byline", "contributor", "translator"},
    epigraph = {"epigraph", "pullquote", "blurb"},
    poetry = {"poem", "poetry", "verse", "stanza"},
    dropcap = {"dropcap", "drop-cap", "lettrine"},
    index = {"index"},
    bibliography = {"bibitem", "bibentry", "workscited", "reference"},
    navigation = {"toc", "nav"},
}

local function contains_any(text, tokens)
    if not text or text == "" then return false end
    local values = {}
    for token in text:lower():gmatch("[%w_-]+") do values[#values + 1] = token end
    for _, token in ipairs(tokens) do
        for _, value in ipairs(values) do
            if value == token or value:sub(1, #token) == token then return true end
        end
    end
    return false
end

-- A structural guess at what the candidate is. It is deliberately coarse:
-- the audit reviews the individual cases before calling them true or false.
local function role_hint(candidate, context)
    local reasons = table.concat(candidate.reasons or {}, ",")
    local selector = (candidate.selector or ""):lower()
    if reasons:find("toc", 1, true) then return "toc-heading" end
    if reasons:find("epub-semantics", 1, true) then return "semantic-heading" end
    if selector:find("bibitem", 1, true) or selector:find("bibentry", 1, true)
        or selector:find("reference", 1, true) or selector:find("workscited", 1, true) then
        return "bibliography-entry"
    end
    for role, tokens in pairs(ROLE_TOKENS) do
        if role ~= "bibliography" and role ~= "navigation" and contains_any(selector, tokens) then
            return role
        end
    end
    if contains_any(selector, ROLE_TOKENS.navigation) then return "navigation" end
    if (context.ancestors or ""):lower():find("blockquote", 1, true) then
        return "quote-context"
    end
    if contains_any(context.next, {"numlist", "list", "bibitem", "verse", "poem", "stanza"}) then
        return "list-title"
    end
    if context.page_break then return "page-break-title" end
    if (context.words or 0) >= 8 and context.ends_period then return "prose-like" end
    if context.all_caps and (context.words or 0) <= 6 then return "display-heading" end
    return "layout-heading"
end

local function summarise_contexts(candidates, documents, reader)
    local by_selector = {}
    for _, candidate in ipairs(candidates) do by_selector[candidate.selector] = candidate end
    for doc_index, path in ipairs(documents) do
        local html = Epub.read(reader, path)
        if html and #html <= 2 * 1024 * 1024 then
            local parsed, doc = pcall(Html.parse, html)
            if parsed and doc then
                local seen = {}
                for _, element in ipairs(doc.elements) do
                    local selector = selector_of(element)
                    if selector and by_selector[selector] then
                        seen[selector] = (seen[selector] or 0) + 1
                        local record = by_selector[selector]
                        record.contexts = record.contexts or {}
                        if #record.contexts < MAX_CONTEXTS then
                            local block = Html.climb_to_block(element) or element
                            record.contexts[#record.contexts + 1] =
                                context_for(block, doc_index, 0, doc_kind(path))
                        end
                    end
                end
                for selector, count in pairs(seen) do
                    local record = by_selector[selector]
                    for _, context in ipairs(record.contexts or {}) do
                        if context.doc_index == doc_index then context.occurrences = count end
                    end
                end
            end
        end
    end
end

local function candidate_record(record)
    local contexts = record.contexts or {}
    local lengths, words = {}, {}
    local counts = {
        all_caps = 0, ends_period = 0, digits = 0, br_heavy = 0, links = 0,
        in_list = 0,
    }
    local ancestors, previous, next, children, kinds = {}, {}, {}, {}, {}
    for _, context in ipairs(contexts) do
        lengths[#lengths + 1] = context.text_len
        words[#words + 1] = context.words
        if context.all_caps then counts.all_caps = counts.all_caps + 1 end
        if context.ends_period then counts.ends_period = counts.ends_period + 1 end
        if context.digits then counts.digits = counts.digits + 1 end
        if context.br >= 3 then counts.br_heavy = counts.br_heavy + 1 end
        if context.links > 0 then counts.links = counts.links + 1 end
        if context.in_list then counts.in_list = counts.in_list + 1 end
        tally(ancestors, context.ancestors)
        tally(previous, context.previous)
        tally(next, context.next)
        tally(children, context.children)
        tally(kinds, context.doc_kind)
    end
    local primary = contexts[1] or {}
    local next_keys = {}
    for key in pairs(next) do next_keys[#next_keys + 1] = key end
    table.sort(next_keys)
    return {
        selector = record.selector,
        level = record.level,
        score = record.score,
        count = record.count,
        reasons = record.reasons,
        page_break = record.page_break == true,
        occurrences = #contexts,
        text_len = #lengths > 0 and median(lengths) or 0,
        words = #words > 0 and median(words) or 0,
        shape = counts,
        ancestors = top(ancestors, 3),
        previous = top(previous, 2),
        next = top(next, 2),
        children = top(children, 4),
        doc_kinds = top(kinds, 3),
        role_hint = role_hint(record, {
            ancestors = primary.ancestors or "",
            next = table.concat(next_keys, " "),
            words = primary.words or 0,
            ends_period = primary.ends_period or false,
            all_caps = primary.all_caps or false,
            page_break = record.page_break == true,
        }),
    }
end

local function book_record(book_id, root)
    local record = {id = book_id, ok = false, skipped = nil, error = nil,
        stats = {}, warnings = {}, candidates = {}, verdicts = {}}
    local reader = new_reader(root)
    if not reader then
        record.error = "no extraction index"
        return record
    end
    local result = Scan.scan(reader)
    record.stats = result.stats or {}
    record.warnings = result.warnings or {}
    record.skipped = result.skipped
    record.error = result.error
    record.ok = result.error == nil and result.skipped == nil
    if not result.candidates or #result.candidates == 0 then return record end

    local opf_path = Epub.find_opf(reader)
    if not opf_path then
        record.error = "no package document"
        return record
    end
    local opf = Epub.parse_opf(Epub.read(reader, opf_path), opf_path)
    local documents = Epub.spine_documents(reader, opf)
    summarise_contexts(result.candidates, documents, reader)

    local roles = {}
    for _, candidate in ipairs(result.candidates) do
        local entry = candidate_record(candidate)
        record.candidates[#record.candidates + 1] = entry
        roles[entry.role_hint] = (roles[entry.role_hint] or 0) + 1
    end
    record.verdicts = roles
    return record
end

local function read_manifest(path)
    local text = read_file(path)
    if not text then fail("cannot read manifest: " .. path) end
    local books = {}
    for _, line in ipairs(split_lines(text)) do
        local fields = split_tabs(line)
        if fields[1] and fields[2] then
            books[#books + 1] = {id = fields[1], root = fields[2]}
        end
    end
    return books
end

local books = read_manifest(options.manifest)
if #books == 0 then
    fail("manifest has no books: " .. options.manifest ..
        " (run tools/corpus_audit.py first)")
end
if options.limit > 0 then
    while #books > options.limit do table.remove(books) end
end

local records = {}
local role_totals = {}
local readable = 0
for position, book in ipairs(books) do
    io.stderr:write(string.format("[%d/%d] %s\n", position, #books, book.id))
    local record = book_record(book.id, book.root)
    if record.error ~= "no extraction index" then
        readable = readable + 1
    end
    records[#records + 1] = record
    for role, count in pairs(record.verdicts or {}) do
        role_totals[role] = (role_totals[role] or 0) + count
    end
end

if readable == 0 then
    fail("no extraction root is readable; re-run tools/corpus_audit.py")
end

local payload = {
    schema = 1,
    plugin = plugin_dir,
    books = records,
    totals = role_totals,
}
local handle = assert(io.open(options.out, "wb"))
handle:write(json_value(payload))
handle:write("\n")
handle:close()
io.stderr:write("wrote " .. options.out .. "\n")
