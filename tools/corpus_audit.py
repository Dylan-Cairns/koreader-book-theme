#!/usr/bin/env python3
"""Structural audit of an EPUB corpus for the Book Theme KOReader plugin.

Reads every ``.epub`` under a corpus directory (read-only), extracts only the
text assets into a disposable temporary tree, and records structure, generator
fingerprints, navigation quality, real headings, pseudo-heading candidates and
decoy patterns.

No book text is written to this repository. The JSON reports document lengths,
counts and tag/class patterns only; books are identified by a short hash of
their path relative to the corpus. Output is deterministic: sorted keys, no
timestamps, no absolute paths.

Usage:
    python -B tools/corpus_audit.py [--corpus DIR] [--out DIR]
                                    [--temp DIR] [--no-extract] [--limit N]
                                    [--classifier FILE] [--verdicts FILE]

The corpus defaults to ``../meaning-and-meditation`` next to the repository,
or ``$BOOK_THEME_CORPUS`` when set. The temporary extraction root defaults to
``$BOOK_THEME_CORPUS_TEMP`` or ``<system temp>/koreader-corpus-audit``; it is
deleted and rebuilt on every run and never lives inside the repository.

``classifier.json`` (from ``tools/corpus_classify.lua``) and ``verdicts.tsv``
(reviewed TP/FP/PARTIAL rows) are merged when present, adding the precision and
ToC-recall estimate to ``aggregate.json``.
"""

import argparse
import hashlib
import json
import os
import posixpath
import re
import shutil
import statistics
import sys
import tempfile
import urllib.parse
import zipfile

SCHEMA = 1
TEXT_EXTENSIONS = {".xhtml", ".html", ".htm", ".opf", ".ncx", ".xml", ".css"}
HEADING_TAGS = ("h1", "h2", "h3", "h4", "h5", "h6")
BLOCK_TAGS = {
    "address", "article", "aside", "blockquote", "body", "caption", "dd",
    "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form",
    "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "li", "main", "nav",
    "ol", "p", "pre", "section", "table", "tbody", "td", "tfoot", "th",
    "thead", "title", "tr", "ul",
}
VOID_TAGS = {
    "area", "base", "br", "col", "embed", "hr", "img", "input", "link",
    "meta", "param", "source", "track", "wbr",
}
FORBIDDEN_ANCESTORS = {"nav", "table", "figure", "aside", "form", "head"}
NEGATIVE_TOKENS = (
    "toc", "nav", "footnote", "note", "caption", "byline", "author",
    "copyright", "dedication", "epigraph", "poem", "verse", "dropcap",
    "image", "figure", "table", "header",
)
NAME_TOKENS = (
    "chapter", "chap", "part", "book", "volume", "section", "heading",
    "title", "subtitle", "subhead",
)
FRONT_MATTER_TITLES = {
    "cover", "title page", "copyright", "contents", "table of contents",
    "toc", "half title", "halftitle",
}
DECOY_TOKENS = {
    "drop_cap": ("dropcap", "drop-cap", "drop_cap", "initial", "lettrine",
                 "firstletter", "first-letter", "first_letter"),
    "epigraph": ("epigraph", "pullquote", "pull-quote", "blurb", "quotation",
                 "quote"),
    "poetry": ("poem", "poetry", "verse", "stanza", "haiku"),
    "footnote": ("footnote", "endnote", "noteref", "fnref", "sidenote",
                 "superscript", "note"),
    "bibliography": ("bibitem", "bibentry", "bibliography", "workscited",
                     "works-cited", "reference"),
    "caption": ("caption", "figcaption", "credit", "legend"),
    "byline": ("byline", "contributor", "translator", "author"),
    "index": ("index", "idx"),
    "toc": ("toc", "nav"),
}
TEXT_LENGTH_BUCKETS = (("1-20", 1, 20), ("21-40", 21, 40), ("41-80", 41, 80),
                       ("81-140", 81, 140), ("141-400", 141, 400),
                       ("401+", 401, 10 ** 9))

TAG_RE = re.compile(r"<([A-Za-z_][\w:.-]*)((?:\"[^\"]*\"|'[^']*'|[^>\"'])*)>")
ATTR_RE = re.compile(
    r"([A-Za-z_:][\w:.-]*)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))")
CSS_RULE_RE = re.compile(r"([^{}]+)\{([^{}]*)\}")
DIGITS_RE = re.compile(r"\d+")
WHITESPACE_RE = re.compile(r"\s+")
CSS_PROPERTIES = ("font-size", "font-weight", "text-align", "text-transform",
                  "page-break-before", "break-before", "margin-top",
                  "text-indent", "font-style", "display")


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

def path_id(rel_path):
    return hashlib.sha1(rel_path.replace("\\", "/").encode("utf-8")).hexdigest()[:8]


def content_sha1(path):
    digest = hashlib.sha1()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()[:16]


def normalize_path(path):
    path = (path or "").replace("\\", "/")
    absolute = path.startswith("/")
    parts = []
    for part in path.split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            if parts and parts[-1] != "..":
                parts.pop()
            elif not absolute:
                parts.append("..")
        else:
            parts.append(part)
    return ("/" if absolute else "") + "/".join(parts)


def dirname(path):
    return posixpath.dirname(path)


def join_path(base, relative):
    if not relative:
        return ""
    if relative.startswith("/"):
        return normalize_path(relative)
    if not base:
        return normalize_path(relative)
    return normalize_path(base + "/" + relative)


def decode_bytes(data):
    if data.startswith(b"\xef\xbb\xbf"):
        return data[3:].decode("utf-8", "replace")
    if data.startswith(b"\xff\xfe") or data.startswith(b"\xfe\xff"):
        return data.decode("utf-16", "replace")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("cp1252", "replace")


NAMED_ENTITIES = {
    "amp": "&", "lt": "<", "gt": ">", "quot": '"', "apos": "'",
    "nbsp": " ", "ndash": "-", "mdash": "-", "hellip": "...",
    "lsquo": "'", "rsquo": "'", "ldquo": '"', "rdquo": '"',
}


def decode_entities(text):
    def replace(match):
        token = match.group(1)
        if token[:2].lower() == "#x":
            try:
                return chr(int(token[2:], 16))
            except ValueError:
                return match.group(0)
        if token.startswith("#"):
            try:
                return chr(int(token[1:], 10))
            except ValueError:
                return match.group(0)
        return NAMED_ENTITIES.get(token.lower(), match.group(0))

    return re.sub(r"&(#x[0-9A-Fa-f]+|#\d+|[A-Za-z]+);", replace, text)


def parse_attrs(attr_text):
    attrs = {}
    for match in ATTR_RE.finditer(attr_text or ""):
        name = match.group(1).lower()
        value = match.group(2)
        if value is None:
            value = match.group(3)
        if value is None:
            value = match.group(4) or ""
        attrs[name] = decode_entities(value)
    return attrs


def iter_tags(text):
    """Yield (name, attribute_text) for opening tags, tolerating quoted '>'."""
    for match in TAG_RE.finditer(text):
        yield match.group(1).lower(), match.group(2)


def find_tag_end(text, start):
    quote = ""
    for index in range(start + 1, len(text)):
        char = text[index]
        if quote:
            if char == quote:
                quote = ""
        elif char in "\"'":
            quote = char
        elif char == ">":
            return index
    return -1


def split_whitespace(value):
    return [part for part in (value or "").split() if part]


def token_in(value, token):
    if not value:
        return False
    return re.search(r"[\s_-]" + re.escape(token) + r"[\s_-]",
                     " " + value.lower() + " ") is not None


def any_token_in(value, tokens):
    if not value:
        return None
    for token in tokens:
        if token_in(value, token):
            return token
    return None


def length_stats(values):
    if not values:
        return {"min": 0, "median": 0, "max": 0, "buckets": {}}
    buckets = {}
    for label, low, high in TEXT_LENGTH_BUCKETS:
        buckets[label] = sum(1 for value in values if low <= value <= high)
    return {
        "min": min(values),
        "median": statistics.median(values),
        "max": max(values),
        "buckets": buckets,
    }


def normalize_token(name):
    if not name:
        return ""
    return DIGITS_RE.sub("N", name.lower())[:40]


