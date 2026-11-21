-- EPUB container, package and navigation parsing. The caller supplies a
-- reader object with list() and read(path); tests use an in-memory reader and
-- the plugin uses KOReader's libarchive wrapper.

local Util = require("hn_util")

local Epub = {}

local XHTML_EXTENSIONS = {xhtml = true, html = true, htm = true}
local CSS_EXTENSIONS = {css = true}

local function attrs_of(tag)
    if not tag then return {} end
    return Util.parse_attrs(tag)
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
