-- Per-book cache validity. A cached stylesheet is only reusable for the exact
-- cache version and theme it was generated from. The version bump from the old
-- product (version 1, no theme hash) therefore costs each book one lazy rescan,
-- which is intended: the cached CSS no longer matches the current generator.

local Cache = {}

function Cache.is_valid(cached, version, theme_hash)
    if type(cached) ~= "table" then return false end
    if cached.version ~= version then return false end
    -- "" is a valid cached value (the scan found nothing to style); nil is not.
    if type(cached.css) ~= "string" then return false end
    if cached.theme_hash ~= theme_hash then return false end
    return true
end

return Cache
