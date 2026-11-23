-- KOReader adapter. The actual work lives in the pure hn_* modules; this file
-- wires them to the document, the style-tweak pipeline and the menu.

local Archiver = require("ffi/archiver")
local DataStorage = require("datastorage")
local Device = require("device")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")

local Generate = require("hn_generate")
local Scan = require("hn_scan")
local Settings = require("hn_settings")
local Theme = require("hn_theme")
local Cache = require("hn_cache")

-- Cache format version. Version 2 adds the theme hash: a cache written under
-- the old product name (version 1) has no hash, so it is rescanned once.
-- Version 3 changes detection (semantic kind gate, ToC shape check, quotes).
-- Version 4 adds the glued chapter-number rules and sup/sub defaults, and the
-- theme settings shrink to two fonts. Version 5 turns the chapter-number rule
-- from a block line into an inline gap. Version 6 centres part/chapter titles,
-- widens the space below them and pairs a standalone number heading with the
-- title heading. Version 7 makes the pair rules repeat the full margin
-- shorthand. Version 9 cancels a publisher's negative pull-up on the block
-- after a chapter title (version 8 existed only as a spacing probe on the test
-- device and was never committed). Version 10 centres every heading level and
-- widens the size ladder to 1.75/1.50/1.25/1.00 rem. Version 11 stores the
-- generator inputs, so a font change rebuilds the open book without a reopen.
local VERSION = 11

-- Saves always write the current key. The legacy heading_normalizer* keys are
-- read only as a fallback, so an existing device state survives the rename. A
-- toggle that is turned off deletes both keys, otherwise the legacy value would
-- switch the feature back on through the fallback.
local KEY = {
    enabled = "book_theme_enabled",
    enabled_legacy = "heading_normalizer_enabled",
    disabled = "book_theme_disabled",
    disabled_legacy = "heading_normalizer_disabled",
    settings = "book_theme_settings",
    cache = "book_theme",
    cache_legacy = "heading_normalizer",
}

local ArchiveBook = {}
ArchiveBook.__index = ArchiveBook

