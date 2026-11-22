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
    luaunit.assertEquals(theme.roles.part.size, "1.75rem")
    luaunit.assertEquals(theme.roles.chapter.size, "1.50rem")
    luaunit.assertEquals(theme.roles.section.size, "1.25rem")
    luaunit.assertEquals(theme.roles.minor.size, "1.00rem")
    luaunit.assertEquals(theme.roles.minor.case, "upper")
    luaunit.assertEquals(theme.roles.minor.spacing, "0.05em")
    -- Every heading level is centred; the sizes must stay a visible ladder.
    for _, role in ipairs({"part", "chapter", "section", "minor"}) do
        luaunit.assertEquals(theme.roles[role].align, "center", role)
    end
    luaunit.assertEquals(theme.roles.quote.family, "EB Garamond")
    luaunit.assertEquals(theme.roles.quote.style, "italic")
    luaunit.assertEquals(theme.toc_hints, true)
    luaunit.assertEquals(#Theme.validate(theme), 0)
end

function TestTheme:testDefaultFontsAreTheTwoChoices()
    luaunit.assertEquals(Theme.DEFAULT_FONTS.body, "EB Garamond")
    luaunit.assertEquals(Theme.DEFAULT_FONTS.heading, "Alegreya Sans")
    local fonts = Theme.fonts(Theme.defaults())
    luaunit.assertEquals(fonts.body, "EB Garamond")
    luaunit.assertEquals(fonts.heading, "Alegreya Sans")
end

function TestTheme:testDefaultsAreFreshTables()
    local first = Theme.defaults()
    first.roles.chapter.family = "Literata"
    first.body.family = "Literata"
    local second = Theme.defaults()
    luaunit.assertEquals(second.roles.chapter.family, "Alegreya Sans")
    luaunit.assertEquals(second.body.family, "EB Garamond")
end

function TestTheme:testFromFontsChangesWholeRoles()
    local theme, problems = Theme.from_fonts({body = "Literata", heading = "FreeSans"})
    luaunit.assertEquals(#problems, 0)
    luaunit.assertEquals(theme.body.family, "Literata")
    -- Quotes read in the body face.
    luaunit.assertEquals(theme.roles.quote.family, "Literata")
    -- One heading choice reaches every heading level, not just one.
    for _, role in ipairs({"part", "chapter", "section", "minor"}) do
        luaunit.assertEquals(theme.roles[role].family, "FreeSans", role)
    end
    -- Sizes and weights stay on their defaults.
    luaunit.assertEquals(theme.roles.chapter.size, "1.50rem")
    luaunit.assertEquals(theme.roles.chapter.weight, "bold")
    luaunit.assertEquals(theme.roles.minor.case, "upper")
    luaunit.assertEquals(#Theme.validate(theme), 0)
end

function TestTheme:testFromFontsKeepsDefaultsForMissingFamilies()
    local theme = Theme.from_fonts({body = "Literata"})
    luaunit.assertEquals(theme.body.family, "Literata")
    luaunit.assertEquals(theme.roles.chapter.family, "Alegreya Sans")
    luaunit.assertEquals(theme.roles.quote.family, "Literata")
end

function TestTheme:testFromFontsRejectsInvalidFamily()
    local theme, problems = Theme.from_fonts({body = 'Bad "Font"; {x}'})
    luaunit.assertEquals(theme.body.family, "EB Garamond")
    luaunit.assertNotNil(problem_for(problems, "body font"))

    theme, problems = Theme.from_fonts({heading = string.rep("A", 65)})
    luaunit.assertEquals(theme.roles.chapter.family, "Alegreya Sans")
    luaunit.assertNotNil(problem_for(problems, "heading font"))
end

function TestTheme:testSettingsStoresOnlyTheTwoFonts()
    local theme = Theme.from_fonts({body = "Literata", heading = "FreeSans"})
    local settings = Theme.settings(theme)
    luaunit.assertEquals(settings.body_font, "Literata")
    luaunit.assertEquals(settings.heading_font, "FreeSans")
    luaunit.assertEquals(settings.body, nil)
    luaunit.assertEquals(settings.roles, nil)
end

function TestTheme:testLoadFontShapeRoundTrips()
    local theme, problems = Theme.load({body_font = "Literata", heading_font = "FreeSans"})
    luaunit.assertEquals(#problems, 0)
    luaunit.assertEquals(theme.body.family, "Literata")
    luaunit.assertEquals(theme.roles.chapter.family, "FreeSans")
    local settings = Theme.settings(theme)
    luaunit.assertEquals(settings.body_font, "Literata")
    luaunit.assertEquals(settings.heading_font, "FreeSans")
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

function TestTheme:testLoadRejectsUnknownSettingsField()
    local theme, problems = Theme.load({body_font = "Literata", weights = {bold = true}})
    luaunit.assertEquals(theme.body.family, "Literata")
    luaunit.assertNotNil(problem_for(problems, "unknown theme field 'weights'"))
end

function TestTheme:testLoadInvalidFontFallsBack()
    local theme, problems = Theme.load({heading_font = "Bad;Font"})
    luaunit.assertEquals(theme.roles.chapter.family, "Alegreya Sans")
    luaunit.assertNotNil(problem_for(problems, "heading font"))
end

function TestTheme:testLoadMigratesLegacyRoleTable()
    -- Builds before the simplification stored a resolved role table.
    local theme, problems = Theme.load({
        body = {family = "Literata", weight = "bold"},
        roles = {
            part = {family = "Alegreya Sans"},
            chapter = {family = "Alegreya Sans"},
            section = {family = "FreeSans", size = "1.20rem"},
            minor = {family = "Alegreya Sans", case = "upper"},
            quote = {family = "Literata", style = "italic"},
        },
    })
    luaunit.assertEquals(#problems, 0)
    luaunit.assertEquals(theme.body.family, "Literata")
    -- The one genuinely customised heading face is kept.
    luaunit.assertEquals(theme.roles.chapter.family, "FreeSans")
    luaunit.assertEquals(theme.roles.section.family, "FreeSans")
    luaunit.assertEquals(theme.roles.quote.family, "Literata")
    -- Derived values do not migrate; they come from the defaults.
    luaunit.assertEquals(theme.roles.section.size, "1.25rem")
    luaunit.assertEquals(theme.roles.minor.case, "upper")
end

function TestTheme:testLoadLegacyDefaultsProduceTheDefaultSettings()
    local theme, problems = Theme.load({
        body = {family = "EB Garamond", weight = "normal"},
        roles = {chapter = {family = "Alegreya Sans"}, section = {family = "Alegreya Sans"}},
    })
    luaunit.assertEquals(#problems, 0)
    luaunit.assertEquals(Theme.hash(theme), Theme.hash(Theme.defaults()))
end

function TestTheme:testLoadLegacyInvalidFamilyFallsBack()
    local theme, problems = Theme.load({roles = {chapter = {family = 'Bad "Font"'}}})
    luaunit.assertEquals(theme.roles.chapter.family, "Alegreya Sans")
    luaunit.assertNotNil(problem_for(problems, "roles.chapter.family"))
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
    -- 23cb147d is the default theme after every heading level became centred
    -- and the size ladder widened (2026-11-22). The previous defaults were
    -- 655593d8 (part/chapter centred) and 74cfd6d8 (all left).
    luaunit.assertEquals(Theme.hash(Theme.defaults()), "23cb147d")
end

function TestTheme:testHashIsKeyOrderIndependent()
    local first = Theme.load({body_font = "Literata", heading_font = "FreeSans"})
    local second = Theme.load({heading_font = "FreeSans", body_font = "Literata"})
    luaunit.assertEquals(Theme.canonical(first), Theme.canonical(second))
    luaunit.assertEquals(Theme.hash(first), Theme.hash(second))
end

function TestTheme:testHashChangesWithEitherFont()
    local base = Theme.hash(Theme.defaults())
    luaunit.assertNotEquals(Theme.hash(Theme.from_fonts({body = "Literata"})), base)
    luaunit.assertNotEquals(Theme.hash(Theme.from_fonts({heading = "Literata"})), base)
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

function TestTheme:testFontsToleratesMissingShape()
    local fonts = Theme.fonts(nil)
    luaunit.assertEquals(fonts.body, "EB Garamond")
    luaunit.assertEquals(fonts.heading, "Alegreya Sans")
    fonts = Theme.fonts({body = {family = "Literata"}})
    luaunit.assertEquals(fonts.body, "Literata")
    luaunit.assertEquals(fonts.heading, nil)
end

return TestTheme
