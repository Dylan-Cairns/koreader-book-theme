# Heading size research

Research note, 2026-11-23. This note changes no code and makes no device change. It exists to answer one question before the next styling round: what sizes should the four heading roles have, relative to body text, in a reading app that is trying to reproduce trade-book typography?

The immediate trigger was owner feedback that the minor heading is still too large and that the chapter number looks bold. Both observations are correct, and the second one has a direct cause in the current CSS.

## Bottom line

Book typography uses two different size regimes, and the current theme applies the wrong one to the in-text levels.

- **Display levels** — part title and chapter title — may be much larger than body text because they open a page and carry the book's visual identity. Current 1.75/1.50 rem is within normal trade-book range and is not the problem.
- **In-text levels** — section and minor — are signposts inside a running chapter. The consistent book-practice answer is a small step, or no size step at all: section heads roughly 1.05–1.20× body, and minor/C-heads at body size or one point smaller, distinguished by weight, case, style and space rather than size.
- **Minor should not be 1.05 rem uppercase.** 1.05 is only 5% larger in ems, but uppercase at the same em has a much larger optical size. In Ysabeau the cap height is 0.658 em against an x-height of 0.414 em, a ratio of 1.59. The minor heading therefore reads as a much bigger element than its nominal 5% suggests. Best practice is 1.00 rem with sentence case bold, or about 0.95 rem if uppercase is kept.
- **The chapter number is bold because it inherits the heading's bold weight.** Its size (1.05 rem against a 1.50 rem chapter title, about 0.70×) is already in the right relationship. It needs `font-weight: normal`, not a smaller size.

A conservative revised ladder, keeping the display levels the owner has already accepted:

| Role | Current | Proposed | Change |
| --- | --- | --- | --- |
| Part | 1.75 rem | 1.75 rem | none |
| Chapter | 1.50 rem | 1.50 rem | none |
| Section | 1.25 rem | 1.15 rem | −0.10 |
| Minor | 1.05 rem uppercase | 1.00 rem sentence case bold, or 0.95 rem if uppercase | −0.05 to −0.10 plus case decision |
| Chapter number | 1.05 rem, inherits bold | 1.05 rem, weight 400 | weight only |

That gives a chapter-to-section ratio of 1.30 and a section-to-body ratio of 1.15, instead of the current 1.20 and 1.25. The hierarchy becomes more top-heavy at the chapter opening and quieter inside the chapter, which is the book convention.

## The two regimes

### Display type: part and chapter openers

Part and chapter titles are display type. They sit on their own page or at the top of a fresh page, often with a lot of white space, and they are allowed to be dramatic. The ranges below are for print, where body text is commonly 10–12 pt:

- Chapter titles: **18–30 pt** (The Book Designer); **20–24 pt**, not much below 16–18 pt (Book Editing Associates); **14–16 pt** in a simpler scheme with 10–12 pt body (InDesignSkills).
- Part titles: **20–36 pt**, larger than the part number; part numbers **12–24 pt** (The Book Designer, Book Editing Associates).
- A modular scale of 1.25 gives 11 pt body → 14 pt H3 → 17 pt H2 → 21 pt H1 → 27 pt title (buk.press). That is a display scale, not a recipe for every subhead inside a chapter.

Against a 10–12 pt body, those chapter ranges are roughly **1.5–3.0× body**, and the part ranges roughly **2.0–3.6× body**. The current 1.50× chapter and 1.75× part are at the quiet end of that range. On a 6-inch e-reader that is defensible: a 51 px chapter title on a 34 px body already fills a good part of the line, and a 59.5 px part title is large without becoming a poster.

Nothing in the research says the part or chapter level must grow. The owner has not complained about them. Leave them alone unless the whole design is being rethought.

### In-text type: section and minor headings

Inside a chapter, the evidence is much more restrained.

