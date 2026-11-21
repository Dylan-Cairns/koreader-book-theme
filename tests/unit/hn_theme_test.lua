local luaunit = require("luaunit")
local Theme = require("hn_theme")

local TestTheme = {}

local function problem_for(problems, needle)
    for _, problem in ipairs(problems) do
        if problem:find(needle, 1, true) then return problem end
    end
    return nil
end

function TestTheme:testDefaultsMatchTheSpec()
    local theme = Theme.defaults()
    luaunit.assertEquals(theme.version, 1)
    luaunit.assertEquals(theme.body.family, "EB Garamond")
    luaunit.assertEquals(theme.body.weight, "normal")
    luaunit.assertEquals(theme.roles.part.family, "Alegreya Sans")
    luaunit.assertEquals(theme.roles.part.weight, "bold")
    luaunit.assertEquals(theme.roles.part.size, "1.45rem")
    luaunit.assertEquals(theme.roles.chapter.size, "1.30rem")
    luaunit.assertEquals(theme.roles.section.size, "1.15rem")
    luaunit.assertEquals(theme.roles.minor.size, "0.95rem")
    luaunit.assertEquals(theme.roles.minor.case, "upper")
    luaunit.assertEquals(theme.roles.minor.spacing, "0.05em")
    luaunit.assertEquals(theme.roles.quote.family, "EB Garamond")
    luaunit.assertEquals(theme.roles.quote.style, "italic")
    luaunit.assertEquals(theme.toc_hints, true)
    luaunit.assertEquals(#Theme.validate(theme), 0)
end

function TestTheme:testDefaultsAreFreshTables()
    local first = Theme.defaults()
    first.roles.chapter.family = "Literata"
    first.body.family = "Literata"
    local second = Theme.defaults()
    luaunit.assertEquals(second.roles.chapter.family, "Alegreya Sans")
    luaunit.assertEquals(second.body.family, "EB Garamond")
end

function TestTheme:testLoadDeepMergesStoredFields()
    local theme, problems = Theme.load({
        body = {family = "Literata"},
        roles = {chapter = {size = "1.20rem"}},
        toc_hints = false,
    })
    luaunit.assertEquals(#problems, 0)
    luaunit.assertEquals(theme.body.family, "Literata")
    luaunit.assertEquals(theme.body.weight, "normal")
    luaunit.assertEquals(theme.roles.chapter.size, "1.20rem")
    luaunit.assertEquals(theme.roles.chapter.family, "Alegreya Sans")
    luaunit.assertEquals(theme.roles.minor.case, "upper")
    luaunit.assertFalse(theme.toc_hints)
end

function TestTheme:testLoadWithoutStoredTheme()
    local theme, problems = Theme.load(nil)
    luaunit.assertEquals(#problems, 0)
    luaunit.assertEquals(theme.body.family, "EB Garamond")
    theme = Theme.load({})
    luaunit.assertEquals(theme.roles.minor.spacing, "0.05em")
end

function TestTheme:testLoadRejectsNonTable()
    local theme, problems = Theme.load("not a theme")
    luaunit.assertEquals(theme.body.family, "EB Garamond")
    luaunit.assertEquals(#problems, 1)
end

function TestTheme:testInvalidFamilyFallsBackWithProblem()
    local theme, problems = Theme.load({roles = {part = {family = 'Bad "Font"; {x}'}}})
    luaunit.assertEquals(theme.roles.part.family, "Alegreya Sans")
    luaunit.assertNotNil(problem_for(problems, "roles.part.family"))
end

function TestTheme:testFamilyLengthIsCapped()
    local theme, problems = Theme.load({body = {family = string.rep("A", 65)}})
    luaunit.assertEquals(theme.body.family, "EB Garamond")
    luaunit.assertNotNil(problem_for(problems, "body.family"))
end

function TestTheme:testInvalidSizeFallsBackWithProblem()
    local theme, problems = Theme.load({roles = {chapter = {size = "2.9rem"}}})
    luaunit.assertEquals(theme.roles.chapter.size, "1.30rem")
    luaunit.assertNotNil(problem_for(problems, "roles.chapter.size"))

    theme, problems = Theme.load({roles = {chapter = {size = "large"}}})
    luaunit.assertEquals(theme.roles.chapter.size, "1.30rem")
    luaunit.assertNotNil(problem_for(problems, "roles.chapter.size"))
end

function TestTheme:testInvalidWeightFallsBackWithProblem()
    local theme, problems = Theme.load({body = {weight = "500"}})
    luaunit.assertEquals(theme.body.weight, "normal")
    luaunit.assertNotNil(problem_for(problems, "body.weight"))

    theme, problems = Theme.load({roles = {minor = {weight = "900"}}})
    luaunit.assertEquals(theme.roles.minor.weight, "bold")
    luaunit.assertNotNil(problem_for(problems, "roles.minor.weight"))
end

function TestTheme:testUnknownRoleAndFieldRejected()
    local theme, problems = Theme.load({
        roles = {epilogue = {family = "Literata"}},
        body = {colour = "red"},
    })
    luaunit.assertEquals(theme.body.family, "EB Garamond")
    luaunit.assertNil(theme.roles.epilogue)
    luaunit.assertNotNil(problem_for(problems, "unknown role 'epilogue'"))
    luaunit.assertNotNil(problem_for(problems, "unknown field 'body.colour'"))
end

function TestTheme:testQuoteRejectsHeadingFields()
    local theme, problems = Theme.load({roles = {quote = {size = "1.1rem"}}})
    luaunit.assertNil(theme.roles.quote.size)
    luaunit.assertNotNil(problem_for(problems, "roles.quote.size"))
end

function TestTheme:testValidateReportsStructuralProblems()
    local theme = Theme.defaults()
    theme.toc_hints = "yes"
    theme.extra = true
    theme.roles.part.family = "Bad;Font"
    local problems = Theme.validate(theme)
    luaunit.assertNotNil(problem_for(problems, "toc_hints"))
    luaunit.assertNotNil(problem_for(problems, "unknown theme field 'extra'"))
    luaunit.assertNotNil(problem_for(problems, "roles.part.family"))
end

function TestTheme:testCanonicalIsSortedAndStable()
    local canonical = Theme.canonical(Theme.defaults())
    luaunit.assertEquals(canonical, Theme.canonical(Theme.defaults()))
    local previous
    for line in canonical:gmatch("[^\n]+") do
        if previous then luaunit.assertTrue(previous <= line, line .. " out of order") end
        previous = line
    end
    luaunit.assertStrContains(canonical, "body.family=EB Garamond;")
    luaunit.assertNotStrContains(canonical, "2026")
end

function TestTheme:testHashIsStable()
    luaunit.assertEquals(Theme.hash(Theme.defaults()), "74cfd6d8")
end

function TestTheme:testHashIsKeyOrderIndependent()
    local first = Theme.load({body = {family = "Literata", weight = "bold"}})
    local second = Theme.load({body = {weight = "bold", family = "Literata"}})
    luaunit.assertEquals(Theme.canonical(first), Theme.canonical(second))
    luaunit.assertEquals(Theme.hash(first), Theme.hash(second))
end

function TestTheme:testHashChangesWithMeaningfulFields()
    local base = Theme.hash(Theme.defaults())
    local theme = Theme.defaults()
    theme.body.family = "Literata"
    luaunit.assertNotEquals(Theme.hash(theme), base)

    theme = Theme.defaults()
    theme.roles.chapter.family = "Literata"
    luaunit.assertNotEquals(Theme.hash(theme), base)

    theme = Theme.defaults()
    theme.roles.minor.case = "none"
    luaunit.assertNotEquals(Theme.hash(theme), base)
end

function TestTheme:testExplicitNormalStyleMatchesAbsentStyle()
    local explicit = Theme.load({roles = {part = {style = "normal"}}})
    luaunit.assertEquals(Theme.hash(explicit), Theme.hash(Theme.defaults()))
end

function TestTheme:testRoleForLevel()
    luaunit.assertEquals(Theme.role_for_level(1), "part")
    luaunit.assertEquals(Theme.role_for_level(2), "chapter")
    luaunit.assertEquals(Theme.role_for_level(3), "section")
    luaunit.assertEquals(Theme.role_for_level(4), "minor")
    luaunit.assertEquals(Theme.role_for_level(5), "minor")
    luaunit.assertEquals(Theme.role_for_level(6), "minor")
    luaunit.assertEquals(Theme.role_for_level(nil), "chapter")
    luaunit.assertEquals(Theme.role_for_level(0), "part")
    luaunit.assertEquals(Theme.role_for_level(9), "minor")
end

function TestTheme:testSetRoleReturnsNewTheme()
    local original = Theme.defaults()
    local changed = Theme.set_role(original, "chapter", "family", "Literata")
    luaunit.assertNotNil(changed)
    luaunit.assertEquals(changed.roles.chapter.family, "Literata")
    luaunit.assertEquals(original.roles.chapter.family, "Alegreya Sans")
    luaunit.assertNotEquals(Theme.hash(changed), Theme.hash(original))
end

function TestTheme:testSetRoleValidates()
    local theme = Theme.defaults()
    local changed, problems = Theme.set_role(theme, "chapter", "size", "3rem")
    luaunit.assertNil(changed)
    luaunit.assertNotNil(problem_for(problems, "roles.chapter.size"))

    changed, problems = Theme.set_role(theme, "chapter", "colour", "red")
    luaunit.assertNil(changed)
    luaunit.assertNotNil(problem_for(problems, "unknown field"))

    changed, problems = Theme.set_role(theme, "body", "family", "Literata")
    luaunit.assertNil(changed)
    luaunit.assertNotNil(problem_for(problems, "unknown role"))
end

function TestTheme:testSetRoleCanClearSpacing()
    local cleared = Theme.set_role(Theme.defaults(), "minor", "spacing", nil)
    luaunit.assertNotNil(cleared)
    luaunit.assertNil(cleared.roles.minor.spacing)
end

return TestTheme
