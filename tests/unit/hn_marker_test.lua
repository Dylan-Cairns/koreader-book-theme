-- A heading that opens with a bare glued number is a real, repeated defect:
-- the publisher separates the number from the title only in its own stylesheet,
-- so with publisher CSS disabled the two run together. These are the positive
-- and negative fixtures for that detection.

local luaunit = require("luaunit")
local Html = require("hn_html")
local Classify = require("hn_classify")

local TestMarker = {}

local function marker(html)
    local doc = Html.parse(html)
    for _, element in ipairs(doc.elements) do
        if Html.is_heading(element.tag) then
            return Classify.heading_marker(element)
        end
    end
    return nil
end

function TestMarker:testGluedChapterNumberIsDetected()
    luaunit.assertEquals(
        marker('<h1><span class="chapter-number">19</span>Philosophy</h1>'),
        "chapter-number")
    luaunit.assertEquals(
        marker('<h2><span class="num">2.</span>The Most Natural State</h2>'),
        "num")
end

function TestMarker:testMarkerAfterAnEmptyAnchorIsStillDetected()
    luaunit.assertEquals(
        marker('<h1><a id="c19"/><span class="chapter-number">19</span>Philosophy</h1>'),
        "chapter-number")
end

function TestMarker:testSpacedNumberNeedsNoRule()
    luaunit.assertNil(
        marker('<h1><span class="chapter-number">19</span> Philosophy</h1>'))
end

function TestMarker:testNumberAfterTitleTextIsNotAnAccessory()
    luaunit.assertNil(
        marker('<h1>Chapter <span class="num">19</span>Philosophy</h1>'))
end

function TestMarker:testHiddenPageNumberIsNotAChapterNumber()
    luaunit.assertNil(
        marker('<h4><span class="pagebreak-rw">281</span>Notes</h4>'))
    luaunit.assertNil(
        marker('<h2><span class="page-number">12</span>Chapter</h2>'))
end

function TestMarker:testFootnoteAndBulletMarkersAreRejected()
    luaunit.assertNil(
        marker('<h2><span class="refnote-marker-container">1</span>Title</h2>'))
    luaunit.assertNil(
        marker('<h2><span class="bullet-marker">1.</span>Title</h2>'))
    luaunit.assertNil(
        marker('<h2><span class="toc-number">4</span>Title</h2>'))
end

function TestMarker:testOnlyHeadingsAreConsidered()
    luaunit.assertNil(
        marker('<p><span class="chapter-number">19</span>Philosophy</p>'))
end

function TestMarker:testDropCapIsNotANumber()
    luaunit.assertNil(
        marker('<h1><span class="dropcap">T</span>he Beginning</h1>'))
end

function TestMarker:testLongerNumbersAndBareNumbersAreRejected()
    luaunit.assertNil(
        marker('<h1><span class="year">2024</span>Annual Report</h1>'))
    -- No title after the number: there is nothing to separate.
    luaunit.assertNil(
        marker('<h1><span class="chapter-number">19</span></h1>'))
end

function TestMarker:testUnselectableMarkerIsSkipped()
    luaunit.assertNil(marker('<h1><span>19</span>Philosophy</h1>'))
end

-- A number set as its own heading, with the title as the next heading, is one
-- title block. Both selectors come back so the generator can tighten the gap
-- between them without losing the space below the title.

local function number_pair(html)
    local doc = Html.parse(html)
    for index, element in ipairs(doc.elements) do
        if Html.is_heading(element.tag) then
            local following
            for later = index + 1, #doc.elements do
                local candidate = doc.elements[later]
                if Html.is_block(candidate.tag)
                    and candidate.tag ~= "body" and candidate.tag ~= "html" then
                    following = candidate
                    break
                end
            end
            return Classify.heading_number(element, following)
        end
    end
    return nil
end

function TestMarker:testStandaloneNumberHeadingIsPairedWithTheTitle()
    local number, title = number_pair(
        '<h2 class="ch_title1"><a id="p1"/><a href="toc">8</a></h2>' ..
        '<h2 class="ch_title2"><a href="toc">Secularism and the Ethic</a></h2>')
    luaunit.assertEquals(number, "h2.ch_title1")
    luaunit.assertEquals(title, "h2.ch_title2")
end

function TestMarker:testNumberHeadingWithoutAFollowingHeadingIsIgnored()
    luaunit.assertNil(number_pair('<h2 class="ch_title1">8</h2><p>Body text.</p>'))
    luaunit.assertNil(number_pair('<h2 class="ch_title1">8</h2>'))
end

function TestMarker:testNumberHeadingNeedsSelectorsForBothHeadings()
    -- Without a class or id there is no safe selector: the bare tag would
    -- restyle every heading of that level.
    luaunit.assertNil(number_pair('<h2>8</h2><h2>Title</h2>'))
end

function TestMarker:testTwoNumberHeadingsAreNotATitlePair()
    luaunit.assertNil(number_pair('<h2 class="a">8</h2><h2 class="b">9</h2>'))
end

function TestMarker:testPageNumberHeadingIsNotAChapterNumber()
    luaunit.assertNil(number_pair(
        '<h2 class="pagebreak-rw">281</h2><h2 class="ch_title">Notes</h2>'))
end

return TestMarker
