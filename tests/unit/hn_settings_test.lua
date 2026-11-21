local luaunit = require("luaunit")
local Settings = require("hn_settings")

local TestSettings = {}

-- Minimal stand-in for KOReader's ReadSettings: readSetting(key) returns the
-- stored value or nil.
local function store(values)
    return {
        values = values,
        readSetting = function(self, key) return self.values[key] end,
    }
end

function TestSettings:testNewKeyWins()
    local settings = store{book_theme_enabled = true, heading_normalizer_enabled = false}
    luaunit.assertEquals(Settings.read(settings, "book_theme_enabled", "heading_normalizer_enabled"), true)
end

function TestSettings:testFallsBackToLegacyKey()
    local settings = store{heading_normalizer_enabled = true}
    luaunit.assertTrue(Settings.read_true(settings, "book_theme_enabled", "heading_normalizer_enabled"))
end

function TestSettings:testFalseIsNotOverriddenByLegacy()
    -- An explicit false must not be replaced by an older true value.
    local settings = store{book_theme_enabled = false, heading_normalizer_enabled = true}
    luaunit.assertFalse(Settings.read_true(settings, "book_theme_enabled", "heading_normalizer_enabled"))
end

function TestSettings:testCacheTableFallback()
    local cache = {version = 1, css = "p.calibre7 { font-weight: bold }"}
    local settings = store{heading_normalizer = cache}
    luaunit.assertEquals(Settings.read(settings, "book_theme", "heading_normalizer"), cache)
    settings.values.book_theme = {version = 1, css = ""}
    luaunit.assertEquals(Settings.read(settings, "book_theme", "heading_normalizer").css, "")
end

function TestSettings:testMissingValuesAndSettings()
    luaunit.assertNil(Settings.read(store{}, "book_theme", "heading_normalizer"))
    luaunit.assertNil(Settings.read(nil, "book_theme", "heading_normalizer"))
    luaunit.assertFalse(Settings.read_true(store{}, "book_theme_enabled", "heading_normalizer_enabled"))
end

return TestSettings
