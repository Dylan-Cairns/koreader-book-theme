-- A small, tolerant HTML scanner. It is not a browser parser: it builds just
-- enough structure to find block elements, their attributes and their text.
-- It accepts the malformed markup common in EPUBs and never throws.

local Util = require("hn_util")

local Html = {}

local VOID = {
    area = true, base = true, br = true, col = true, embed = true, hr = true,
    img = true, input = true, link = true, meta = true, param = true,
    source = true, track = true, wbr = true,
}

local BLOCK = {
    address = true, article = true, aside = true, blockquote = true, body = true,
    caption = true, dd = true, div = true, dl = true, dt = true, fieldset = true,
    figcaption = true, figure = true, footer = true, form = true,
    h1 = true, h2 = true, h3 = true, h4 = true, h5 = true, h6 = true,
    header = true, hr = true, li = true, main = true, nav = true, ol = true,
    p = true, pre = true, section = true, table = true, tbody = true,
    td = true, tfoot = true, th = true, thead = true, title = true, tr = true,
    ul = true,
}

local HEADING = {
    h1 = true, h2 = true, h3 = true, h4 = true, h5 = true, h6 = true,
}

function Html.is_block(tag) return BLOCK[tag] == true end
function Html.is_heading(tag) return HEADING[tag] == true end

local function find_tag_end(html, start_pos)
    local quote
    for index = start_pos + 1, #html do
        local character = html:sub(index, index)
        if quote then
            if character == quote then quote = nil end
        elseif character == '"' or character == "'" then
            quote = character
        elseif character == ">" then
            return index
        end
    end
    return nil
end

