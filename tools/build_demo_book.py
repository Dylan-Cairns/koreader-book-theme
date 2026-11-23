#!/usr/bin/env python3
"""Build the Book Theme demo EPUB.

Every page exercises one styling path of the plugin:

* real h1-h6 tag rules and the heading-size ladder
* a part title and a chapter/section title found through the NCX
* a chapter number and title set as two headings (the pair rule)
* a chapter number glued to its title inside a real h1 (the marker rule)
* layout-only headings at three levels, with no contents entry
* headings declared with epub:type
* quotes, epigraphs and verse, plus a plain blockquote
* sup/sub, lists, code and inline formatting

The output is generated, never edited by hand:

    py -3.15 -B tools/build_demo_book.py

writes ``local/demo/book-theme-demo.epub`` and an extracted copy under
``local/demo/src`` for inspection. The archive is deterministic: fixed
timestamps and a sorted file order, so rebuilding produces identical bytes.
"""

from __future__ import annotations

import pathlib
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_OUT = ROOT / "local" / "demo" / "book-theme-demo.epub"
DEFAULT_SRC = ROOT / "local" / "demo" / "src"

UID = "urn:uuid:5d0f5b62-6a52-4c2e-9d8f-2f6a1f2c9b31"
STAMP = (2026, 11, 23, 0, 0, 0)

XHTML = """<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en">
<head>
  <title>{title}</title>
  <link rel="stylesheet" type="text/css" href="../styles/demo.css"/>
</head>
<body>
{body}
</body>
</html>
"""

CSS = """/* Layout signals for the scanner. The plugin's generated rules win. */
body {
    font-family: serif;
    line-height: 1.5;
    margin: 5%;
}
p {
    margin: 0;
    text-indent: 1.2em;
    text-align: justify;
}
p.first, p.subtitle, p.note, p.plain {
    text-indent: 0;
}
p.subtitle {
    font-style: italic;
    text-align: center;
}
div.top {
    /* A publisher pull-up that would eat the title's bottom margin. */
    margin-top: -1em;
}
.part-title {
    font-size: 2em;
    font-weight: bold;
    text-align: center;
    page-break-before: always;
    margin: 2em 0 1em 0;
}
.chapter-title {
    font-size: 1.6em;
    font-weight: bold;
    text-align: center;
    page-break-before: always;
    margin: 2em 0 1em 0;
}
.section-title {
    font-size: 1.25em;
    font-weight: bold;
    text-align: center;
    margin: 1.5em 0 0.5em 0;
}
h1, h2, h3, h4, h5, h6 {
    page-break-after: avoid;
}
.layout-big {
    font-size: 1.5em;
    font-weight: bold;
    text-align: center;
    page-break-before: always;
    margin: 1.5em 0 0.6em 0;
}
.layout-mid {
    font-size: 1.25em;
    font-weight: bold;
    text-align: center;
    page-break-before: always;
    margin: 1.5em 0 0.6em 0;
}
.layout-minor {
    font-size: 1em;
    font-weight: bold;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    text-align: center;
    page-break-before: always;
    margin: 1.5em 0 0.6em 0;
}
.epigraph, .verse {
    font-style: italic;
    margin: 1em 2em;
}
.epi-inline {
    margin: 1em 2em 0 2em;
}
blockquote {
    margin: 1em 2em;
    font-style: italic;
}
ul {
    margin: 1em 1.5em;
}
pre {
    margin: 1em 0;
    padding: 0.5em;
    border: 1px solid #999;
}
"""

TITLEPAGE = """
<h1>Book Theme Demo</h1>
<p class="subtitle">Every element the plugin styles, in one book</p>
<p class="note">While reading, open <b>Tools → Book Theme</b> and change
<b>Body font</b> or <b>Heading font</b>. These pages restyle immediately,
without closing the book.</p>
<p class="note">The pages up to <b>A Glued Chapter Number</b> are listed in the
contents. The rest show how the plugin finds headings with no contents entry at
all; page to them.</p>
"""