def normalize_pattern(tag, classes, ident):
    parts = []
    for class_name in classes:
        token = normalize_token(class_name)
        if token and token not in parts:
            parts.append(token)
    if parts:
        return tag + "." + ".".join(sorted(parts))
    if ident:
        return tag + "#" + normalize_token(ident)
    return tag


# ---------------------------------------------------------------------------
# HTML scanner (deliberately tolerant; mirrors the plugin's own scanner)
# ---------------------------------------------------------------------------

class Element:
    __slots__ = ("index", "tag", "attrs", "classes", "class_set", "element_id",
                 "parent", "children", "own_text", "text", "in_head", "depth")

    def __init__(self, index, tag, attrs, parent):
        self.index = index
        self.tag = tag
        self.attrs = attrs
        self.classes = split_whitespace(attrs.get("class"))
        self.class_set = {name: True for name in self.classes}
        self.element_id = attrs.get("id")
        self.parent = parent
        self.children = []
        self.own_text = ""
        self.text = ""
        self.in_head = tag == "head" or bool(parent and parent.in_head)
        self.depth = (parent.depth + 1) if parent else 1

    def identity(self):
        return ((self.attrs.get("class") or "") + " "
                + (self.element_id or "")).lower()

    def has_class(self, name):
        return name in self.class_set


class Document:
    __slots__ = ("elements", "by_id", "body")

    def __init__(self):
        self.elements = []
        self.by_id = {}
        self.body = None


def parse_html(html):
    doc = Document()
    if not html:
        return doc
    if html.startswith("\ufeff"):
        html = html[1:]
    lower_html = html.lower()
    stack = []
    position = 0
    length = len(html)

    def add_text(fragment):
        if not fragment or not stack:
            return
        target = stack[-1]
        if len(target.own_text) < 4000:
            target.own_text += fragment

    def pop_through(tag_name):
        while stack:
            element = stack.pop()
            if element.tag == tag_name:
                return True
        return False

    while position < length:
        tag_start = html.find("<", position)
        if tag_start < 0:
            add_text(html[position:])
            break
        add_text(html[position:tag_start])

        if html.startswith("<!--", tag_start):
            close = html.find("-->", tag_start + 4)
            position = (close + 3) if close >= 0 else length
        elif html.startswith("<![CDATA[", tag_start):
            close = html.find("]]>", tag_start + 9)
            if close >= 0:
                add_text(html[tag_start + 9:close])
                position = close + 3
            else:
                position = length
        elif html.startswith("<!", tag_start) or html.startswith("<?", tag_start):
            close = html.find(">", tag_start + 2)
            position = (close + 1) if close >= 0 else length
        elif html.startswith("</", tag_start):
            close = html.find(">", tag_start + 2)
            if close < 0:
                break
            name = re.match(r"\s*([\w:.-]+)", html[tag_start + 2:close])
            if name:
                pop_through(name.group(1).lower())
            position = close + 1
        else:
            tag_end = find_tag_end(html, tag_start)
            if tag_end < 0:
                break
            inside = html[tag_start + 1:tag_end]
            self_closing = inside.endswith("/")
            if self_closing:
                inside = inside[:-1]
            name_match = re.match(r"\s*([\w:.-]+)", inside)
            if not name_match:
                position = tag_end + 1
                continue
            tag = name_match.group(1).lower()
            if tag in BLOCK_TAGS and stack and stack[-1].tag == "p" and tag != "p":
                pop_through("p")
            if tag == "li" and stack and stack[-1].tag == "li":
                pop_through("li")
            if tag in ("dt", "dd") and stack and stack[-1].tag in ("dt", "dd"):
                pop_through(stack[-1].tag)

            attrs = parse_attrs(inside)
            parent = stack[-1] if stack else None
            element = Element(len(doc.elements), tag, attrs, parent)
            doc.elements.append(element)
            if parent:
                parent.children.append(element)
            if element.element_id and element.element_id not in doc.by_id:
                doc.by_id[element.element_id] = element
            if tag == "body" and doc.body is None:
                doc.body = element
            if tag not in VOID_TAGS and not self_closing:
                stack.append(element)

            if tag in ("script", "style"):
                close_start = lower_html.find("</" + tag, tag_end + 1)
                if close_start >= 0:
                    close_end = html.find(">", close_start)
                    pop_through(tag)
                    position = (close_end + 1) if close_end >= 0 else length
                    continue
                position = length
                continue
            position = tag_end + 1

    for element in reversed(doc.elements):
        text = element.own_text
        for child in element.children:
            if child.text:
                text += " " + child.text
        text = WHITESPACE_RE.sub(" ", text).strip()
        element.text = text[:400]
    return doc


# ---------------------------------------------------------------------------
# CSS: only the declarations that decide heading signals
# ---------------------------------------------------------------------------

class Stylesheet:
    def __init__(self, texts=()):
        self.rules = []
        self.by_tag = {}
        self.by_class = {}
        self.universal = []
        self.order = 0
        for text in texts:
            self._parse(text)
        for rule in self.rules:
            if rule["tag"]:
                self.by_tag.setdefault(rule["tag"], []).append(rule)
            elif rule["classes"]:
                for class_name in rule["classes"]:
                    self.by_class.setdefault(class_name, []).append(rule)
            else:
                self.universal.append(rule)
        self._cache = {}

    def _parse(self, text):
        if not text:
            return
        text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
        for match in CSS_RULE_RE.finditer(text):
            selectors = match.group(1).strip()
            if selectors.startswith("@"):
                continue
            declarations = self._declarations(match.group(2))
            if not declarations:
                continue
            for part in selectors.split(","):
                rule = self._selector(part.strip())
                if not rule:
                    continue
                rule["decls"] = declarations
                rule["order"] = self.order
                self.order += 1
                self.rules.append(rule)

    @staticmethod
    def _declarations(body):
        declarations = {}
        for piece in body.split(";"):
            if ":" not in piece:
                continue
            name, value = piece.split(":", 1)
            name = name.strip().lower()
            if name not in CSS_PROPERTIES:
                continue
            value = value.strip()
            important = False
            if value.lower().endswith("!important"):
                important = True
                value = value[:-10].strip()
            declarations[name] = {"value": value, "important": important}
        return declarations

    @staticmethod
    def _selector(selector):
        if not selector or re.search(r"[\s>+~\[\]():]", selector):
            return None
        rule = {"tag": None, "classes": [], "id": None}
        rest = selector
        hash_index = rest.find("#")
        if hash_index >= 0:
            after = rest[hash_index + 1:]
            match = re.match(r"([\w_:.-]+)(.*)$", after)
            if not match:
                return None
            rule["id"] = match.group(1)
            rest = rest[:hash_index] + (match.group(2) or "")
        if rest == "*":
            pass
        elif rest == "":
            if not rule["id"]:
                return None
        elif rest.startswith("."):
            for class_name in rest.split(".")[1:]:
                if not re.match(r"^[A-Za-z_][\w-]*$", class_name):
                    return None
                rule["classes"].append(class_name)
        else:
            tag = re.match(r"^[^.]+", rest)
            if not tag or not re.match(r"^[A-Za-z_][\w-]*$", tag.group(0)):
                return None
            rule["tag"] = tag.group(0).lower()
            for class_name in re.findall(r"\.([^.]+)", rest):
                if not re.match(r"^[A-Za-z_][\w-]*$", class_name):
                    return None
                rule["classes"].append(class_name)
        if not rule["tag"] and not rule["id"] and not rule["classes"]:
            return None
        rule["spec"] = ((100 if rule["id"] else 0)
                        + 10 * len(rule["classes"])
                        + (1 if rule["tag"] else 0))
        return rule

    def _candidates(self, element):
        rules = list(self.universal)
        rules.extend(self.by_tag.get(element.tag, ()))
        for class_name in element.classes:
            rules.extend(self.by_class.get(class_name, ()))
        if element.element_id:
            rules.extend(rule for rule in self.rules
                         if rule["id"] == element.element_id)
        return rules

    def compute(self, element):
        if element.index in self._cache:
            return self._cache[element.index]
        best = {}

        def apply(declarations, spec, order):
            for name, declaration in declarations.items():
                important = declaration["important"]
                rank = (1 if important else 0, spec, order)
                current = best.get(name)
                if current is None or rank >= current[0]:
                    best[name] = (rank, declaration["value"])

        for rule in self._candidates(element):
            if not self._matches(rule, element):
                continue
            apply(rule["decls"], rule["spec"], rule["order"])
        style = element.attrs.get("style")
        if style:
            inline = self._declarations(style)
            for declaration in inline.values():
                declaration["important"] = True
            apply(inline, 1000, self.order + 1)
        values = {name: value for name, (rank, value) in best.items()}
        self._cache[element.index] = values
        return values

    @staticmethod
    def _matches(rule, element):
        if rule["tag"] and rule["tag"] != element.tag:
            return False
        if rule["id"] and rule["id"] != element.element_id:
            return False
        for class_name in rule["classes"]:
            if not element.has_class(class_name):
                return False
        return True


