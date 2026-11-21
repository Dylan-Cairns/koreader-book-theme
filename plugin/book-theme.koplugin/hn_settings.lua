-- Settings-key migration helper. The product was renamed from Heading
-- Normaliser to Book Theme, so new code reads book_theme* keys first and falls
-- back to the old heading_normalizer* keys. Writes always use the new key; the
-- legacy values are never deleted here, so an older build still finds its own
-- state. Pure Lua: the caller passes any object with a readSetting(key) method.

local Settings = {}

-- Returns a non-nil value from `key`, otherwise the value of `legacy_key`.
function Settings.read(settings, key, legacy_key)
    if not settings then return nil end
    local value = settings:readSetting(key)
    if value == nil and legacy_key then
        value = settings:readSetting(legacy_key)
    end
    return value
end

-- Boolean form, matching KOReader's ReadSettings:isTrue semantics.
function Settings.read_true(settings, key, legacy_key)
    return Settings.read(settings, key, legacy_key) == true
end

return Settings