function ArchiveBook.new(path)
    local archive = Archiver.Reader:new()
    if not archive:open(path) then
        return nil, archive.err or "could not open archive"
    end
    local book = setmetatable({archive = archive, entries = {}, by_path = {}}, ArchiveBook)
    for entry in archive:iterate() do
        if entry.mode == "file" then
            local item = {path = entry.path, size = entry.size or 0}
            book.entries[#book.entries + 1] = item
            book.by_path[entry.path] = item
        end
    end
    return book
end

function ArchiveBook:list()
    return self.entries
end

function ArchiveBook:read(path)
    local entry = self.by_path[path]
    if not entry then
        local lowered = path:lower()
        for _, item in ipairs(self.entries) do
            if item.path:lower() == lowered then
                entry = item
                break
            end
        end
    end
    if not entry then return nil end
    local content = self.archive:extractToMemory(entry.path)
    if not content and self.archive.err then
        logger.warn("book-theme: cannot read", entry.path, self.archive.err)
    end
    return content
end

function ArchiveBook:close()
    self.archive:close()
end

local BookTheme = WidgetContainer:extend{
    name = "booktheme",
}

function BookTheme:init()
    self.generated_css = nil
    self.report = nil
    self:loadTheme()
    -- The same plugin is instantiated by the file manager, where there is no
    -- document or style-tweak pipeline. Only the reader gets a menu entry.
    if self.ui and self.ui.document and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
    if self.ui and self.ui.styletweak then
        self:installCssHook()
    end
end

-- The stored theme is merged over the defaults and validated field by field.
-- Invalid values fall back to their default and are logged; a broken settings
-- table must never stop a book from opening.
function BookTheme:loadTheme()
    local stored = Settings.read(G_reader_settings, KEY.settings)
    local theme, problems = Theme.load(stored)
    self.theme = theme
    self.theme_hash = Theme.hash(theme)
    for _, problem in ipairs(problems) do
        logger.warn("book-theme: theme setting ignored:", problem)
    end
    return theme
end

-- ReaderTypeset rebuilds the stylesheet on every ApplyStyleSheet. Appending
-- here means the generated CSS survives later style changes instead of being
-- silently dropped the next time the user edits a tweak.
function BookTheme:installCssHook()
    local styletweak = self.ui.styletweak
    if not styletweak or styletweak._book_theme_hooked then return end
    local original = styletweak.getCssText
    local plugin = self
    styletweak.getCssText = function(instance)
        local css = original(instance)
        local extra = plugin.generated_css
        if not extra or extra == "" then return css end
        if not css or css == "" then return extra end
        return css .. "\n" .. extra
    end
    styletweak._book_theme_hooked = true
end

function BookTheme:isEnabled()
    return Settings.read_true(G_reader_settings, KEY.enabled, KEY.enabled_legacy)
end

function BookTheme:isBookDisabled()
    return Settings.read_true(self.ui.doc_settings, KEY.disabled, KEY.disabled_legacy)
end

function BookTheme:readCache()
    return Settings.read(self.ui.doc_settings, KEY.cache, KEY.cache_legacy)
end

function BookTheme:isEpub()
    local format = self.ui.document and self.ui.document:getDocumentFormat() or ""
    return format:lower():find("epub", 1, true) ~= nil
end

function BookTheme:scanNow()
    local path = self.ui.document and self.ui.document.file
    if not path then return {error = "no document path"} end
    local book, err = ArchiveBook.new(path)
    if not book then return {error = err} end
    local ok, result = pcall(Scan.scan, book, {
        theme = self.theme,
    })
    book:close()
    if not ok then
        return {error = tostring(result)}
    end
    return result
end

local function report_for_storage(result)
    result = result or {}
    local report = {
        skipped = result.skipped,
        error = result.error,
        theme_hash = result.theme_hash,
        stats = result.stats,
        warnings = {},
        candidates = {},
    }
    for index, warning in ipairs(result.warnings or {}) do
        if index > 20 then break end
        report.warnings[#report.warnings + 1] = warning
    end
    for _, candidate in ipairs(result.candidates or {}) do
        if #report.candidates >= 200 then break end
        report.candidates[#report.candidates + 1] = {
            selector = candidate.selector,
            level = candidate.level,
            score = candidate.score,
            text = candidate.text,
            reasons = candidate.reasons,
        }
    end
    return report
end

function BookTheme:applyCss()
    local document = self.ui.document
    local typeset = self.ui.typeset
    local styletweak = self.ui.styletweak
    if not document or not typeset or not styletweak then return end
    document:setStyleSheet(typeset.css or document.default_css,
        styletweak:getCssText() or "")
end

-- One write path for the per-book cache, so a rescan and a live theme rebuild
-- always persist the same fields, including the generator inputs.
function BookTheme:writeCache(css, report, generation)
    if not self.ui or not self.ui.doc_settings then return end
    self.ui.doc_settings:saveSetting(KEY.cache, {
        version = VERSION,
        theme_hash = self.theme_hash,
        css = css or "",
        report = report,
        generation = generation,
        scanned_at = os.time(),
    })
end

function BookTheme:onPreRenderDocument(doc_settings)
    self.ui.doc_settings = doc_settings or self.ui.doc_settings
    local ok, err = pcall(function() self:prepareForRender() end)
    if not ok then
        logger.err("book-theme: " .. tostring(err))
        self.generated_css = nil
    end
end

function BookTheme:prepareForRender()
    if not self:isEnabled() or self:isBookDisabled() or not self:isEpub() then
        self.generated_css = nil
        return
    end

    local cached = self:readCache()
    if Cache.is_valid(cached, VERSION, self.theme_hash) then
        self.generated_css = cached.css ~= "" and cached.css or nil
        self.report = cached.report
    else
        local result = self:scanNow()
        self.report = report_for_storage(result)
        self.generated_css = result and result.css or nil
        self:writeCache(self.generated_css, self.report, result and result.generation)
        logger.info("book-theme: scanned",
            self.ui.document.file,
            "theme", self.theme_hash,
            self.report and self.report.stats and self.report.stats.pseudo_headings or 0)
    end

    if self.generated_css then
        self:applyCss()
    end
end

-- Rebuild this book's stylesheet from the stored generator inputs. If a cache
-- predates the stored inputs (or was just cleared), one scan runs instead. The
-- CSS is byte-identical to a fresh scan of the same book under this theme.
function BookTheme:rebuildCss()
    local cached = self:readCache()
    local generation = cached and cached.generation
    if not generation then
        local result = self:scanNow()
        if not result or result.error then
            return nil, (result and result.error) or "scan failed"
        end
        generation = result.generation
        self.report = report_for_storage(result)
    else
        self.report = cached.report or self.report
    end
    if type(generation) ~= "table" then
        return nil, "no scan data"
    end
    local css = Generate.from_generation(generation, self.theme)
    if not css then return nil, "generation failed" end
    return css, nil, generation
end

-- Apply a theme change to the book that is open right now. ReaderTypeset's
-- ApplyStyleSheet is the same path KOReader uses when a style tweak changes: it
-- re-applies the stylesheet and preserves the reading position. On failure the
-- old CSS stays on screen and the next open picks up the new theme from cache.
function BookTheme:applyThemeToOpenBook()
    if not self:isEnabled() or self:isBookDisabled() or not self:isEpub() then
        return false
    end
    local ok, css, err, generation = pcall(function() return self:rebuildCss() end)
    if not ok then
        logger.err("book-theme: rebuild failed: " .. tostring(css))
        return false
    end
    if not css then
        logger.warn("book-theme: rebuild failed: " .. tostring(err))
        return false
    end
    self.generated_css = css
    self:writeCache(css, self.report, generation)
    local applied = pcall(function()
        self.ui:handleEvent(Event:new("ApplyStyleSheet"))
    end)
    if not applied then
        logger.err("book-theme: could not apply the new stylesheet")
        return false
    end
    return true
end

function BookTheme:currentReport()
    if self.report then return self.report end
    local cached = self:readCache()
    return cached and cached.report or nil
end

function BookTheme:formatReport()
    local report = self:currentReport()
    if not report then return _("No scan has run for this book yet.") end
    local lines = {}
    if report.error then
        lines[#lines + 1] = _("Error: ") .. tostring(report.error)
    end
    if report.skipped then
        lines[#lines + 1] = _("Skipped: ") .. tostring(report.skipped)
    end
    local stats = report.stats or {}
    lines[#lines + 1] = string.format(
        _("Documents: %d   Stylesheets: %d   ToC entries: %d   Pseudo-headings: %d"),
        stats.documents or 0, stats.stylesheets or 0,
        stats.toc_entries or 0, stats.pseudo_headings or 0)
    if (stats.heading_markers or 0) > 0 then
        lines[#lines + 1] = string.format(_("Glued chapter numbers: %d"),
            stats.heading_markers)
    end
    if (stats.heading_numbers or 0) > 0 then
        lines[#lines + 1] = string.format(_("Standalone chapter numbers: %d"),
            stats.heading_numbers)
    end
    for _, candidate in ipairs(report.candidates or {}) do
        lines[#lines + 1] = string.format("L%d  %s  (%d)  %s",
            candidate.level or 0, candidate.selector or "?",
            candidate.score or 0, candidate.text or "")
    end
    local warning_prefix = _("Warning: ")
    for _, warning in ipairs(report.warnings or {}) do
        lines[#lines + 1] = warning_prefix .. warning
    end
    return table.concat(lines, "\n")
end

function BookTheme:currentCss()
    if self.generated_css and self.generated_css ~= "" then return self.generated_css end
    local cached = self:readCache()
    if cached and cached.css and cached.css ~= "" then return cached.css end
    return nil
end

function BookTheme:showReport(title, text)
    if not text or text == "" then
        UIManager:show(InfoMessage:new{text = _("Nothing to show.")})
        return
    end
    UIManager:show(TextViewer:new{
        title = title,
        text = text,
    })
end

local function show_info(text)
    UIManager:show(InfoMessage:new{text = text})
end

-- The theme is authoritative for body type; this only keeps the font shown in
-- KOReader's Aa menu in step. No size, spacing, margin or gamma is touched.
function BookTheme:syncBodyFont(family)
    if type(family) ~= "string" or family == "" then return end
    G_reader_settings:saveSetting("cre_font", family)
    -- A book that already pins its own face (ReaderFont saves `font_face` per
    -- book) ignores `cre_font` in the Aa menu. Update the live face and the
    -- pinned value so the menu agrees, without forcing a mid-session re-render:
    -- the stylesheet already enforces the family.
    local font = self.ui and self.ui.font
    if font then font.font_face = family end
    local settings = self.ui and self.ui.doc_settings
    if settings and settings:readSetting("font_face") ~= nil then
        settings:saveSetting("font_face", family)
    end
end

-- The single write path for a font choice. The settings table stores only the
-- two families, never the derived sizes and weights. The open book is rebuilt
-- from its cached generator inputs and re-rendered in place; only when that is
-- impossible (no document, disabled book, failed rebuild) does the change wait
-- for the next open. `generated_css` is never cleared here: clearing it could
-- drop styling mid-session on the next stylesheet rebuild.
function BookTheme:setFont(which, family)
    local fonts = Theme.fonts(self.theme)
    if fonts[which] == family then return true end
    fonts[which] = family
    local changed, problems = Theme.from_fonts(fonts)
    if not changed or #problems > 0 then
        show_info(_("The theme was not changed: ") .. table.concat(problems or {}, "; "))
        return false
    end
    G_reader_settings:saveSetting(KEY.settings, Theme.settings(changed))
    self:loadTheme()
    if which == "body" then
        self:syncBodyFont(family)
    end
    local applied = self.ui and self.ui.document and self:applyThemeToOpenBook()
    local message
    if applied then
        message = _("Applied to this book now.")
    else
        message = _("Takes effect the next time this book is opened.")
    end
    if which == "body" then
        message = _("The Aa menu font now matches.") .. "\n" .. message
    end
    show_info(message)
    return true
end

-- Same source as ReaderFont, read on demand so a font added since KOReader
-- started appears in the list without a restart.
function BookTheme:installedFonts()
    local ok, faces = pcall(function()
        local cre = require("document/credocument"):engineInit()
        return cre.getFontFaces()
    end)
    if not ok or type(faces) ~= "table" then return {} end
    local seen, result = {}, {}
    for _, face in ipairs(faces) do
        if type(face) == "string" then
            local name = face:match("^%s*(.-)%s*$")
            if name ~= "" and not seen[name] then
                seen[name] = true
                result[#result + 1] = name
            end
        end
    end
    table.sort(result)
    return result
end

-- One picker per font role. The list is rebuilt from KOReader's installed
-- faces each time it opens, so a font added since start appears without a
-- restart.
function BookTheme:fontItems(which)
    local items = {}
    for _, face in ipairs(self:installedFonts()) do
        items[#items + 1] = {
            text = face,
            checked_func = function() return Theme.fonts(self.theme)[which] == face end,
            callback = function() self:setFont(which, face) end,
        }
    end
    if #items == 0 then
        items[1] = {
            text = _("No installed fonts found."),
            enabled = false,
        }
    end
    return items
end

function BookTheme:formatThemeSummary()
    local fonts = Theme.fonts(self.theme)
    return table.concat({
        string.format(_("Body font: %s"), tostring(fonts.body)),
        string.format(_("Heading font: %s"), tostring(fonts.heading)),
        string.format(_("Theme: %s"), tostring(self.theme_hash)),
    }, "\n")
end

function BookTheme:formatStatus()
    return self:formatThemeSummary() .. "\n\n" .. self:formatReport()
end

-- The theme owns weight. Everything else in KOReader's font and layout menus
-- is left alone, and contrast has to stay there because CSS cannot scope gamma.
function BookTheme:prepareReaderSettings()
    G_reader_settings:saveSetting("copt_font_base_weight", 0)
    local settings = self.ui and self.ui.doc_settings
    if settings and settings:readSetting("copt_font_base_weight") ~= nil then
        settings:saveSetting("copt_font_base_weight", 0)
    end
    local font = self.ui and self.ui.font
    if font and font.configurable then
        font.configurable.font_base_weight = 0
    end
    show_info(_("KOReader font weight is set to 0 for this book and as the default: the theme owns weight.") .. "\n"
        .. _("Contrast stays in KOReader, because CSS cannot scope gamma.") .. "\n"
        .. _("Takes effect the next time a book is opened."))
end

function BookTheme:restoreDefaultTheme()
    G_reader_settings:delSetting(KEY.settings)
    self:loadTheme()
    self:syncBodyFont(self.theme.body.family)
    show_info(_("Default theme restored; the Aa menu font now matches.") .. "\n"
        .. _("Takes effect the next time this book is opened."))
end

function BookTheme:exportStyleTweak()
    local css = self:currentCss()
    if not css then
        show_info(_("No generated CSS yet. Open this book once so it can be scanned."))
        return
    end
    local dir = DataStorage:getDataDir() .. "/styletweaks"
    local path = dir .. "/book-theme.css"
    local ok, result = pcall(function()
        if lfs.attributes(dir, "mode") ~= "directory" then
            lfs.mkdir(dir)
        end
        if lfs.attributes(dir, "mode") ~= "directory" then
            error("cannot create " .. dir)
        end
        local file = assert(io.open(path, "wb"))
        assert(file:write(css))
        assert(file:close())
    end)
    if not ok then
        logger.warn("book-theme: style tweak export failed:", result)
        show_info(string.format(_("Could not write %s: %s"), path, tostring(result)))
        return
    end
    show_info(string.format(_("Exported to %s."), path) .. "\n"
        .. _("Enabling it under User style tweaks duplicates the plugin's own CSS; keep one of them."))
end

function BookTheme:addToMainMenu(menu_items)
    if not (self.ui and self.ui.document) then return end
    local function toggleGlobal()
        if self:isEnabled() then
            G_reader_settings:delSetting(KEY.enabled)
            G_reader_settings:delSetting(KEY.enabled_legacy)
        else
            G_reader_settings:saveSetting(KEY.enabled, true)
        end
        self.generated_css = nil
        UIManager:show(InfoMessage:new{
            text = _("Takes effect the next time a book is opened."),
        })
    end

    local function toggleBook()
        local settings = self.ui.doc_settings
        if self:isBookDisabled() then
            settings:delSetting(KEY.disabled)
            settings:delSetting(KEY.disabled_legacy)
        else
            settings:saveSetting(KEY.disabled, true)
        end
        self.generated_css = nil
        UIManager:show(InfoMessage:new{
            text = _("Takes effect the next time this book is opened."),
        })
    end

    menu_items.book_theme = {
        text = _("Book Theme"),
        sorting_hint = "tools",
        sub_item_table = {
            -- The two decisions a reader actually makes. Everything else about
            -- the type is a fixed default.
            {
                text = _("Body font"),
                sub_item_table_func = function() return self:fontItems("body") end,
            },
            {
                text = _("Heading font"),
                sub_item_table_func = function() return self:fontItems("heading") end,
            },
            {
                text = _("Restore default theme"),
                separator = true,
                callback = function() self:restoreDefaultTheme() end,
            },
            {
                text = _("Enable for all books"),
                checked_func = function() return self:isEnabled() end,
                callback = toggleGlobal,
            },
            {
                text = _("Disable for this book"),
                checked_func = function() return self:isBookDisabled() end,
                callback = toggleBook,
            },
            {
                text = _("Diagnostics"),
                separator = true,
                sub_item_table = {
                    {
                        text = _("Status and detected headings"),
                        callback = function()
                            self:showReport(_("Book Theme"), self:formatStatus())
                        end,
                    },
                    {
                        text = _("View generated CSS"),
                        callback = function()
                            self:showReport(_("Generated theme CSS"), self:currentCss())
                        end,
                    },
                    {
                        text = _("Copy generated CSS"),
                        callback = function()
                            local css = self:currentCss()
                            if not css then
                                UIManager:show(InfoMessage:new{text = _("No generated CSS yet.")})
                            elseif Device:hasClipboard() then
                                Device:setClipboardText(css)
                                Notification:notify(_("Theme CSS copied to clipboard."))
                            else
                                UIManager:show(InfoMessage:new{text = _("Clipboard not available.")})
                            end
                        end,
                    },
                    {
                        text = _("Export generated CSS as style tweak"),
                        callback = function() self:exportStyleTweak() end,
                    },
                    {
                        text = _("Prepare KOReader settings"),
                        help_text = _("Sets KOReader's font weight to 0."
                            .. " Size, spacing, margins and contrast are untouched."),
                        callback = function() self:prepareReaderSettings() end,
                    },
                    {
                        text = _("Re-scan this book on next open"),
                        callback = function()
                            -- Drop the legacy cache too, or the fallback would serve it again.
                            self.ui.doc_settings:delSetting(KEY.cache)
                            self.ui.doc_settings:delSetting(KEY.cache_legacy)
                            self.generated_css = nil
                            UIManager:show(InfoMessage:new{
                                text = _("The next opening of this book will scan it again."),
                            })
                        end,
                    },
                },
            },
        },
    }
end

return BookTheme
