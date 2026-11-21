-- Shared helpers for the host test suite. Not loaded on the reader.

local Helpers = {}

function Helpers.read_fixture(name)
    local file = assert(io.open("tests/fixtures/" .. name, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

-- A reader with the same small interface as the libarchive wrapper used on
-- the device: list() returns {path, size} entries, read(path) returns bytes.
function Helpers.memory_reader(files)
    local entries = {}
    for path, content in pairs(files) do
        entries[#entries + 1] = {path = path, size = #content}
    end
    table.sort(entries, function(left, right) return left.path < right.path end)
    return {
        entries = entries,
        files = files,
        list = function(self) return self.entries end,
        read = function(self, path) return self.files[path] end,
    }
end

function Helpers.count(haystack, needle)
    local total, start = 0, 1
    while true do
        local found = haystack:find(needle, start, true)
        if not found then return total end
        total = total + 1
        start = found + #needle
    end
end

function Helpers.contains(haystack, needle)
    return haystack:find(needle, 1, true) ~= nil
end

return Helpers