local function new_element(doc, tag, attrs, parent)
    local element = {
        index = #doc.elements + 1,
        tag = tag,
        attrs = attrs,
        parent = parent,
        children = {},
        depth = parent and (parent.depth + 1) or 1,
        own_text = "",
        text = "",
        classes = Util.split_whitespace(attrs.class),
        class_set = {},
        id = attrs.id,
        style = attrs.style,
        epub_type = attrs["epub:type"] or attrs["epub-type"],
        role = attrs.role,
        aria_level = tonumber(attrs["aria-level"] or ""),
        in_head = tag == "head" or (parent and parent.in_head) or false,
        closed = false,
    }
    for _, class_name in ipairs(element.classes) do
        element.class_set[class_name] = true
    end
    doc.elements[element.index] = element
    if parent then parent.children[#parent.children + 1] = element end
    if element.id and element.id ~= "" and not doc.by_id[element.id] then
        doc.by_id[element.id] = element
    end
    if tag == "body" and not doc.body then doc.body = element end
    return element
end

-- Parse an HTML/XHTML fragment. Returns
--   { elements = {...}, by_id = {...}, body = element|nil }
function Html.parse(html)
    local doc = {elements = {}, by_id = {}}
    if not html or html == "" then return doc end
    html = html:gsub("^\239\187\191", "")
    local lower_html = html:lower()
    local stack = {}
    local position = 1

    local function top() return stack[#stack] end

    local function add_text(text)
        local element = top()
        if not element or text == "" then return end
        if #element.own_text < 4000 then
            element.own_text = element.own_text .. text
        end
    end

    local function pop_through(tag_name)
        while #stack > 0 do
            local element = table.remove(stack)
            element.closed = true
            if element.tag == tag_name then return true end
        end
        return false
    end

    while position <= #html do
        local tag_start = html:find("<", position, true)
        if not tag_start then
            add_text(html:sub(position))
            break
        end
        add_text(html:sub(position, tag_start - 1))

        if html:sub(tag_start, tag_start + 3) == "<!--" then
            local close = html:find("-->", tag_start + 4, true)
            position = close and (close + 3) or (#html + 1)
        elseif html:sub(tag_start, tag_start + 8) == "<![CDATA[" then
            local close = html:find("]]>", tag_start + 9, true)
            if close then
                add_text(html:sub(tag_start + 9, close - 1))
                position = close + 3
            else
                position = #html + 1
            end
        elseif html:sub(tag_start, tag_start + 1) == "<!" or html:sub(tag_start, tag_start + 1) == "<?" then
            local close = html:find(">", tag_start + 2, true)
            position = close and (close + 1) or (#html + 1)
        elseif html:sub(tag_start, tag_start + 1) == "</" then
            local close = html:find(">", tag_start + 2, true)
            if not close then break end
            local name = html:sub(tag_start + 2, close - 1):match("^%s*([%w_:.-]+)")
            if name then pop_through(name:lower()) end
            position = close + 1
        else
            local tag_end = find_tag_end(html, tag_start)
            if not tag_end then break end
            local inside = html:sub(tag_start + 1, tag_end - 1)
            local self_closing = inside:sub(-1) == "/"
            if self_closing then inside = inside:sub(1, -2) end
            local tag = inside:match("^%s*([%w_:.-]+)")
            if not tag then
                position = tag_end + 1
            else
                tag = tag:lower()
                -- Implicitly close a paragraph before the next block, as
                -- browsers do; EPUBs rely on this more often than they should.
                if BLOCK[tag] and top() and top().tag == "p" and tag ~= "p" then
                    pop_through("p")
                end
                if tag == "li" and top() and top().tag == "li" then pop_through("li") end
                if (tag == "dt" or tag == "dd") and top() and
                    (top().tag == "dt" or top().tag == "dd") then
                    pop_through(top().tag)
                end

                local attrs = Util.parse_attrs(inside)
                local element = new_element(doc, tag, attrs, top())
                if not VOID[tag] and not self_closing then
                    stack[#stack + 1] = element
                end

                if tag == "script" or tag == "style" then
                    local close_start = lower_html:find("</" .. tag, tag_end + 1, true)
                    if close_start then
                        local close_end = html:find(">", close_start, true)
                        pop_through(tag)
                        position = close_end and (close_end + 1) or (#html + 1)
                    else
                        position = #html + 1
                    end
                else
                    position = tag_end + 1
                end
            end
        end
    end

    while #stack > 0 do
        local element = table.remove(stack)
        element.closed = true
    end

    -- Children always have a greater index than their parent, so one reverse
    -- pass is enough to collect each element's full text.
    for index = #doc.elements, 1, -1 do
        local element = doc.elements[index]
        local text = element.own_text
        for _, child in ipairs(element.children) do
            if child.text ~= "" then
                text = text .. " " .. child.text
            end
        end
        text = Util.trim(text:gsub("%s+", " "))
        if #text > 400 then text = text:sub(1, 400) end
        element.text = text
    end

    return doc
end

function Html.first_block_element(doc)
    for _, element in ipairs(doc.elements) do
        if not element.in_head and BLOCK[element.tag]
            and element.tag ~= "body" and element.tag ~= "html"
            and element.text ~= "" then
            return element
        end
    end
    return nil
end

function Html.is_ancestor(ancestor, element)
    local current = element.parent
    while current do
        if current.index == ancestor.index then return true end
        current = current.parent
    end
    return false
end

function Html.has_block_children(element)
    for _, child in ipairs(element.children) do
        if BLOCK[child.tag] and child.text ~= "" then return true end
    end
    return false
end

function Html.first_block_child(element)
    for _, child in ipairs(element.children) do
        if BLOCK[child.tag] and child.text ~= "" then return child end
    end
    return nil
end

function Html.first_block_in_body(doc)
    if not doc.body then return Html.first_block_element(doc) end
    return Html.first_block_child(doc.body) or Html.first_block_element(doc)
end

function Html.climb_to_block(element)
    local current = element
    while current and not BLOCK[current.tag] do
        current = current.parent
    end
    return current
end

function Html.ancestor_tag(element, tags)
    local current = element.parent
    while current do
        if tags[current.tag] then return current.tag end
        current = current.parent
    end
    return nil
end

function Html.ancestor_class_token(element, token)
    local current = element.parent
    while current do
        for _, class_name in ipairs(current.classes) do
            if class_name:lower():find(token, 1, true) then return class_name end
        end
        current = current.parent
    end
    return nil
end

return Html