- **InDesign Type** (Nigel French): “Subheads may be the same size as the body text but be distinguished by a different font or weight, or they may be a point or two bigger.” At a 10–12 pt body, “a point or two” is roughly **1.08–1.20×**.
- **Wits University Press** house style: body 12 pt; A-head bold caps **12 pt**; B-head bold title case **12 pt**; C-head italics **11 pt**. Two of three subhead levels are exactly body size; the third is one point smaller.
- **Basic Book Design** (Wikibooks): body 11 pt; chapter 14 pt; section 12 pt; subhead 12 pt italic. It also summarises *The Chicago Manual of Style* as recommending the same font for text and subheads, with levels differentiated by all caps, italics or small caps.
- **Butterick's Practical Typography**: “It's fine to make the point size bigger, but just a little. Use the smallest increment necessary to make a visible difference. If your text is set in 12 point, you needn't go up to 14 or 15 point. Try a smaller increase — to 12.5 or 13 point.” Butterick also says the best emphasis is space above and below, and that bold is preferable to italic for headings.
- **Web Style Guide** (Lynch and Horton): “If you want them to be larger, increase their size by one measure. If you prefer bold, leave the heads the same size as your body text and make them bold. You will soon discover that only a small variation is required to establish visual contrast.” The same page warns against setting section heads “large, bold, and all uppercase” at once.

The consensus is not “every level must be visibly larger.” It is that a heading needs **one clear differentiator**, and that size is the coarsest and least necessary one once the reader is already inside a chapter.

This is also why the current 1.25 rem section is not outrageous but is on the high side. At 34 px body, 1.25 rem is 42.5 px, a 25% step; 1.15 rem would be 39.1 px, a 15% step. The latter matches the “point or two” guidance and leaves more room between the section and the 1.50 rem chapter title.

## The minor heading and optical size

The minor role is the lowest in-chapter level. The sources treat it as a C-head or run-in head:

- Wits: C-head **11 pt italics** against 12 pt body.
- Wikibooks: subhead **12 pt Times italic** against 11 pt body; if small caps are used, “make sure the heading font isn't smaller than the text font” because fake small caps shrink capitals and confuse the hierarchy.
- The Book Designer: subheads are “typically set a little larger than the main text,” with hierarchy carried by size, face, indentation, colour and other elements.
- InDesign Type: same size as body, or a point or two bigger.

The current minor is 1.05 rem, uppercase, bold, with 0.05 em tracking. The nominal size is almost body size, but three things make it read larger:

1. **Uppercase has a larger optical size.** Ysabeau's cap height is 0.658 em; its x-height is 0.414 em. A line of caps at 1.05 rem therefore has a cap height of about 23.5 px on the current device, against a body x-height of about 14.1 px. The caps are not literally 1.67× the body's lowercase height in the way a 1.67× font would be, because body text also has ascenders and descenders, but the heading's visual mass is much closer to a 1.3–1.5× heading than to a 1.05× one.
2. **Bold adds weight.** The body is regular; the minor is bold.
3. **Tracking adds width.** 0.05 em spreads the line and makes it occupy more horizontal space.

So the owner's perception is not a contradiction of the 5% number. It is the correct reading of the rendered page.

There are three defensible fixes:

- **Recommended: same size, sentence case, bold.** `1.00 rem`, no tracking, bold. This follows the strongest consensus (same size, differentiate by weight and space), avoids the uppercase inflation, and keeps the heading legible. It is also the least “shouty” option for a heading that may appear several times per chapter.
- **Keep uppercase, reduce size.** `0.95 rem` or even `0.92 rem`, keep 0.04–0.05 em tracking. This keeps the current visual language but accepts that uppercase needs a smaller em to look equal. Wits' 11 pt C-head against 12 pt body is precedent for a C-head slightly below body size.
- **Small caps at body size.** `1.00 rem` with `font-variant: small-caps` if crengine renders it well. This is the traditional book solution and looks less aggressive than full caps. It needs a device check, because faux small caps can look poor and crengine's support is not the same as a browser's.

The first option is the safest default; the second is the conservative change if the owner wants to keep the existing uppercase look.