def font_size_ratio(value):
    if not value:
        return None
    value = value.strip().lower()
    keywords = {
        "xx-small": 0.6, "x-small": 0.75, "small": 0.89, "medium": 1.0,
        "large": 1.2, "x-large": 1.5, "xx-large": 2.0, "smaller": 0.85,
        "larger": 1.2,
    }
    if value in keywords:
        return keywords[value]
    percent = re.match(r"^([\d.]+)%$", value)
    if percent:
        return float(percent.group(1)) / 100.0
    number = re.match(r"^([\d.]+)\s*([a-z]*)$", value)
    if not number:
        return None
    amount = float(number.group(1))
    unit = number.group(2)
    if unit in ("em", "rem"):
        return amount
    if unit in ("ex", "ch"):
        return amount * 0.5
    if unit == "px":
        return amount / 16.0
    if unit == "pt":
        return amount / 12.0
    if unit == "pc":
        return amount / 6.0
    return None


def is_bold(value):
    if not value:
        return False
    value = value.strip().lower()
    if value in ("bold", "bolder"):
        return True
    try:
        return int(value) >= 600
    except ValueError:
        return False


def is_centered(value):
    return bool(value) and value.strip().lower() == "center"


def is_upper(value):
    return bool(value) and value.strip().lower() == "uppercase"


def page_break(value):
    if not value:
        return False
    return value.strip().lower() in ("always", "left", "right", "recto",
                                     "verso", "page")


def margin_top(value):
    if not value:
        return 0.0
    match = re.match(r"^(-?[\d.]+)\s*([a-z]*)$", value.strip().lower())
    if not match:
        return 0.0
    amount = float(match.group(1))
    unit = match.group(2)
    if unit in ("em", "rem"):
        return amount
    if unit == "px":
        return amount / 16.0
    if unit == "pt":
        return amount / 12.0
    return 0.0


def is_ancestor(element, ancestor):
    current = element.parent
    while current is not None:
        if current.index == ancestor.index:
            return True
        current = current.parent
    return False


def ancestor_tags(element):
    current = element.parent
    while current is not None:
        yield current
        current = current.parent


def has_block_children(element):
    return any(child.tag in BLOCK_TAGS and child.text for child in element.children)


def climb_to_block(element):
    current = element
    while current is not None and current.tag not in BLOCK_TAGS:
        current = current.parent
    return current


def first_block_child(element):
    for child in element.children:
        if child.tag in BLOCK_TAGS and child.text:
            return child
    return None


def first_block_in_body(doc):
    if doc.body is None:
        for element in doc.elements:
            if not element.in_head and element.tag in BLOCK_TAGS \
                    and element.tag not in ("body", "html") and element.text:
                return element
        return None
    return first_block_child(doc.body)


def ancestor_shape(element, levels=3):
    parts = []
    current = element.parent
    while current is not None and len(parts) < levels:
        if current.tag in ("body", "html"):
            break
        token = current.tag
        if current.classes:
            token += "." + normalize_token(current.classes[0])
        parts.append(token)
        current = current.parent
    return " < ".join(reversed(parts)) if parts else "body"


def sibling_shape(element, direction):
    if element.parent is None:
        return ""
    siblings = [child for child in element.parent.children if child.tag in BLOCK_TAGS]
    try:
        index = siblings.index(element)
    except ValueError:
        return ""
    index += direction
    if index < 0 or index >= len(siblings):
        return ""
    other = siblings[index]
    shape = other.tag
    if other.classes:
        shape += "." + normalize_token(other.classes[0])
    return shape


# ---------------------------------------------------------------------------
# EPUB structure
# ---------------------------------------------------------------------------

def is_xhtml_path(path, media_type=""):
    extension = posixpath.splitext(path.lower())[1]
    return extension in (".xhtml", ".html", ".htm") or media_type in (
        "application/xhtml+xml", "text/html")


def find_opf(zf):
    try:
        container = zf.read("META-INF/container.xml").decode("utf-8", "replace")
    except KeyError:
        container = ""
    match = re.search(r"<rootfile\b[^>]*>", container, re.I)
    if match:
        attrs = parse_attrs(TAG_RE.match(match.group(0)).group(2))
        if attrs.get("full-path"):
            return normalize_path(urllib.parse.unquote(attrs["full-path"]))
    for name in sorted(zf.namelist()):
        if name.lower().endswith(".opf"):
            return normalize_path(name)
    return None


def parse_package(text, base_dir=""):
    package = {
        "version": "2.0",
        "manifest": [],
        "by_id": {},
        "spine": [],
        "toc_id": None,
    }
    match = re.search(r"<package\b[^>]*>", text, re.I)
    if match:
        attrs = parse_attrs(match.group(0)[1:-1])
        if attrs.get("version"):
            package["version"] = attrs["version"]
    for name, attr_text in iter_tags(text):
        if name == "item":
            attrs = parse_attrs(attr_text)
            if attrs.get("id") and attrs.get("href"):
                item = {
                    "id": attrs["id"],
                    "path": join_path(base_dir,
                                      urllib.parse.unquote(attrs["href"])),
                    "media_type": (attrs.get("media-type") or "").lower(),
                    "properties": (attrs.get("properties") or "").lower(),
                }
                package["manifest"].append(item)
                package["by_id"][item["id"]] = item
        elif name == "spine":
            attrs = parse_attrs(attr_text)
            if attrs.get("toc"):
                package["toc_id"] = attrs["toc"]
        elif name == "itemref":
            attrs = parse_attrs(attr_text)
            if attrs.get("idref"):
                package["spine"].append(attrs["idref"])
    return package


def detect_generator(opf_text, doc_samples, names):
    lowered = "\n".join(doc_samples[:6])
    opf_lower = opf_text.lower()
    evidence = []
    scores = {}

    def add(kind, label, weight):
        evidence.append(label)
        scores[kind] = max(scores.get(kind, 0), weight)

    if re.search(r'name\s*=\s*"calibre:', opf_text, re.I):
        add("calibre", "opf:calibre-meta", 3)
    if any(name.startswith("META-INF/calibre") for name in names):
        add("calibre", "meta-inf:calibre", 3)
    if re.search(r'class\s*=\s*"[^"]*\bcalibre\d+\b', lowered, re.I):
        add("calibre", "html:class-calibreN", 2)
    if "calibre" in opf_lower:
        add("calibre", "opf:calibre", 1)

    if re.search(r'name\s*=\s*"sigil', opf_text, re.I) or "sigil" in opf_lower:
        add("sigil", "opf:sigil", 3)
    if any("sigil" in name.lower() for name in names):
        add("sigil", "meta-inf:sigil", 2)

    if re.search(r'content\s*=\s*"[^"]*pandoc', opf_text, re.I) \
            or "pandoc" in opf_lower:
        add("pandoc", "opf:pandoc", 3)
    if "generated by pandoc" in lowered.lower() or 'class="pandoc' in lowered:
        add("pandoc", "html:pandoc", 2)

    if re.search(r"adobe\s+indesign", opf_text, re.I):
        add("indesign", "opf:indesign-generator", 3)
    if "_idgen" in lowered.lower():
        add("indesign", "html:_idGen-class", 2)
    if re.search(r"<\?aid\b", lowered, re.I):
        add("indesign", "html:aid-pi", 1)

    if re.search(r"microsoft\s+word", opf_lower):
        add("word", "opf:word", 2)

    if not scores:
        return "unknown", []
    priority = {"calibre": 5, "indesign": 4, "pandoc": 3, "sigil": 2, "word": 1}
    best = max(scores, key=lambda kind: (scores[kind], priority.get(kind, 0)))
    return best, sorted(set(evidence))