REAL_HEADINGS = """
<h1>Part Heading (h1)</h1>
<p class="first">A real h1 is always styled as a part title: the largest step
of the ladder, centred, in the heading face.</p>

<h2>Chapter Heading (h2)</h2>
<p>The h2 step is one size down and still unmistakably a chapter.</p>

<h3>Section Heading (h3)</h3>
<p>The h3 step sits inside prose and stays tight to the text below it.</p>

<h4>Minor Heading (h4)</h4>
<p>Minor headings are body size, bold and sentence case, so weight and space
separate them from a bold paragraph without making them another section.</p>

<h5>Minor Heading (h5)</h5>
<p>h5 and h6 share the minor role with h4.</p>

<h6>Minor Heading (h6)</h6>
<p>Part and chapter titles are centred; section and minor headings align
left, so they cannot be confused with body text.</p>
"""

PART = """
<p class="part-title" id="part1">Part One: Found Through the Contents</p>
<p class="first">This line is a plain paragraph. The contents page points at
it, so it becomes a part title even though the markup carries no h1.</p>
<p>Body text follows in the body face. The indentation and justification come
from the publisher's stylesheet; the plugin owns only the type.</p>
"""

CHAPTER = """
<p class="chapter-title" id="ch1">Chapter One: A Chapter Title in Plain Text</p>
<p class="section-title" id="sec1">A Section Under That Chapter</p>
<p class="first">Both of these lines are paragraphs. The contents page gives
the first one chapter level and the nested entry section level, so the size
difference is the theme's, not the publisher's.</p>
<p>An ordinary paragraph follows the section head. Compare its size with the
section title above: 1 rem against 1.15 rem.</p>
"""

PAIR = """
<h2 class="ch_num" id="ch8">8</h2>
<h2 class="ch_name">A Number and a Title as Two Headings</h2>
<div class="top"><p class="epigraph">An epigraph the publisher pulls up under
the title with a negative margin.</p></div>
<p class="first">The number sits close above the title, and the epigraph keeps
a clear gap below it. Both margins belong to the theme.</p>
<p>The two headings are one title block, not two sections.</p>
"""

GLUED = """
<h1 id="glued"><span class="chapter-number">19</span>A Chapter Number Glued to Its Title</h1>
<p class="first">The publisher separates the number from the title only in its
own stylesheet. With that stylesheet off the two would touch; the plugin moves
the number onto its own line above the title, in the heading's own face and
smaller than the title.</p>
<p>This page checks that the number is subordinate to the title without the
publisher's CSS.</p>
"""

LAYOUT = """
<p class="layout-big" id="layout-big">A Large Heading Found by Layout</p>
<p class="first">No contents entry, no epub:type. This page's stylesheet alone
makes these three lines heading-shaped.</p>

<p class="layout-mid" id="layout-mid">A Mid-Sized Heading Found by Layout</p>
<p>Bold, centred and larger than body text in the source: the plugin reads that
combination as a section heading and applies its own alignment.</p>

<p class="layout-minor" id="layout-minor">A Minor Heading Found by Layout</p>
<p>Uppercase, bold and centred in the source, but only just above body size:
the plugin reads it as a minor heading, the same role as h4-h6.</p>
"""

SEMANTIC_CHAPTER = """
<p class="sem-chapter" epub:type="chapter">A Chapter Declared in the Markup</p>
<p class="first">This paragraph carries no heading markup and no heading-like
styling. Only the <code>epub:type</code> attribute says what it is.</p>
"""

SEMANTIC_SECTION = """
<p class="sem-section" epub:type="section">A Section Declared in the Markup</p>
<p class="first">A section declaration maps to the section level, with no
contents entry to help.</p>
"""

SEMANTIC_SUBTITLE = """
<p class="sem-subtitle" epub:type="subtitle">A Subtitle Declared in the Markup</p>
<p class="first">A subtitle declaration maps to the section level too.</p>
"""