## Chapter number

The chapter-number evidence is consistent:

- The classic chapter opener is a **small number above a larger title**; the title is the largest element, roughly 18–28 pt, while the number is smaller and often letterspaced or set in small caps (ebookdone).
- Pick **one dominant element**, usually the title or the number; the others should be “simpler, smaller, and complementary” (Kindlepreneur). The chapter title should be the largest text element.
- A common example is “Chapter 5” in 12 pt small caps with an 18 pt title (Masterly Publishing). Part numbers are 12–24 pt against 20–36 pt part titles (The Book Designer, Book Editing Associates).

The current number is 1.05 rem against a 1.50 rem title, which is **0.70×** — squarely in the “smaller, secondary” relationship. The size is not the defect. The defect is that the number rule uses `font-family: inherit` but says nothing about weight, so it inherits the heading's `font-weight: bold`. That makes a small number look like a compressed bold title rather than a quiet numeral.

The fix is one declaration on both number paths:

```css
font-weight: normal;
```

The title stays bold, the number becomes regular, and the existing `font-variant-numeric: lining-nums` stays. No size change is needed.

If the owner wants the number even quieter, 1.00 rem is defensible, but 1.05 rem already produces a 0.70× ratio and going smaller risks looking like a footnote. Keep the size unless the device check says otherwise.

## What the current theme does

The current defaults are set in `hn_theme.lua`:

| Role | Family | Weight | Size | Case | Align |
| --- | --- | --- | --- | --- | --- |
| Body | body face | normal | reader's size (34 px on the Go6) | — | — |
| Part | heading face | bold | 1.75 rem (59.5 px) | none | centre |
| Chapter | heading face | bold | 1.50 rem (51 px) | none | centre |
| Section | heading face | bold | 1.25 rem (42.5 px) | none | left |
| Minor | heading face | bold | 1.05 rem (35.7 px) | upper | left |
| Quote | body face | normal | inherited | italic | — |

The generated marker rule and the standalone number-pair rule also set the number to 1.05 rem, `line-height: 1.15`, and lining figures, but they inherit the heading's bold weight.

The size ladder was built as a display scale and then extended down to the in-text levels. That is the conceptual error the owner identified. The top two levels can use a display scale; the bottom two should use the in-text scale.

## Recommendation

1. **Change the section role to 1.15 rem.** It remains clearly larger than body, but no longer competes with the chapter title.
2. **Change the minor role to 1.00 rem, sentence case, bold, no tracking.** If the owner wants to keep uppercase, use 0.95 rem and keep 0.04–0.05 em tracking.
3. **Add `font-weight: normal` to both chapter-number paths** (the marker inside a real heading, and the standalone number heading paired with its title). Keep 1.05 rem and lining figures.
4. **Leave part and chapter at 1.75/1.50 rem.** They are inside the trade-book display range and the owner has not flagged them.
5. **Do not introduce a modular ratio for every level.** The sources support a display scale for openers, not a single geometric series applied to in-text heads. Butterick explicitly warns against treating a ratio as a substitute for visual judgment.

Expected device result at 34 px body: part 59.5 px, chapter 51 px, section 39.1 px, minor 34 px (or 32.3 px if uppercase), number 35.7 px regular. The chapter opening stays dominant; the section step becomes 15%; the minor heading stops reading as a second section title.

## Open decisions for the owner

- **Minor style:** sentence case bold at 1.00 rem (recommended), or keep uppercase at 0.95 rem, or try small caps at 1.00 rem.
- **Section size:** 1.15 rem (recommended) or 1.20 rem if the 1.15 step reads too subtle on the device.
- **Part/chapter:** keep the current display sizes unless the owner wants a more dramatic opener.

No code or device change has been made from this note. The next implementation round should wait for the owner's choice on the minor style.

## Sources

All URLs accessed 2026-11-23.