def parse_ncx(text):
    entries = []
    if not text:
        return entries
    text = re.sub(r"<!DOCTYPE[^>]*>", "", text, count=1, flags=re.I | re.S)
    try:
        import xml.etree.ElementTree as ET
        root = ET.fromstring(text)
        ns = ""
        match = re.match(r"\{([^}]+)\}", root.tag)
        if match:
            ns = "{" + match.group(1) + "}"

        def walk(node, depth):
            for child in node:
                if child.tag == ns + "navPoint":
                    label = child.find(ns + "navLabel")
                    title = ""
                    if label is not None:
                        text_node = label.find(ns + "text")
                        if text_node is not None and text_node.text:
                            title = text_node.text.strip()
                    content = child.find(ns + "content")
                    src = content.get("src") if content is not None else ""
                    entries.append({"title": title, "src": src or "",
                                    "depth": depth})
                    walk(child, depth + 1)
                else:
                    walk(child, depth)
        walk(root, 1)
        return entries
    except Exception:
        pass
    stack = []
    for match in re.finditer(r"(<[^>]+>)([^<]*)", text):
        raw, text_node = match.group(1), match.group(2)
        name_match = re.match(r"</?\s*([\w:.-]+)", raw)
        if not name_match:
            continue
        name = name_match.group(1).lower()
        closing = raw.startswith("</")
        if name == "navpoint" and not closing:
            stack.append({"depth": len(stack) + 1, "title": "", "src": None})
        elif name == "navpoint" and closing:
            if stack:
                item = stack.pop()
                if item["src"]:
                    entries.append(item)
        elif name == "text" and not closing and stack:
            stack[-1]["title"] += text_node
        elif name == "content" and stack:
            attrs = parse_attrs(raw[1:-1])
            if attrs.get("src"):
                stack[-1]["src"] = attrs["src"]
    return entries


def parse_nav(text):
    entries = []
    if not text:
        return entries
    text = re.sub(r"<!DOCTYPE[^>]*>", "", text, count=1, flags=re.I | re.S)
    text = re.sub(r"&nbsp;", " ", text)
    try:
        import xml.etree.ElementTree as ET
        root = ET.fromstring(text)
        ns = ""
        match = re.match(r"\{([^}]+)\}", root.tag)
        if match:
            ns = "{" + match.group(1) + "}"
        navs = [node for node in root.iter() if node.tag == ns + "nav"]
        chosen = None
        for nav in navs:
            kind = (nav.get("epub:type")
                    or nav.get("{http://www.idpf.org/2007/ops}type")
                    or "").lower()
            role = (nav.get("role") or "").lower()
            if "toc" in kind or "doc-toc" in role:
                chosen = nav
                break
        if chosen is None and navs:
            chosen = navs[0]
        if chosen is None:
            return entries

        def walk(ol, depth):
            for li in ol.findall(ns + "li"):
                anchor = li.find(ns + "a")
                if anchor is not None and anchor.get("href"):
                    entries.append({
                        "title": "".join(anchor.itertext()).strip(),
                        "src": anchor.get("href"),
                        "depth": depth,
                    })
                sub = li.find(ns + "ol")
                if sub is not None:
                    walk(sub, depth + 1)
        top = chosen.find(ns + "ol")
        if top is not None:
            walk(top, 1)
        return entries
    except Exception:
        pass
    return entries


def split_src(src):
    if not src:
        return "", ""
    path, _, fragment = src.partition("#")
    return urllib.parse.unquote(path), urllib.parse.unquote(fragment)


def classify_toc_kind(package):
    ncx_path = None
    if package["toc_id"] and package["toc_id"] in package["by_id"]:
        item = package["by_id"][package["toc_id"]]
        if item["path"].lower().endswith(".ncx"):
            ncx_path = item["path"]
    if ncx_path is None:
        for item in package["manifest"]:
            if item["path"].lower().endswith(".ncx"):
                ncx_path = item["path"]
                break
    nav_path = None
    for item in package["manifest"]:
        if "nav" in item["properties"].split():
            nav_path = item["path"]
            break
    if nav_path is None:
        for item in package["manifest"]:
            if posixpath.basename(item["path"]).lower() in ("nav.xhtml", "nav.html"):
                nav_path = item["path"]
                break
    return ncx_path, nav_path


def encrypted_text(zf):
    try:
        xml = zf.read("META-INF/encryption.xml").decode("utf-8", "replace")
    except KeyError:
        return False
    for match in re.finditer(r'URI\s*=\s*"([^"]+)"', xml, re.I):
        path = urllib.parse.unquote(match.group(1)).lower()
        if path.endswith((".xhtml", ".html", ".htm", ".opf", ".ncx")):
            return True
    return False


# ---------------------------------------------------------------------------
# Decoy accounting
# ---------------------------------------------------------------------------

def decoy_categories(element, doc_is_front_matter):
    categories = set()
    identity = element.identity()
    for category, tokens in DECOY_TOKENS.items():
        for token in tokens:
            if token in identity:
                categories.add(category)
                break
    if element.tag in ("table", "tr", "td", "th", "caption", "thead", "tbody", "tfoot"):
        categories.add("table")
    if element.tag in ("figcaption", "figure"):
        categories.add("figure")
    if any(ancestor.tag == "blockquote" for ancestor in ancestor_tags(element)):
        categories.add("blockquote")
    if doc_is_front_matter:
        categories.add("front_matter")
    return categories


def doc_front_matter(path, doc):
    lowered = path.lower()
    if re.search(r"(titlepage|title_page|halftitle|half_title|copyright|"
                 r"dedication|colophon|cover|toc)", lowered):
        return True
    for element in doc.elements:
        kind = (element.attrs.get("epub:type")
                or element.attrs.get("epub-type") or "").lower()
        if kind in ("frontmatter", "cover", "titlepage", "copyright-page", "toc"):
            return True
    return False


INVALID_NAME_CHARS = re.compile(r'[<>:"|?*\x00-\x1f]')


def safe_segment(segment, index):
    """Return a Windows-safe file name, keeping the mapping in _entries.tsv."""
    cleaned = INVALID_NAME_CHARS.sub("_", segment).strip().rstrip(".")
    if not cleaned:
        cleaned = "entry_%d" % index
    if len(cleaned) > 80:
        extension = posixpath.splitext(cleaned)[1][:10]
        cleaned = "long_%d%s" % (index, extension)
    return cleaned


def escape_field(value):
    """Escape tabs/newlines so archive names cannot break the TSV record."""
    return (value.replace("\\", "\\\\").replace("\t", "\\t")
            .replace("\n", "\\n").replace("\r", "\\r"))


def extract_text_assets(epub_path, target):
    os.makedirs(target, exist_ok=True)
    entries = []
    used = set()
    with zipfile.ZipFile(epub_path) as zf:
        for index, info in enumerate(zf.infolist()):
            if info.is_dir():
                continue
            name = info.filename.replace("\\", "/")
            if name.startswith("/") or ".." in name.split("/"):
                continue
            extension = posixpath.splitext(name.lower())[1]
            if extension not in TEXT_EXTENSIONS and not name.startswith("META-INF/"):
                continue
            segments = [safe_segment(part, index) for part in name.split("/") if part]
            disk_rel = "/".join(segments)
            if disk_rel in used:
                disk_rel = "%s~%d" % (disk_rel, index)
            used.add(disk_rel)
            destination = os.path.join(target, *disk_rel.split("/"))
            if len(destination) > 240:
                extension = posixpath.splitext(segments[-1])[1][:10]
                segments[-1] = "long_%d%s" % (index, extension)
                disk_rel = "/".join(segments)
                destination = os.path.join(target, *disk_rel.split("/"))
            os.makedirs(os.path.dirname(destination), exist_ok=True)
            with zf.open(info) as source, open(destination, "wb") as sink:
                shutil.copyfileobj(source, sink)
            entries.append((name, disk_rel, info.file_size))
    entries.sort()
    with open(os.path.join(target, "_entries.tsv"), "w", encoding="utf-8",
              newline="\n") as handle:
        for name, disk_rel, size in entries:
            handle.write("%s\t%s\t%d\n" % (escape_field(name),
                                           escape_field(disk_rel), size))


