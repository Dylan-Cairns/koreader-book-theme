-- A deliberately small CSS reader. It understands the simple selectors and
-- declarations that decide whether a block looks like a heading. It ignores
-- pseudo-classes, attribute selectors, combinators and @font-face.

local Util = require("hn_util")

local Css = {}

local function valid_ident(text)
    return text:match("^[%a_][%w_-]*$") ~= nil
end

local function parse_selector(selector)
    if not selector or selector == "" then return nil end
    if selector:find("[%s>+~%[%]():]") then return nil end

    local rule = {classes = {}}
    local rest = selector

    local hash = rest:find("#", 1, true)
    if hash then
        local before = rest:sub(1, hash - 1)
        local after = rest:sub(hash + 1)
        local id, tail = after:match("^([%w_:.-]+)(.*)$")
        if not id then return nil end
        rule.id = id
        rest = before .. (tail or "")
    end

    if rest == "*" then
        rule.tag = nil
    elseif rest == "" then
        if not rule.id then return nil end
    elseif rest:sub(1, 1) == "." then
        for class_name in rest:gmatch("[^.]+") do
            if not valid_ident(class_name) then return nil end
            rule.classes[#rule.classes + 1] = class_name
        end
    else
        local tag = rest:match("^[^.]+")
        if not tag or not valid_ident(tag) then return nil end
        rule.tag = tag:lower()
        for class_name in rest:gmatch("%.([^.]+)") do
            if not valid_ident(class_name) then return nil end
            rule.classes[#rule.classes + 1] = class_name
        end
    end

    if not rule.tag and not rule.id and #rule.classes == 0 then return nil end
    rule.spec = (rule.id and 100 or 0) + (#rule.classes * 10) + (rule.tag and 1 or 0)
    return rule
end

local function parse_declarations(body)
    local declarations = {}
    for piece in body:gmatch("[^;]+") do
        local value, important = piece:match("^(.-)%s*!important%s*$")
        if value then
            piece = value
        else
            important = false
        end
        local property, declaration = piece:match("^%s*([%w%-]+)%s*:%s*(.-)%s*$")
        if property then
            declarations[property:lower()] = {
                value = Util.trim(declaration),
                important = important == true,
            }
        end
    end
    return declarations
end

local function parse_rules(text, rules, order, depth)
    local position = 1
    depth = depth or 0
    while position <= #text and depth < 8 do
        local open = text:find("{", position, true)
        if not open then break end
        local selector = Util.trim(text:sub(position, open - 1))
        if selector == "" then
            position = open + 1
        else
            local nesting = 1
            local index = open + 1
            local quote
            while index <= #text and nesting > 0 do
                local character = text:sub(index, index)
                if quote then
                    if character == quote then quote = nil end
                elseif character == '"' or character == "'" then
                    quote = character
                elseif character == "{" then
                    nesting = nesting + 1
                elseif character == "}" then
                    nesting = nesting - 1
                end
                index = index + 1
            end
            local body = text:sub(open + 1, index - 2)
            if selector:sub(1, 1) == "@" then
                local at_rule = selector:lower()
                if at_rule:find("^@media") or at_rule:find("^@supports") then
                    order = parse_rules(body, rules, order, depth + 1)
                end
            else
                local declarations = parse_declarations(body)
                if next(declarations) then
                    for part in selector:gmatch("[^,]+") do
                        local rule = parse_selector(Util.trim(part))
                        if rule then
                            rule.declarations = declarations
                            rule.order = order
                            order = order + 1
                            rules[#rules + 1] = rule
                        end
                    end
                end
            end
            position = index
        end
    end
    return order
end

function Css.parse(text)
    local rules = {}
    if not text or text == "" then return rules end
    text = text:gsub("/%*.-%*/", " ")
    parse_rules(text, rules, 1, 0)
    table.sort(rules, function(left, right) return left.order < right.order end)
    return rules
end

local function matches(rule, element)
    if rule.tag and rule.tag ~= element.tag then return false end
    if rule.id and rule.id ~= element.id then return false end
    for _, class_name in ipairs(rule.classes) do
        if not element.class_set[class_name] then return false end
    end
    return true
end

function Css.compute(element, rules)
    local best = {}
    local function apply(declarations, specificity, force_important)
        for property, declaration in pairs(declarations) do
            local important = declaration.important or force_important
            local current = best[property]
            if not current
                or (important and not current.important)
                or (important == current.important and specificity >= current.specificity) then
                best[property] = {
                    value = declaration.value,
                    important = important,
                    specificity = specificity,
                }
            end
        end
    end
    for _, rule in ipairs(rules) do
        if matches(rule, element) then
            apply(rule.declarations, rule.spec, false)
        end
    end
    if element.style and element.style ~= "" then
        apply(parse_declarations(element.style), 1000, true)
    end
    local values = {}
    for property, declaration in pairs(best) do
        values[property] = declaration.value
    end
    return values
end

local KEYWORD_SIZES = {
    ["xx-small"] = 0.6, ["x-small"] = 0.75, ["small"] = 0.89,
    ["medium"] = 1.0, ["large"] = 1.2, ["x-large"] = 1.5,
    ["xx-large"] = 2.0, ["smaller"] = 0.85, ["larger"] = 1.2,
}

function Css.font_size_ratio(value)
    if not value then return nil end
    value = Util.trim(value:lower())
    if KEYWORD_SIZES[value] then return KEYWORD_SIZES[value] end
    local percent = value:match("^([%d%.]+)%%$")
    if percent then return tonumber(percent) / 100 end
    local number, unit = value:match("^([%d%.]+)%s*(%a*)$")
    if not number then return nil end
    number = tonumber(number)
    if not number then return nil end
    if unit == "em" or unit == "rem" then return number end
    if unit == "ex" or unit == "ch" then return number * 0.5 end
    if unit == "px" then return number / 16 end
    if unit == "pt" then return number / 12 end
    if unit == "pc" then return number / 6 end
    return nil
end

function Css.is_bold(value)
    if not value then return false end
    value = Util.trim(value:lower())
    if value == "bold" or value == "bolder" then return true end
    local number = tonumber(value)
    return number ~= nil and number >= 600
end

function Css.is_centered(value)
    return value ~= nil and Util.trim(value:lower()) == "center"
end

function Css.is_upper(value)
    return value ~= nil and Util.trim(value:lower()) == "uppercase"
end

function Css.page_break_before(value)
    if not value then return false end
    value = Util.trim(value:lower())
    return value == "always" or value == "left" or value == "right"
        or value == "recto" or value == "verso" or value == "page"
end

function Css.margin_top(value)
    if not value then return 0 end
    value = Util.trim(value:lower())
    local number, unit = value:match("^(-?[%d%.]+)%s*(%a*)$")
    if not number then return 0 end
    number = tonumber(number) or 0
    if unit == "em" or unit == "rem" then return number end
    if unit == "px" then return number / 16 end
    if unit == "pt" then return number / 12 end
    return 0
end

return Css