- Robert Bringhurst's principles as applied by Butterick, *Practical Typography*, “Headings” — <https://practicaltypography.com/headings.html>. Smallest size increment; space above/below; bold over italic; caution about modular scales.
- Nigel French, *InDesign Type: Professional Typography with Adobe InDesign*, 2nd ed., sample pages — <https://ptgmedia.pearsoncmg.com/images/9780134846712/samplepages/9780134846712_sample.pdf>. “Subheads may be the same size as the body text but be distinguished by a different font or weight, or they may be a point or two bigger.”
- Wits University Press, “Manuscript preparation” — <https://witspress.co.za/page/Manuscript-preparation?sub-collapse-1=>. Body 12 pt; A-head 12 pt bold caps; B-head 12 pt bold title case; C-head 11 pt italics.
- Wikibooks, *Basic Book Design/Font* — <https://en.wikibooks.org/wiki/Basic_Book_Design/Font>. Body 11 pt; chapter 14 pt; section 12 pt; subhead 12 pt italic; Chicago's same-font/same-size subhead advice; small-caps caution.
- Patrick J. Lynch and Sarah Horton, *Web Style Guide*, ch. 9, “Typography” — <https://webstyleguide.com/9-typography.html>. Same-size bold heads or one measure larger; avoid large + bold + all caps; downstyle preferred.
- Book Editing Associates, “Basics of Book Design, Part 1” — <https://book-editing.com/basics-book-design-part-1>. Body 9–13 pt; chapter title 20–24 pt; part title 24–36 pt; subheads 10–14 pt.
- The Book Designer / Andrea Reider, “Book Design Basics: A Primer in Good Book Layout Design” — <https://thebookdesigner.com/book-design-basics>. Body 9–13 pt; chapter 18–30 pt; part title 20–36 pt; part number 12–24 pt; subheads a little larger than body.
- InDesignSkills, “Choosing Font Sizes for Books” — <https://indesignskills.com/tutorials/book-font-size>. Body 10–12 pt; A-heads 14–16 pt; B-heads 12–14 pt.
- buk.press, “Book typography for people who are not typographers” — <https://buk.press/blog/book-typography-basics>. 1.25 modular scale example: 11/14/17/21/27 pt.
- ebookdone, “Chapter Heading Design: How Real Books Open a Chapter” — <https://ebookdone.com/blog/chapter-heading-design>. Small number above larger title; title 18–28 pt; number smaller, often letterspaced or small caps.
- Kindlepreneur, “How to Create Beautiful Chapter Headings for Your Book” — <https://kindlepreneur.com/design-beautiful-chapter-themes>. One dominant element; other elements simpler and smaller; chapter title largest.
- Masterly Publishing, “Book Interior Design” — <https://masterlypublishing.com/book-interior-design-layout-typography-and-readability-that-keep-readers-turning-pages>. 18–20 pt title; number above in a smaller or display style; example 12 pt small-caps number with 18 pt title.
- The Chicago Manual of Style / Turabian guidance on same-size headings, as summarised by Wikibooks above and by the Turabian tip sheet — <https://www.chicagomanualofstyle.org/dam/jcr:134b5b19-bdc9-4d69-b4ad-0aa19fdc3730/Turabian-Tip-Sheet-7.pdf>. The CMOS Online text itself is paywalled; the note relies on the published summary and the Wikibooks quotation rather than claiming a direct read of the current edition.

## Method and limitations

- The ranges are from print book design. An e-reader has a different measure, resolution and user-controlled base size, so the ratios are more useful than the absolute point sizes.
- The device is a 6-inch Go6 at 1072×1448 with KOReader's base size at 34 px. The px figures in this note use that setting.
- Ysabeau metrics were read from the installed static Regular face: unitsPerEm 1000, x-height 414, cap height 658.
- No rendered comparison was made for this note. The next round should build the candidate CSS, capture the demo and a real book, and judge the hierarchy on the device before shipping.
- This note deliberately does not decide the minor style. That is a visual choice between same-size sentence case, smaller uppercase, and small caps, and the owner should see the options before the code changes.