# ---------------------------------------------------------------------------
# Per-book audit
# ---------------------------------------------------------------------------

def empty_book(book_id, size):
    return {
        "id": book_id,
        "sha": "",
        "bytes": size,
        "epub_version": None,
        "generator": "unknown",
        "generator_evidence": [],
        "duplicate_of": None,
        "documents": {},
        "toc": {"kind": "none", "entries": 0, "resolved": {}},
        "headings": {"counts": {tag: 0 for tag in HEADING_TAGS}, "total": 0,
                     "documents_with_headings": 0, "documents": 0, "empty": 0,
                     "length": length_stats([]), "examples": []},
        "pseudo": {"short_blocks": 0, "pattern_count": 0, "patterns": {}},
        "toc_targets": {"resolved_id": 0, "file_only": 0, "missing": 0},
        "decoys": {"counts": {}, "patterns": {}},
        "negative_filters": {},
        "warnings": [],
    }


def warn(book, message):
    if message not in book["warnings"]:
        book["warnings"].append(message)


def audit_book(epub_path, rel_path):
    book = empty_book(path_id(rel_path), os.path.getsize(epub_path))
    try:
        zf = zipfile.ZipFile(epub_path)
    except Exception as exc:  # report the failure, keep going
        warn(book, "unreadable archive: %s" % type(exc).__name__)
        return book

    with zf:
        names = zf.namelist()
        opf_path = find_opf(zf)
        if not opf_path:
            warn(book, "no package document")
            return book
        opf_text = zf.read(opf_path).decode("utf-8", "replace")
        package = parse_package(opf_text, dirname(opf_path))
        book["epub_version"] = package["version"]

        documents = []
        seen = set()
        for idref in package["spine"]:
            item = package["by_id"].get(idref)
            if item and is_xhtml_path(item["path"], item["media_type"]) \
                    and item["path"] not in seen:
                seen.add(item["path"])
                documents.append(item["path"])
        if not documents:
            for item in package["manifest"]:
                if is_xhtml_path(item["path"], item["media_type"]) \
                        and item["path"] not in seen:
                    seen.add(item["path"])
                    documents.append(item["path"])

        css_texts = []
        css_documents = 0
        for item in package["manifest"]:
            if item["path"].lower().endswith(".css") or item["media_type"] == "text/css":
                try:
                    css_texts.append(zf.read(item["path"]).decode("utf-8", "replace"))
                    css_documents += 1
                except KeyError:
                    warn(book, "missing stylesheet")
        stylesheet = Stylesheet(css_texts)

        docs = {}
        html_bytes = 0
        for path in documents:
            try:
                raw = zf.read(path)
            except KeyError:
                warn(book, "missing spine document")
                continue
            html_bytes += len(raw)
            docs[path] = parse_html(decode_bytes(raw))

        ncx_path, nav_path = classify_toc_kind(package)
        ncx_entries, nav_entries = [], []
        if ncx_path:
            try:
                ncx_entries = parse_ncx(zf.read(ncx_path).decode("utf-8", "replace"))
            except KeyError:
                warn(book, "missing ncx")
        if nav_path:
            try:
                nav_entries = parse_nav(zf.read(nav_path).decode("utf-8", "replace"))
            except KeyError:
                warn(book, "missing nav document")

        if ncx_entries and nav_entries:
            kind = "both"
        elif ncx_entries:
            kind = "ncx_only"
        elif nav_entries:
            kind = "nav_only"
        elif ncx_path and nav_path:
            kind = "both_empty"
        elif ncx_path:
            kind = "ncx_empty"
        elif nav_path:
            kind = "nav_empty"
        else:
            kind = "none"

        if len(ncx_entries) >= len(nav_entries):
            source_entries, source_base = ncx_entries, dirname(ncx_path or "")
        else:
            source_entries, source_base = nav_entries, dirname(nav_path or "")

        depth_counts = {}
        resolved = {"id": 0, "file": 0, "missing": 0}
        target_patterns = {}
        front_matter_entries = 0
        for entry in source_entries:
            title = (entry.get("title") or "").strip().lower()
            if title in FRONT_MATTER_TITLES or title.startswith(
                    ("cover", "contents", "copyright", "title page")):
                front_matter_entries += 1
            depth = str(entry.get("depth") or 1)
            depth_counts[depth] = depth_counts.get(depth, 0) + 1
            path, fragment = split_src(entry.get("src") or "")
            target = join_path(source_base, path) if path else ""
            doc = docs.get(target)
            if doc is None:
                resolved["missing"] += 1
                continue
            element = doc.by_id.get(fragment) if fragment else None
            if element is not None:
                element = climb_to_block(element)
                if element is not None and has_block_children(element):
                    child = first_block_child(element)
                    if child is not None:
                        element = child
            if element is None:
                resolved["file"] += 1
                continue
            resolved["id"] += 1
            pattern = normalize_pattern(element.tag, element.classes, element.element_id)
            record = target_patterns.setdefault(
                pattern, {"entries": 0, "real_heading": False, "lengths": []})
            record["entries"] += 1
            record["real_heading"] = record["real_heading"] or element.tag in HEADING_TAGS
            record["lengths"].append(len(element.text))

        book["toc"] = {
            "kind": kind,
            "entries": len(source_entries),
            "ncx_entries": len(ncx_entries),
            "nav_entries": len(nav_entries),
            "ncx_present": bool(ncx_path),
            "nav_present": bool(nav_path),
            "depths": depth_counts,
            "resolved": resolved,
            "front_matter_entries": front_matter_entries,
            "target_patterns": {
                pattern: {
                    "entries": record["entries"],
                    "real_heading": record["real_heading"],
                    "median_text_len": statistics.median(record["lengths"]),
                }
                for pattern, record in sorted(target_patterns.items())
            },
        }

        heading_counts = {tag: 0 for tag in HEADING_TAGS}
        heading_lengths = []
        empty_headings = 0
        documents_with_headings = []
        for position, path in enumerate(documents, 1):
            doc = docs.get(path)
            if doc is None:
                continue
            per_doc = {tag: 0 for tag in HEADING_TAGS}
            for element in doc.elements:
                if element.tag in HEADING_TAGS and not element.in_head:
                    per_doc[element.tag] += 1
                    heading_counts[element.tag] += 1
                    if element.text:
                        heading_lengths.append(len(element.text))
                    else:
                        empty_headings += 1
            total = sum(per_doc.values())
            if total:
                documents_with_headings.append({
                    "position": position,
                    "counts": per_doc,
                    "explicit_levels": sum(1 for tag, count in per_doc.items()
                                           if tag != "h1" and count and not per_doc["h1"]),
                })
        documents_with_headings.sort(key=lambda item: (-sum(item["counts"].values()),
                                                       item["position"]))
        book["headings"] = {
            "counts": heading_counts,
            "total": sum(heading_counts.values()),
            "documents_with_headings": len(documents_with_headings),
            "documents": len(docs),
            "empty": empty_headings,
            "length": length_stats(heading_lengths),
            "examples": documents_with_headings[:20],
        }

        pattern_stats = {}
        pattern_docs = {}
        negative = {"in_head": 0, "forbidden_ancestor": 0, "negative_token": 0,
                    "long_text": 0, "block_children": 0}
        decoy_counts = {}
        decoy_patterns = {}
        prose_long_blocks = 0
        short_blocks = 0
        for path, doc in docs.items():
            front = doc_front_matter(path, doc)
            class_counts = {}
            for element in doc.elements:
                for class_name in element.classes:
                    class_counts[class_name] = class_counts.get(class_name, 0) + 1
            first = first_block_in_body(doc)
            for element in doc.elements:
                if element.in_head:
                    negative["in_head"] += 1
                    continue
                if element.tag not in BLOCK_TAGS or element.tag in ("body", "html"):
                    continue
                is_heading = element.tag in HEADING_TAGS
                for category in decoy_categories(element, front):
                    decoy_counts[category] = decoy_counts.get(category, 0) + 1
                    pattern = normalize_pattern(element.tag, element.classes,
                                                element.element_id)
                    record = decoy_patterns.setdefault(category, {}).setdefault(
                        pattern, {"elements": 0})
                    record["elements"] += 1
                if is_heading or not element.text:
                    continue
                if len(element.text) > 140:
                    prose_long_blocks += 1
                    negative["long_text"] += 1
                    continue
                if has_block_children(element):
                    negative["block_children"] += 1
                    continue
                if element.tag in FORBIDDEN_ANCESTORS:
                    negative["forbidden_ancestor"] += 1
                    continue
                forbidden = False
                for ancestor in ancestor_tags(element):
                    if ancestor.tag in FORBIDDEN_ANCESTORS:
                        forbidden = True
                        break
                if not forbidden:
                    for class_name in element.classes:
                        lowered = class_name.lower()
                        if "toc" in lowered or "nav" in lowered or "footnote" in lowered:
                            forbidden = True
                            break
                if not forbidden and any_token_in(element.identity(), NEGATIVE_TOKENS):
                    forbidden = True
                if forbidden:
                    negative["negative_token"] += 1
                    continue

                values = stylesheet.compute(element)
                ratio = font_size_ratio(values.get("font-size")) or 1.0
                bold = is_bold(values.get("font-weight"))
                centered = is_centered(values.get("text-align"))
                upper = is_upper(values.get("text-transform"))
                breaks = page_break(values.get("page-break-before")) \
                    or page_break(values.get("break-before"))
                if not breaks:
                    for ancestor in ancestor_tags(element):
                        ancestor_values = stylesheet.compute(ancestor)
                        if page_break(ancestor_values.get("page-break-before")) \
                                or page_break(ancestor_values.get("break-before")):
                            breaks = True
                            break
                indent = values.get("text-indent")
                hanging = bool(indent) and indent.strip().startswith("-")
                identity = element.identity()
                name_hint = any_token_in(identity, NAME_TOKENS)
                single_use = any(class_counts.get(name, 0) == 1
                                 for name in element.classes)
                is_first = first is not None and (
                    first.index == element.index
                    or (is_ancestor(element, first) and len(first.text) <= 140))
                pattern = normalize_pattern(element.tag, element.classes,
                                            element.element_id)

                signals = {}
                if name_hint:
                    signals["name_hint"] = 1
                if breaks:
                    signals["page_break"] = 1
                if bold:
                    signals["bold"] = 1
                if centered:
                    signals["centered"] = 1
                if upper:
                    signals["upper"] = 1
                if is_first:
                    signals["first_block"] = 1
                if single_use:
                    signals["single_use"] = 1
                if bold and ratio >= 1.12:
                    signals["bright"] = 1
                if hanging:
                    signals["hanging_indent"] = 1

                record = pattern_stats.setdefault(pattern, {
                    "elements": 0, "lengths": [], "signals": {},
                    "ancestors": {}, "previous": {}, "next": {},
                })
                record["elements"] += 1
                record["lengths"].append(len(element.text))
                for key, value in signals.items():
                    record["signals"][key] = record["signals"].get(key, 0) + value
                ancestor = ancestor_shape(element)
                record["ancestors"][ancestor] = record["ancestors"].get(ancestor, 0) + 1
                previous = sibling_shape(element, -1)
                following = sibling_shape(element, 1)
                if previous:
                    record["previous"][previous] = record["previous"].get(previous, 0) + 1
                if following:
                    record["next"][following] = record["next"].get(following, 0) + 1
                pattern_docs.setdefault(pattern, set()).add(path)
                short_blocks += 1

        for pattern, record in pattern_stats.items():
            target = book["toc"]["target_patterns"].get(pattern)
            record["toc_entries"] = target["entries"] if target else 0
            record["documents"] = len(pattern_docs[pattern])
            record["text_len"] = length_stats(record.pop("lengths"))
            record["ancestors"] = dict(sorted(record["ancestors"].items(),
                                              key=lambda kv: (-kv[1], kv[0]))[:3])
            record["previous"] = dict(sorted(record["previous"].items(),
                                             key=lambda kv: (-kv[1], kv[0]))[:3])
            record["next"] = dict(sorted(record["next"].items(),
                                         key=lambda kv: (-kv[1], kv[0]))[:3])
        book["pseudo"] = {
            "short_blocks": short_blocks,
            "pattern_count": len(pattern_stats),
            "patterns": dict(sorted(pattern_stats.items())),
        }
        book["negative_filters"] = negative
        book["decoys"] = {
            "counts": dict(sorted(decoy_counts.items())),
            "patterns": {category: dict(sorted(patterns.items()))
                         for category, patterns in sorted(decoy_patterns.items())},
            "prose_long_blocks": prose_long_blocks,
        }
        book["documents"] = {
            "spine": len(documents),
            "parsed": len(docs),
            "css": css_documents,
            "html_bytes": html_bytes,
            "archive_entries": len(names),
            "encryption_xml": "META-INF/encryption.xml" in names,
            "encrypted_text": encrypted_text(zf),
        }

        samples = [decode_bytes(zf.read(path))[:40000] for path in documents[:6]
                   if path in docs]
        generator, evidence = detect_generator(opf_text, samples, names)
        book["generator"] = generator
        book["generator_evidence"] = evidence

    book["sha"] = content_sha1(epub_path)
    return book


