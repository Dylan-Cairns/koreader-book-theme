local luaunit = require("luaunit")
local Cache = require("hn_cache")

local TestCache = {}

function TestCache:testCurrentCacheIsValid()
    local cached = {version = 2, theme_hash = "74cfd6d8", css = "body {}", report = {}}
    luaunit.assertTrue(Cache.is_valid(cached, 2, "74cfd6d8"))
end

function TestCache:testEmptyCssIsStillValid()
    -- "" means "scanned, nothing to add"; nil means the scan never completed.
    luaunit.assertTrue(Cache.is_valid({version = 2, theme_hash = "abc", css = ""}, 2, "abc"))
end

function TestCache:testNilCssIsInvalid()
    luaunit.assertFalse(Cache.is_valid({version = 2, theme_hash = "abc"}, 2, "abc"))
end

function TestCache:testWrongVersionIsInvalid()
    luaunit.assertFalse(Cache.is_valid({version = 1, theme_hash = "abc", css = ""}, 2, "abc"))
end

function TestCache:testMissingThemeHashIsInvalid()
    luaunit.assertFalse(Cache.is_valid({version = 2, css = ""}, 2, "abc"))
end

function TestCache:testChangedThemeHashIsInvalid()
    luaunit.assertFalse(Cache.is_valid({version = 2, theme_hash = "old", css = ""}, 2, "new"))
end

function TestCache:testNonCacheValuesAreInvalid()
    luaunit.assertFalse(Cache.is_valid(nil, 2, "abc"))
    luaunit.assertFalse(Cache.is_valid("css", 2, "abc"))
    luaunit.assertFalse(Cache.is_valid({}, 2, "abc"))
end

function TestCache:testLegacyVersionOneCacheIsInvalid()
    -- The Heading Normaliser cache had no theme hash and version 1; one lazy
    -- rescan per book is the intended upgrade cost.
    local legacy = {version = 1, css = "p.calibre7 { font-weight: bold }", report = {}}
    luaunit.assertFalse(Cache.is_valid(legacy, 2, "74cfd6d8"))
end

return TestCache