QUOTES = """
<blockquote><p>A plain blockquote is always italic, in the body face, with no
detection involved.</p></blockquote>

<div class="epigraph">
  <p>An epigraph held in a div with a telling class name.</p>
  <p>The whole block is treated as one quote.</p>
</div>

<div class="verse">
  <p>A verse line,</p>
  <p>another verse line,</p>
  <p>and a third.</p>
</div>

<p class="epi-inline" epub:type="epigraph">A one-line epigraph declared with
epub:type.</p>

<p class="first">Quote rules only change family, weight and style. Size stays
KOReader's, so a quote is never mistaken for a heading.</p>
"""

INLINE = """
<h3>A Real Section Head With <em>an Inner Run</em></h3>
<p class="first">A footnote marker<sup>1</sup> and a chemical formula
H<sub>2</sub>O. Both keep their raised or lowered position when the publisher
stylesheet is off.</p>
<ul>
  <li>List items inherit the body face.</li>
  <li>Inline code such as <code>Book Theme</code> stays monospace.</li>
</ul>
<pre>local theme = { body_font = "EB Garamond" }
print(theme.body_font)</pre>
<p class="plain">Inline <strong>bold</strong>, <em>italic</em>, and a
<a href="text-01-real-headings.xhtml">link to the first page</a>.</p>
"""

DOCUMENTS = [
    ("text/titlepage.xhtml", "Title Page", TITLEPAGE),
    ("text/text-01-real-headings.xhtml", "Real Headings", REAL_HEADINGS),
    ("text/text-02-part.xhtml", "Part Found Through the Contents", PART),
    ("text/text-03-chapter.xhtml", "Chapter and Section in Plain Text", CHAPTER),
    ("text/text-04-pair.xhtml", "Number and Title as Two Headings", PAIR),
    ("text/text-05-glued.xhtml", "A Glued Chapter Number", GLUED),
    ("text/text-06-layout.xhtml", "Headings Found by Layout", LAYOUT),
    ("text/text-07-semantic-chapter.xhtml", "Chapter Declared in the Markup", SEMANTIC_CHAPTER),
    ("text/text-08-semantic-section.xhtml", "Section Declared in the Markup", SEMANTIC_SECTION),
    ("text/text-09-semantic-subtitle.xhtml", "Subtitle Declared in the Markup", SEMANTIC_SUBTITLE),
    ("text/text-10-quotes.xhtml", "Quotes, Epigraphs and Verse", QUOTES),
    ("text/text-11-inline.xhtml", "Inline Details", INLINE),
]

NAV_ENTRIES = """
      <li><a href="text/text-01-real-headings.xhtml">Real Headings</a></li>
      <li><a href="text/text-02-part.xhtml#part1">Part One: Found Through the Contents</a></li>
      <li><a href="text/text-03-chapter.xhtml#ch1">Chapter One: A Chapter Title in Plain Text</a>
        <ol>
          <li><a href="text/text-03-chapter.xhtml#sec1">A Section Under That Chapter</a></li>
        </ol>
      </li>
      <li><a href="text/text-04-pair.xhtml">Chapter Number and Title as Two Headings</a></li>
      <li><a href="text/text-05-glued.xhtml#glued">A Glued Chapter Number</a></li>
"""

NCX_POINTS = """
    <navPoint id="nav-1"><navLabel><text>Real Headings</text></navLabel>
      <content src="text/text-01-real-headings.xhtml"/></navPoint>
    <navPoint id="nav-2"><navLabel><text>Part One: Found Through the Contents</text></navLabel>
      <content src="text/text-02-part.xhtml#part1"/></navPoint>
    <navPoint id="nav-3"><navLabel><text>Chapter One: A Chapter Title in Plain Text</text></navLabel>
      <content src="text/text-03-chapter.xhtml#ch1"/>
      <navPoint id="nav-3-1"><navLabel><text>A Section Under That Chapter</text></navLabel>
        <content src="text/text-03-chapter.xhtml#sec1"/></navPoint>
    </navPoint>
    <navPoint id="nav-4"><navLabel><text>Chapter Number and Title as Two Headings</text></navLabel>
      <content src="text/text-04-pair.xhtml"/></navPoint>
    <navPoint id="nav-5"><navLabel><text>A Glued Chapter Number</text></navLabel>
      <content src="text/text-05-glued.xhtml#glued"/></navPoint>
"""