# ---------------------------------------------------------------------------
# Aggregation and output
# ---------------------------------------------------------------------------

def aggregate(books, classifier, verdicts=None, verdict_source=None):
    totals = {
        "books": len(books),
        "unique_books": len({book["sha"] for book in books}),
        "bytes": sum(book["bytes"] for book in books),
        "documents": sum(book["documents"].get("spine", 0) for book in books),
        "headings": {tag: sum(book["headings"]["counts"].get(tag, 0) for book in books)
                     for tag in HEADING_TAGS},
        "books_without_headings": sum(1 for book in books
                                      if book["headings"]["total"] == 0),
        "books_without_toc": sum(1 for book in books
                                 if book["toc"].get("entries", 0) == 0),
        "toc_entries": sum(book["toc"].get("entries", 0) for book in books),
        "toc_resolved_id": sum(book["toc"].get("resolved", {}).get("id", 0)
                               for book in books),
        "toc_file_only": sum(book["toc"].get("resolved", {}).get("file", 0)
                             for book in books),
        "toc_missing": sum(book["toc"].get("resolved", {}).get("missing", 0)
                           for book in books),
        "pseudo_short_blocks": sum(book["pseudo"]["short_blocks"] for book in books),
    }
    generators = {}
    for book in books:
        bucket = generators.setdefault(book["generator"], {
            "books": 0, "documents": 0, "headings": 0, "toc_entries": 0,
            "toc_kinds": {}, "books_without_headings": 0, "books_without_toc": 0,
            "patterns": 0,
        })
        bucket["books"] += 1
        bucket["documents"] += book["documents"].get("spine", 0)
        bucket["headings"] += book["headings"]["total"]
        bucket["toc_entries"] += book["toc"].get("entries", 0)
        kind = book["toc"].get("kind", "none")
        bucket["toc_kinds"][kind] = bucket["toc_kinds"].get(kind, 0) + 1
        bucket["patterns"] += len(book["pseudo"]["patterns"])
        if book["headings"]["total"] == 0:
            bucket["books_without_headings"] += 1
        if book["toc"].get("entries", 0) == 0:
            bucket["books_without_toc"] += 1

    toc_kinds = {}
    versions = {}
    for book in books:
        kind = book["toc"].get("kind", "none")
        toc_kinds[kind] = toc_kinds.get(kind, 0) + 1
        version = book["epub_version"] or "unknown"
        versions[version] = versions.get(version, 0) + 1

    patterns = {}
    toc_targets = {}
    decoys = {}
    for book in books:
        for pattern, record in book["toc"].get("target_patterns", {}).items():
            entry = toc_targets.setdefault(pattern, {
                "books": 0, "entries": 0, "real_heading_books": 0, "lengths": [],
            })
            entry["books"] += 1
            entry["entries"] += record["entries"]
            if record["real_heading"]:
                entry["real_heading_books"] += 1
            entry["lengths"].append(record["median_text_len"])
        for pattern, record in book["pseudo"]["patterns"].items():
            entry = patterns.setdefault(pattern, {
                "books": 0, "elements": 0, "documents": 0,
                "signals": {}, "lengths": [], "ancestors": {},
                "previous": {}, "next": {}, "generators": {},
                "toc_entry_books": 0,
            })
            entry["books"] += 1
            entry["elements"] += record["elements"]
            entry["documents"] += record["documents"]
            for key, value in record["signals"].items():
                entry["signals"][key] = entry["signals"].get(key, 0) + value
            entry["lengths"].append(record["text_len"]["median"])
            for key in ("ancestors", "previous", "next"):
                for shape, count in record[key].items():
                    entry[key][shape] = entry[key].get(shape, 0) + count
            entry["generators"][book["generator"]] = \
                entry["generators"].get(book["generator"], 0) + 1
            if record["toc_entries"]:
                entry["toc_entry_books"] += 1
        for category, category_patterns in book["decoys"]["patterns"].items():
            bucket = decoys.setdefault(category, {"books": 0, "elements": 0,
                                                  "patterns": {}})
            bucket["books"] += 1
            for pattern, record in category_patterns.items():
                bucket["elements"] += record["elements"]
                target = bucket["patterns"].setdefault(
                    pattern, {"books": 0, "elements": 0})
                target["books"] += 1
                target["elements"] += record["elements"]

    for entry in patterns.values():
        entry["text_len"] = length_stats(entry.pop("lengths"))
        for key in ("ancestors", "previous", "next"):
            entry[key] = dict(sorted(entry[key].items(),
                                     key=lambda kv: (-kv[1], kv[0]))[:5])
        entry["signals"] = dict(sorted(entry["signals"].items()))
        entry["generators"] = dict(sorted(entry["generators"].items()))
    for entry in toc_targets.values():
        entry["text_len"] = length_stats(entry.pop("lengths"))
    for bucket in decoys.values():
        bucket["patterns"] = dict(sorted(
            bucket["patterns"].items(), key=lambda kv: (-kv[1]["elements"], kv[0])))

    result = {
        "schema": SCHEMA,
        "totals": totals,
        "versions": dict(sorted(versions.items())),
        "generators": dict(sorted(generators.items())),
        "toc_kinds": dict(sorted(toc_kinds.items())),
        "pseudo_patterns": dict(sorted(patterns.items())),
        "toc_target_patterns": dict(sorted(toc_targets.items())),
        "decoys": dict(sorted(decoys.items())),
    }
    if classifier:
        result["classifier"] = classifier
    summary = verdict_summary(books, classifier, verdicts, books, verdict_source)
    if summary:
        result["verdicts"] = summary
    return result


