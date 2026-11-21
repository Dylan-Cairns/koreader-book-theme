-- EPUB container, package and navigation parsing. The caller supplies a
-- reader object with list() and read(path); tests use an in-memory reader and
-- the plugin uses KOReader's libarchive wrapper.

local Util = require("hn_util")

local Epub = {}

local XHTML_EXTENSIONS = {xhtml = true, html = true, htm = true}
local CSS_EXTENSIONS = {css = true}

-- Documents that are furniture rather than body text. Pseudo-heading detection
-- is skipped for them entirely; the real `h1`-`h6` rules still apply.
local FRONT_MATTER_TYPES = {
    cover = true, ["title-page"] = true, titlepage = true,
    ["copyright-page"] = true, toc = true, contents = true,
    dedication = true, epigraph = true, imprint = true, colophon = true,
}

-- Filename fallback for packages that declare neither a guide nor landmarks.
-- Publisher prefixes are common (`s003-BookTitlePage-01.xhtml`), so the
-- multi-word stems are matched anywhere in the name. Short generic words are
-- only matched as whole separators-delimited tokens, and `title` only as a
-- leading word, so `chapter-title.xhtml` is not furniture.
local FRONT_MATTER_SUBSTRINGS = {
    "titlepage", "title_page", "halftitle", "half_title", "copyright",
    "colophon", "imprint", "tableofcontents", "frontmatter",
}
local FRONT_MATTER_WORDS = {"cover", "toc", "contents", "nav"}

local function is_separator(character)
    return character == "-" or character == "_" or character == "."
end

local function basename_is_front_matter(name)
    local stem = name:lower():gsub("%.[%a0-9]+$", "")
    for _, token in ipairs(FRONT_MATTER_SUBSTRINGS) do
        if stem:find(token, 1, true) then return token end
    end
    if stem == "title" or stem:match("^title[-_.]") then return "title" end
    for _, token in ipairs(FRONT_MATTER_WORDS) do
        local start = 1
        while true do
            local found = stem:find(token, start, true)
            if not found then break end
            local before_ok = found == 1 or is_separator(stem:sub(found - 1, found - 1))
            local after = found + #token
            local after_ok = after > #stem or is_separator(stem:sub(after, after))
            if before_ok and after_ok then return token end
            start = found + 1
        end
    end
    return nil
end

local function attrs_of(tag)
    if not tag then return {} end
    return Util.parse_attrs(tag)
end

local function has_property(item, property)
    for token in (item.properties or ""):gmatch("%S+") do
        if token == property then return true end
    end
    return false
end

local function extension(path)
    return (path:lower():match("%.([%a0-9]+)$")) or ""
end

local function split_href(href)
    if not href then return "", "" end
    local path, fragment = href:match("^([^#]*)#?(.*)$")
    return Util.url_decode(path or ""), Util.url_decode(fragment or "")
end