def build_files() -> dict[str, bytes]:
    files: dict[str, bytes] = {}

    files["META-INF/container.xml"] = b"""<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""

    manifest = [
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
        '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
        '<item id="css" href="styles/demo.css" media-type="text/css"/>',
    ]
    spine = []
    for index, (path, title, body) in enumerate(DOCUMENTS, start=1):
        item_id = f"doc{index:02d}"
        manifest.append(
            f'<item id="{item_id}" href="{path}" media-type="application/xhtml+xml"/>'
        )
        spine.append(f'<itemref idref="{item_id}"/>')
        document = XHTML.format(title=title, body=body.strip())
        files[f"OEBPS/{path}"] = document.encode("utf-8")

    files["OEBPS/styles/demo.css"] = CSS.encode("utf-8")

    files["OEBPS/nav.xhtml"] = (
        """<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en">
<head><title>Contents</title></head>
<body>
  <nav epub:type="toc" id="toc">
    <h1>Contents</h1>
    <ol>"""
        + NAV_ENTRIES
        + """    </ol>
  </nav>
</body>
</html>
"""
    ).encode("utf-8")

    files["OEBPS/toc.ncx"] = (
        f"""<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="{UID}"/>
    <meta name="dtb:depth" content="2"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle><text>Book Theme Demo</text></docTitle>
  <navMap>"""
        + NCX_POINTS
        + """  </navMap>
</ncx>
"""
    ).encode("utf-8")

    files["OEBPS/content.opf"] = (
        f"""<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">{UID}</dc:identifier>
    <dc:title>Book Theme Demo</dc:title>
    <dc:language>en</dc:language>
    <dc:creator>Book Theme</dc:creator>
    <meta property="dcterms:modified">2026-11-23T00:00:00Z</meta>
  </metadata>
  <manifest>
    {chr(10).join("    " + item for item in manifest).strip()}
  </manifest>
  <spine toc="ncx">
    {chr(10).join("    " + item for item in spine).strip()}
  </spine>
  <guide>
    <reference type="title-page" title="Title Page" href="text/titlepage.xhtml"/>
  </guide>
</package>
"""
    ).encode("utf-8")

    files["mimetype"] = b"application/epub+zip"
    return files


def write_epub(files: dict[str, bytes], out: pathlib.Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out, "w") as archive:
        info = zipfile.ZipInfo("mimetype", date_time=STAMP)
        info.compress_type = zipfile.ZIP_STORED
        archive.writestr(info, files["mimetype"])
        for name in sorted(files):
            if name == "mimetype":
                continue
            info = zipfile.ZipInfo(name, date_time=STAMP)
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, files[name])


def write_source_tree(files: dict[str, bytes], out: pathlib.Path) -> None:
    for name, data in files.items():
        if name == "mimetype":
            continue
        target = out / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)


def main(argv: list[str]) -> int:
    out = pathlib.Path(argv[1]) if len(argv) > 1 else DEFAULT_OUT
    src = pathlib.Path(argv[2]) if len(argv) > 2 else DEFAULT_SRC
    files = build_files()
    write_epub(files, out)
    write_source_tree(files, src)
    listing = "\n".join(sorted(files))
    (src / "files.txt").write_text(listing + "\n", encoding="utf-8")
    print(f"wrote {out}")
    print(f"source tree {src}")
    print(f"{len(files)} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