def merge_classifier(books, classifier_path):
    if not classifier_path or not os.path.exists(classifier_path):
        return None
    with open(classifier_path, encoding="utf-8") as handle:
        data = json.load(handle)
    if not data.get("books"):
        sys.stderr.write("warning: %s has no book records; re-run "
                         "tools/corpus_classify.lua\n" % classifier_path)
        return None
    by_id = {book.get("id"): book for book in data.get("books", [])}
    for book in books:
        record = by_id.get(book["id"])
        if record is None:
            continue
        book["classifier"] = {
            "ok": record.get("ok"),
            "error": record.get("error"),
            "skipped": record.get("skipped"),
            "stats": record.get("stats") or {},
            "warnings": record.get("warnings") or [],
            "candidates": record.get("candidates") or [],
            "verdicts": record.get("verdicts") or {},
        }
    roles = {}
    selectors = {}
    for record in data.get("books", []):
        for candidate in record.get("candidates") or []:
            role = candidate.get("role_hint", "unknown")
            roles[role] = roles.get(role, 0) + 1
            entry = selectors.setdefault(candidate.get("selector", ""), {
                "books": 0, "count": 0, "levels": {}, "scores": [],
                "reasons": {}, "role_hints": {},
            })
            entry["books"] += 1
            entry["count"] += candidate.get("count", 0)
            level = str(candidate.get("level"))
            entry["levels"][level] = entry["levels"].get(level, 0) + 1
            entry["scores"].append(candidate.get("score", 0))
            for reason in candidate.get("reasons") or []:
                entry["reasons"][reason] = entry["reasons"].get(reason, 0) + 1
            entry["role_hints"][role] = entry["role_hints"].get(role, 0) + 1
    for entry in selectors.values():
        scores = entry.pop("scores")
        entry["score"] = {"min": min(scores) if scores else 0,
                          "max": max(scores) if scores else 0}
        entry["levels"] = dict(sorted(entry["levels"].items()))
        entry["reasons"] = dict(sorted(entry["reasons"].items()))
        entry["role_hints"] = dict(sorted(entry["role_hints"].items()))
    summary = {
        "books": len(data.get("books", [])),
        "books_with_candidates": sum(1 for record in data.get("books", [])
                                     if record.get("candidates")),
        "books_with_errors": sum(1 for record in data.get("books", [])
                                 if record.get("error")),
        "books_skipped": sum(1 for record in data.get("books", [])
                             if record.get("skipped")),
        "candidates": sum(len(record.get("candidates") or [])
                          for record in data.get("books", [])),
        "roles": dict(sorted(roles.items())),
        "selectors": dict(sorted(selectors.items())),
    }
    return summary


# ---------------------------------------------------------------------------
# Reviewed verdicts and precision/recall
# ---------------------------------------------------------------------------

# ToC targets that are not heading-shaped: bylines, copyright pages,
# dedications, epigraphs, cover documents and title pages. They are reported
# separately because styling them would not be a heading detection.
NON_HEADING_TARGET = re.compile(
    r"(copyright|dedicat|epigraph|epgN|cover|byline|author|acknowledg|colophon|"
    r"titlepage|halftitle|imprint)", re.IGNORECASE)

# A heading is short. Targets whose text is this long are section wrappers that
# contain the heading, not the heading itself.
WRAPPER_TEXT_LEN = 140


def selector_pattern(selector):
    """Normalise a classifier selector the same way as a ToC target pattern."""
    tag, sep, rest = selector.partition("#")
    if sep:
        return normalize_pattern(tag, [], rest)
    tag, _, classes = selector.partition(".")
    return normalize_pattern(tag, [name for name in classes.split(".") if name], None)


def load_verdicts(path):
    """Read the reviewed verdict table: book, selector, verdict, family, note."""
    if not path or not os.path.exists(path):
        return None
    rows = {}
    with open(path, encoding="utf-8") as handle:
        header = handle.readline().rstrip("\n").split("\t")
        if header[:3] != ["book", "selector", "verdict"]:
            raise ValueError("unexpected verdict header: %s" % header)
        for line in handle:
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 4:
                continue
            row = dict(zip(header, fields))
            rows[(row["book"], row["selector"])] = {
                "verdict": row["verdict"],
                "family": row["family"],
                "note": row.get("note", ""),
            }
    return rows