function Epub.read(reader, path)
    if not reader or not path or path == "" then return nil end
    local candidates = {path}
    local decoded = Util.url_decode(path)
    if decoded ~= path then candidates[#candidates + 1] = decoded end
    if path:sub(1, 1) == "/" then
        candidates[#candidates + 1] = path:sub(2)
    end
    for _, candidate in ipairs(candidates) do
        local content = reader:read(candidate)
        if content then return content end
    end
    return nil
end

function Epub.parse_container(xml)
    if not xml then return nil end
    for tag in xml:gmatch("<rootfile[^>]->") do
        local attrs = attrs_of(tag)
        if attrs["full-path"] then
            return Util.normalize_path(Util.url_decode(attrs["full-path"]))
        end
    end
    return nil
end

function Epub.parse_opf(xml, opf_path)
    local opf = {
        path = opf_path,
        manifest = {},
        manifest_by_id = {},
        spine = {},
        guide = {},
        version = "2.0",
        toc_id = nil,
    }
    if not xml then return opf end

    local package_tag = xml:match("<package[^>]*>")
    local version
    if package_tag then
        version = package_tag:match('version%s*=%s*"([^"]+)"')
            or package_tag:match("version%s*=%s*'([^']+)'")
    end
    if version then opf.version = version end

    local manifest = xml:match("<manifest[^>]*>(.-)</manifest>") or xml
    for tag in manifest:gmatch("<item[%s][^>]->") do
        local attrs = attrs_of(tag)
        if attrs.id and attrs.href then
            local item = {
                id = attrs.id,
                href = attrs.href,
                media_type = (attrs["media-type"] or ""):lower(),
                properties = (attrs.properties or ""):lower(),
                path = Util.join_path(Util.dirname(opf_path), Util.url_decode(attrs.href)),
            }
            opf.manifest[#opf.manifest + 1] = item
            opf.manifest_by_id[item.id] = item
        end
    end

    local spine_tag = xml:match("<spine[^>]*>")
    if spine_tag then
        local attrs = attrs_of(spine_tag)
        opf.toc_id = attrs.toc
    end
    local spine = xml:match("<spine[^>]*>(.-)</spine>") or ""
    for tag in spine:gmatch("<itemref[%s][^>]->") do
        local attrs = attrs_of(tag)
        if attrs.idref then
            opf.spine[#opf.spine + 1] = attrs.idref
        end
    end

    -- EPUB 2 reading-system guide. Only the type and href are needed: the
    -- front-matter pass resolves the href against the package directory.
    local guide = xml:match("<guide[^>]*>(.-)</guide>") or ""
    for tag in guide:gmatch("<reference[%s][^>]->") do
        local attrs = attrs_of(tag)
        if attrs.type and attrs.href then
            opf.guide[#opf.guide + 1] = {
                type = attrs.type:lower(),
                href = attrs.href,
            }
        end
    end

    return opf
end

local function is_xhtml_item(item)
    return XHTML_EXTENSIONS[extension(item.path)] == true
        or item.media_type == "application/xhtml+xml"
        or item.media_type == "text/html"
end

function Epub.spine_documents(reader, opf)
    local documents, seen = {}, {}
    for _, idref in ipairs(opf.spine) do
        local item = opf.manifest_by_id[idref]
        if item and is_xhtml_item(item) and not seen[item.path] then
            seen[item.path] = true
            documents[#documents + 1] = item.path
        end
    end
    if #documents == 0 then
        for _, item in ipairs(opf.manifest) do
            if is_xhtml_item(item) and not seen[item.path] then
                seen[item.path] = true
                documents[#documents + 1] = item.path
            end
        end
    end
    return documents
end

function Epub.css_documents(reader, opf)
    local documents = {}
    for _, item in ipairs(opf.manifest) do
        if CSS_EXTENSIONS[extension(item.path)] == true or item.media_type == "text/css" then
            documents[#documents + 1] = item.path
        end
    end
    return documents
end

function Epub.parse_ncx(xml, base_dir)
    local entries = {}
    local stack = {}
    if not xml then return entries end

    for tag, text in xml:gmatch("(<[^>]+>)([^<]*)") do
        local name = tag:match("^<%s*([%w_:.-]+)") or tag:match("^</%s*([%w_:.-]+)")
        local closing = tag:match("^</") ~= nil
        if name then name = name:lower() end

        if name == "navpoint" and not closing then
            stack[#stack + 1] = {depth = #stack + 1, title = "", href = nil}
        elseif name == "navpoint" and closing then
            local item = table.remove(stack)
            if item and item.href then
                local path, fragment = split_href(item.href)
                entries[#entries + 1] = {
                    title = Util.trim(Util.decode_entities(item.title)),
                    path = Util.join_path(base_dir, path),
                    fragment = fragment,
                    depth = item.depth,
                }
            end
        elseif name == "text" and not closing and #stack > 0 then
            stack[#stack].title = stack[#stack].title .. text
        elseif name == "content" and #stack > 0 then
            local attrs = attrs_of(tag)
            if attrs.src then stack[#stack].href = attrs.src end
        end
    end

    return entries
end

function Epub.parse_nav(xml, base_dir)
    local entries = {}
    if not xml then return entries end

    local nav_block
    for block in xml:gmatch("<nav[^>]->.-</nav>") do
        local opening = block:match("^<nav[^>]->")
        local attrs = attrs_of(opening)
        local type_attr = (attrs["epub:type"] or ""):lower()
        local role = (attrs.role or ""):lower()
        if type_attr:find("toc", 1, true) or role:find("doc-toc", 1, true) then
            nav_block = block
            break
        end
    end
    if not nav_block and xml:find("<a%s", 1) then nav_block = xml end
    if not nav_block then return entries end

    local depth = 0
    local current
    for tag, text in nav_block:gmatch("(<[^>]+>)([^<]*)") do
        local name = tag:match("^<%s*([%w_:.-]+)") or tag:match("^</%s*([%w_:.-]+)")
        local closing = tag:match("^</") ~= nil
        if name then name = name:lower() end

        if name == "ol" then
            depth = math.max(0, depth + (closing and -1 or 1))
        elseif name == "a" and not closing then
            local attrs = attrs_of(tag)
            if attrs.href then
                current = {
                    title = "",
                    href = attrs.href,
                    depth = math.max(depth, 1),
                }
                entries[#entries + 1] = current
                if text ~= "" then current.title = current.title .. text end
            end
        elseif name == "a" and closing then
            current = nil
        elseif current then
            current.title = current.title .. text
        end
    end

    for _, entry in ipairs(entries) do
        local path, fragment = split_href(entry.href)
        entry.title = Util.trim(Util.decode_entities(entry.title))
        entry.path = Util.join_path(base_dir, path)
        entry.fragment = fragment
        entry.href = nil
    end
    return entries
end

-- EPUB 3 landmarks navigation: it names the front-matter documents the way the
-- EPUB 2 guide does. Returns { {type = "title-page", href = "text/title.xhtml"}, ... }.
function Epub.parse_landmarks(xml)
    local entries = {}
    if not xml then return entries end

    for block in xml:gmatch("<nav[^>]->.-</nav>") do
        local opening = block:match("^<nav[^>]->")
        local attrs = attrs_of(opening)
        local kind = ((attrs["epub:type"] or "") .. " " .. (attrs.role or "")):lower()
        if kind:find("landmark", 1, true) then
            for tag in block:gmatch("<a[%s][^>]->") do
                local link = attrs_of(tag)
                if link.href and link["epub:type"] then
                    entries[#entries + 1] = {
                        type = link["epub:type"]:lower(),
                        href = link.href,
                    }
                end
            end
        end
    end
    return entries
end

-- Map of document path -> reason for every document that is front matter. The
-- scan skips pseudo-heading detection (all tiers, including quotes) for these.
-- Three independent sources are merged: the OPF guide, EPUB 3 landmarks and a
-- filename fallback for packages that declare neither.
function Epub.front_matter_paths(reader, opf)
    local paths = {}
    if not opf then return paths end
    local base = Util.dirname(opf.path or "")

    local function add(path, reason)
        path = Util.normalize_path(path or "")
        if path ~= "" and not paths[path] then paths[path] = reason end
    end

    local function add_kinds(kind_text, href, from_dir, prefix)
        for token in (kind_text or ""):gmatch("%S+") do
            local kind = token:match("([^:]+)$") or token
            kind = kind:lower()
            if FRONT_MATTER_TYPES[kind] then
                local path = split_href(href)
                add(Util.join_path(from_dir, path), prefix .. kind)
                return
            end
        end
    end

    for _, reference in ipairs(opf.guide or {}) do
        add_kinds(reference.type, reference.href, base, "guide:")
    end

    for _, item in ipairs(opf.manifest) do
        if is_xhtml_item(item) then
            local name = Util.basename(item.path)
            local token = basename_is_front_matter(name)
            if token then add(item.path, "filename:" .. token) end
        end
    end

    for _, item in ipairs(opf.manifest) do
        if is_xhtml_item(item) and has_property(item, "nav") then
            local xml = Epub.read(reader, item.path)
            local from_dir = Util.dirname(item.path)
            for _, entry in ipairs(Epub.parse_landmarks(xml)) do
                add_kinds(entry.type, entry.href, from_dir, "landmark:")
            end
            break
        end
    end

    return paths
end

function Epub.toc(reader, opf)
    local toc_item
    if opf.toc_id then toc_item = opf.manifest_by_id[opf.toc_id] end
    if toc_item then
        local xml = Epub.read(reader, toc_item.path)
        return Epub.parse_ncx(xml, Util.dirname(toc_item.path))
    end

    for _, item in ipairs(opf.manifest) do
        if item.properties:find("nav", 1, true) then
            local xml = Epub.read(reader, item.path)
            return Epub.parse_nav(xml, Util.dirname(item.path))
        end
    end

    for _, item in ipairs(opf.manifest) do
        local name = Util.basename(item.path):lower()
        if name == "toc.ncx" then
            local xml = Epub.read(reader, item.path)
            return Epub.parse_ncx(xml, Util.dirname(item.path))
        elseif name == "nav.xhtml" or name == "nav.html" then
            local xml = Epub.read(reader, item.path)
            return Epub.parse_nav(xml, Util.dirname(item.path))
        end
    end

    return {}
end

-- Font obfuscation is harmless here; encrypted text is not.
function Epub.is_encrypted(reader)
    local xml = Epub.read(reader, "META-INF/encryption.xml")
    if not xml then return false end
    for uri in xml:gmatch('URI%s*=%s*"([^"]+)"') do
        local path = Util.url_decode(uri):lower()
        if path:match("%.xhtml$") or path:match("%.html$") or path:match("%.htm$")
            or path:match("%.opf$") or path:match("%.ncx$") then
            return true
        end
    end
    return false
end

function Epub.find_opf(reader)
    local container = Epub.read(reader, "META-INF/container.xml")
    local opf_path = Epub.parse_container(container)
    if opf_path and Epub.read(reader, opf_path) then return opf_path end
    for _, entry in ipairs(reader:list()) do
        if entry.path:lower():match("%.opf$") then return entry.path end
    end
    return nil
end

return Epub
