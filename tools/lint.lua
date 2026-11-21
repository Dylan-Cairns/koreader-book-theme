package.path = "local/toolchain/luacheck/src/?.lua;local/toolchain/luacheck/src/?/init.lua;" .. package.path
local luacheck = require("luacheck")
local options = {}
setfenv(assert(loadfile(".luacheckrc")), options)()
local sources, names = {}, {}
for _, name in ipairs(arg) do
    local file = assert(io.open(name, "rb"))
    sources[#sources + 1] = file:read("*a")
    file:close()
    names[#names + 1] = name
end
local report = luacheck.check_strings(sources, options)
for index, issues in ipairs(report) do
    for _, issue in ipairs(issues) do
        io.stderr:write(string.format("%s:%d:%d: [%s] %s\n", names[index],
            issue.line or 0, issue.column or 0, issue.code, luacheck.get_message(issue)))
    end
end
print(string.format("Luacheck: %d files, %d warnings, %d errors", #names, report.warnings, report.errors))
os.exit((report.warnings + report.errors + report.fatals == 0) and 0 or 1)