def verdict_summary(books, classifier, verdicts, report, source):
    if not classifier or not verdicts:
        return None
    counts = {"TP": 0, "FP": 0, "PARTIAL": 0, "unreviewed": 0}
    occurrences = {"TP": 0, "FP": 0, "PARTIAL": 0, "unreviewed": 0}
    by_role = {}
    by_family = {}
    per_book = {}
    for book in books:
        record = book.get("classifier")
        if not record:
            continue
        book_counts = {"candidates": 0, "TP": 0, "FP": 0, "PARTIAL": 0,
                       "unreviewed": 0, "tp_occurrences": 0, "fp_occurrences": 0}
        for candidate in record.get("candidates") or []:
            verdict = verdicts.get((book["id"], candidate.get("selector")))
            kind = verdict["verdict"] if verdict else "unreviewed"
            family = verdict["family"] if verdict else "unreviewed"
            count = candidate.get("count", 0)
            counts[kind] += 1
            occurrences[kind] += count
            book_counts["candidates"] += 1
            book_counts[kind] += 1
            if kind == "TP":
                book_counts["tp_occurrences"] += count
            elif kind == "FP":
                book_counts["fp_occurrences"] += count
            role = candidate.get("role_hint", "unknown")
            for table, key in ((by_role, role), (by_family, family)):
                entry = table.setdefault(key, {"candidates": 0, "occurrences": 0,
                                               "TP": 0, "FP": 0, "PARTIAL": 0,
                                               "unreviewed": 0})
                entry["candidates"] += 1
                entry["occurrences"] += count
                entry[kind] += 1
        per_book[book["id"]] = book_counts

    judged = counts["TP"] + counts["FP"]
    judged_occ = occurrences["TP"] + occurrences["FP"]
    with_any = [book_id for book_id, entry in per_book.items()
                if entry["candidates"]]
    without_tp = [book_id for book_id in with_any
                  if not per_book[book_id]["TP"]]
    summary = {
        "source": source,
        "candidates": counts,
        "occurrences": occurrences,
        "precision": {
            "candidate": round(counts["TP"] / judged, 4) if judged else None,
            "occurrence": round(occurrences["TP"] / judged_occ, 4) if judged_occ else None,
        },
        "books_with_candidates": len(with_any),
        "books_without_true_positive": len(without_tp),
        "books_without_true_positive_ids": sorted(
            book_id for book_id in without_tp
            if per_book[book_id]["fp_occurrences"] or per_book[book_id]["PARTIAL"]),
        "by_role": {key: dict(sorted(value.items()))
                    for key, value in sorted(by_role.items())},
        "by_family": {key: dict(sorted(value.items()))
                      for key, value in sorted(by_family.items())},
        "per_book": {key: dict(sorted(value.items()))
                     for key, value in sorted(per_book.items())},
    }

    # Tier-1 (ToC) recall: which non-heading ToC targets reach the classifier.
    detected = set()
    for book in books:
        record = book.get("classifier")
        for candidate in (record or {}).get("candidates") or []:
            detected.add((book["id"], selector_pattern(candidate.get("selector", ""))))
    raw = {"entries": 0, "covered": 0, "patterns": 0}
    shaped = {"entries": 0, "covered": 0, "patterns": 0}
    misses = []
    excluded = []
    for book in report:
        for pattern, target in book.get("toc", {}).get("target_patterns", {}).items():
            if target.get("real_heading"):
                continue
            hit = (book["id"], pattern) in detected
            raw["entries"] += target["entries"]
            raw["patterns"] += 1
            raw["covered"] += target["entries"] if hit else 0
            is_wrapper = target.get("median_text_len", 0) >= WRAPPER_TEXT_LEN
            if is_wrapper or NON_HEADING_TARGET.search(pattern):
                excluded.append({"book": book["id"], "pattern": pattern,
                                 "entries": target["entries"], "detected": hit})
                continue
            shaped["entries"] += target["entries"]
            shaped["patterns"] += 1
            shaped["covered"] += target["entries"] if hit else 0
            if not hit:
                misses.append({"book": book["id"], "pattern": pattern,
                               "entries": target["entries"],
                               "median_text_len": target.get("median_text_len", 0)})
    for bucket in (raw, shaped):
        bucket["rate"] = (round(bucket["covered"] / bucket["entries"], 4)
                          if bucket["entries"] else None)
    summary["recall"] = {
        "toc_targets_all": raw,
        "toc_targets_heading_shaped": shaped,
        "excluded_targets": excluded,
        "misses": sorted(misses, key=lambda item: (-item["entries"], item["book"],
                                                   item["pattern"])),
    }
    return summary


def write_json(path, payload):
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True, ensure_ascii=True)
        handle.write("\n")


def find_corpus(explicit):
    if explicit:
        return os.path.abspath(explicit)
    env = os.environ.get("BOOK_THEME_CORPUS")
    if env:
        return os.path.abspath(env)
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return os.path.abspath(os.path.join(os.path.dirname(root),
                                        "meaning-and-meditation"))


def discover_books(corpus):
    books = []
    for dirpath, dirnames, filenames in os.walk(corpus):
        dirnames.sort()
        for name in sorted(filenames):
            if name.lower().endswith(".epub"):
                full = os.path.join(dirpath, name)
                books.append((os.path.relpath(full, corpus), full))
    books.sort(key=lambda item: item[0].replace("\\", "/"))
    return books


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--corpus", help="corpus directory containing .epub files")
    parser.add_argument("--out", default=os.path.join("local", "corpus-audit"),
                        help="output directory (default: local/corpus-audit)")
    parser.add_argument("--temp", help="temporary extraction root")
    parser.add_argument("--no-extract", action="store_true",
                        help="do not extract text assets")
    parser.add_argument("--classifier", help="classifier.json to merge")
    parser.add_argument("--no-classifier", action="store_true",
                        help="ignore an existing classifier.json")
    parser.add_argument("--verdicts", help="reviewed verdicts.tsv to merge")
    parser.add_argument("--no-verdicts", action="store_true",
                        help="ignore an existing verdicts.tsv")
    parser.add_argument("--limit", type=int, default=0,
                        help="audit only the first N books")
    args = parser.parse_args(argv)

    corpus = find_corpus(args.corpus)
    if not os.path.isdir(corpus):
        sys.stderr.write("corpus not found: %s\n" % corpus)
        return 2
    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)

    temp_root = args.temp or os.environ.get("BOOK_THEME_CORPUS_TEMP") or \
        os.path.join(tempfile.gettempdir(), "koreader-corpus-audit")
    temp_root = os.path.abspath(temp_root)
    if not args.no_extract:
        if os.path.isdir(temp_root):
            shutil.rmtree(temp_root)
        os.makedirs(temp_root, exist_ok=True)

    books = discover_books(corpus)
    if args.limit:
        books = books[:args.limit]

    results = []
    extraction = []
    duplicate_map = {}
    for index, (rel, full) in enumerate(books, 1):
        book_id = path_id(rel)
        sys.stderr.write("[%d/%d] %s\n" % (index, len(books), book_id))
        book = audit_book(full, rel)
        if book["sha"] and book["sha"] in duplicate_map:
            book["duplicate_of"] = duplicate_map[book["sha"]]
        elif book["sha"]:
            duplicate_map[book["sha"]] = book["id"]
        results.append(book)
        extract_dir = os.path.join(temp_root, "books", book_id) \
            if not args.no_extract else ""
        if extract_dir:
            extract_text_assets(full, extract_dir)
        extraction.append({"id": book_id, "root": extract_dir,
                           "bytes": book["bytes"]})

    if args.no_extract:
        # Keep the manifest meaningful: reuse the roots recorded by the last
        # extraction run instead of writing an empty manifest.
        previous = os.path.join(out_dir, "extraction.json")
        roots = {}
        if os.path.exists(previous):
            with open(previous, encoding="utf-8") as handle:
                for item in json.load(handle).get("books", []):
                    roots[item.get("id")] = item.get("root") or ""
        for item in extraction:
            item["root"] = roots.get(item["id"], "")

    classifier_path = args.classifier or os.path.join(out_dir, "classifier.json")
    if args.no_classifier:
        classifier_path = None
    classifier = merge_classifier(results, classifier_path)
    verdicts_path = args.verdicts or os.path.join(out_dir, "verdicts.tsv")
    if args.no_verdicts:
        verdicts_path = None
    verdicts = load_verdicts(verdicts_path)
    verdict_source = None
    if verdicts is not None:
        verdict_source = os.path.relpath(verdicts_path).replace("\\", "/")

    write_json(os.path.join(out_dir, "report.json"), {
        "schema": SCHEMA,
        "corpus": {
            "books": len(results),
            "unique_books": len({book["sha"] for book in results}),
            "duplicates": sorted(book["id"] for book in results
                                 if book["duplicate_of"]),
        },
        "books": results,
    })
    write_json(os.path.join(out_dir, "aggregate.json"),
               aggregate(results, classifier, verdicts, verdict_source))

    write_json(os.path.join(out_dir, "extraction.json"), {
        "schema": SCHEMA,
        "books": extraction,
    })
    manifest_path = os.path.join(out_dir, "extraction.tsv")
    with open(manifest_path, "w", encoding="utf-8", newline="\n") as handle:
        for item in extraction:
            if item["root"]:
                handle.write("%s\t%s\n" % (item["id"], item["root"]))
    sys.stderr.write("wrote %s\n" % out_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
