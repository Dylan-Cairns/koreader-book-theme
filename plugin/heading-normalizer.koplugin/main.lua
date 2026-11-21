-- KOReader adapter. The actual work lives in the pure hn_* modules; this file
-- wires them to the document, the style-tweak pipeline and the menu.

local Archiver = require("ffi/archiver")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local Scan = require("hn_scan")

local VERSION = 1

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
        logger.warn("heading-normalizer: cannot read", entry.path, self.archive.err)
    end
    return content
end

function ArchiveBook:close()
    self.archive:close()
end

local HeadingNormalizer = WidgetContainer:extend{
    name = "headingnormalizer",
}

function HeadingNormalizer:init()
    self.generated_css = nil
    self.report = nil
    self.ui.menu:registerToMainMenu(self)
    self:installCssHook()
end

-- ReaderTypeset rebuilds the stylesheet on every ApplyStyleSheet. Appending
-- here means the generated CSS survives later style changes instead of being
-- silently dropped the next time the user edits a tweak.
function HeadingNormalizer:installCssHook()
    local styletweak = self.ui.styletweak
    if not styletweak or styletweak._heading_normalizer_hooked then return end
    local original = styletweak.getCssText
    local plugin = self
    styletweak.getCssText = function(instance)
        local css = original(instance)
        local extra = plugin.generated_css
        if not extra or extra == "" then return css end
        if not css or css == "" then return extra end
        return css .. "\n" .. extra
    end
    styletweak._heading_normalizer_hooked = true
end

function HeadingNormalizer:isEnabled()
    return G_reader_settings:isTrue("heading_normalizer_enabled")
end

function HeadingNormalizer:isBookDisabled()
    return self.ui.doc_settings and self.ui.doc_settings:isTrue("heading_normalizer_disabled")
end

function HeadingNormalizer:isEpub()
    local format = self.ui.document and self.ui.document:getDocumentFormat() or ""
    return format:lower():find("epub", 1, true) ~= nil
end

function HeadingNormalizer:scanNow()
    local path = self.ui.document and self.ui.document.file
    if not path then return {error = "no document path"} end
    local book, err = ArchiveBook.new(path)
    if not book then return {error = err} end
    local ok, result = pcall(Scan.scan, book, {
        toc_hints = true,
        include_page_break = true,
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

function HeadingNormalizer:applyCss()
    local document = self.ui.document
    local typeset = self.ui.typeset
    local styletweak = self.ui.styletweak
    if not document or not typeset or not styletweak then return end
    document:setStyleSheet(typeset.css or document.default_css,
        styletweak:getCssText() or "")
end

function HeadingNormalizer:onPreRenderDocument(doc_settings)
    self.ui.doc_settings = doc_settings or self.ui.doc_settings
    local ok, err = pcall(function() self:prepareForRender() end)
    if not ok then
        logger.err("heading-normalizer: " .. tostring(err))
        self.generated_css = nil
    end
end

function HeadingNormalizer:prepareForRender()
    if not self:isEnabled() or self:isBookDisabled() or not self:isEpub() then
        self.generated_css = nil
        return
    end

    local cached = self.ui.doc_settings:readSetting("heading_normalizer")
    if cached and cached.version == VERSION and cached.css ~= nil then
        self.generated_css = cached.css ~= "" and cached.css or nil
        self.report = cached.report
    else
        local result = self:scanNow()
        self.report = report_for_storage(result)
        self.generated_css = result and result.css or nil
        self.ui.doc_settings:saveSetting("heading_normalizer", {
            version = VERSION,
            css = self.generated_css or "",
            report = self.report,
            scanned_at = os.time(),
        })
        logger.info("heading-normalizer: scanned",
            self.ui.document.file,
            self.report and self.report.stats and self.report.stats.pseudo_headings or 0)
    end

    if self.generated_css then
        self:applyCss()
    end
end

function HeadingNormalizer:currentReport()
    if self.report then return self.report end
    local cached = self.ui.doc_settings and self.ui.doc_settings:readSetting("heading_normalizer")
    return cached and cached.report or nil
end

function HeadingNormalizer:formatReport()
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
    for _, candidate in ipairs(report.candidates or {}) do
        lines[#lines + 1] = string.format("L%d  %s  (%d)  %s",
            candidate.level or 0, candidate.selector or "?",
            candidate.score or 0, candidate.text or "")
    end
    for _, warning in ipairs(report.warnings or {}) do
        lines[#lines + 1] = _("Warning: ") .. warning
    end
    return table.concat(lines, "\n")
end

function HeadingNormalizer:currentCss()
    if self.generated_css and self.generated_css ~= "" then return self.generated_css end
    local cached = self.ui.doc_settings and self.ui.doc_settings:readSetting("heading_normalizer")
    if cached and cached.css and cached.css ~= "" then return cached.css end
    return nil
end

function HeadingNormalizer:showReport(title, text)
    if not text or text == "" then
        UIManager:show(InfoMessage:new{text = _("Nothing to show.")})
        return
    end
    UIManager:show(TextViewer:new{
        title = title,
        text = text,
    })
end

function HeadingNormalizer:addToMainMenu(menu_items)
    local function toggleGlobal()
        if G_reader_settings:isTrue("heading_normalizer_enabled") then
            G_reader_settings:delSetting("heading_normalizer_enabled")
        else
            G_reader_settings:saveSetting("heading_normalizer_enabled", true)
        end
        self.generated_css = nil
        UIManager:show(InfoMessage:new{
            text = _("Takes effect the next time a book is opened."),
        })
    end

    local function toggleBook()
        local settings = self.ui.doc_settings
        if settings:isTrue("heading_normalizer_disabled") then
            settings:delSetting("heading_normalizer_disabled")
        else
            settings:saveSetting("heading_normalizer_disabled", true)
        end
        self.generated_css = nil
        UIManager:show(InfoMessage:new{
            text = _("Takes effect the next time this book is opened."),
        })
    end

    menu_items.heading_normalizer = {
        text = _("Heading normaliser"),
        sub_item_table = {
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
                text = _("Status and detected headings"),
                callback = function()
                    self:showReport(_("Heading normaliser"), self:formatReport())
                end,
            },
            {
                text = _("View generated CSS"),
                callback = function()
                    self:showReport(_("Generated heading CSS"), self:currentCss())
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
                        Notification:notify(_("Heading CSS copied to clipboard."))
                    else
                        UIManager:show(InfoMessage:new{text = _("Clipboard not available.")})
                    end
                end,
            },
            {
                text = _("Re-scan this book on next open"),
                callback = function()
                    self.ui.doc_settings:delSetting("heading_normalizer")
                    self.generated_css = nil
                    UIManager:show(InfoMessage:new{
                        text = _("The next opening of this book will scan it again."),
                    })
                end,
            },
        },
    }
end

return HeadingNormalizer
