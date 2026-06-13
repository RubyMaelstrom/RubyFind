# RubyFind — Article Extraction Notes

## How It Works

The article reader lives in `lua/article_extract.lua` and is invoked via
`/search/read?a=<url>` from `lua/handlers/read.lua`.

Pipeline:

1. **Fetch** the target URL with curl (user-agent set to a desktop browser).
2. **Strip non-content elements** — `<nav>`, `<div>` / `<section>` / `<aside>`
   whose class or id contains keywords like `menu`, `sidebar`, `toc`, `header`,
   `footer`, `ad`, `social`, `share`, `breadcrumbs`, etc. (see
   `NON_CONTENT_KEYWORDS`). Block-level tags only; inline elements are left alone.
3. **Strip decorative HTML** — `<style>`, `<script>`, `<link>`, `<meta>`,
   `<img>`, form controls (`<input>`, `<button>`, `<select>`, `<textarea>`),
   `<hr>`, and HTML comments. `<br>` becomes a space.
4. **Find the best content container** — searches for common article class/id
   patterns (`article-body`, `entry-content`, `post-body`, etc.), then falls back
   to `<article>` tags, then scans all `<p>` tags inside `<body>` picking the
   largest text block. A depth counter handles nested same-name tags correctly.
5. **Clean up** — strip remaining tags keeping only article formatting (`<p>`,
   `<ul>`, `<ol>`, `<li>`, `<h1>`–`<h6>`, `<strong>`, `<em>`, `<blockquote>`, etc.),
   then normalize curly quotes and dashes.

## Scoring

Containers are scored by:

- **Character density** (primary signal — characters after stripping tags)
- **Paragraph count bonus** (+30 per paragraph beyond the first)
- **Heading bonus** (+25 for `<h1>`, +10 for any other heading)
- **Link ratio penalty** — containers where link text dominates prose get reduced scores

Minimum threshold: 100 characters of plain text.

## Lua 5.1 / OpenResty Compatibility

OpenResty uses LuaJIT based on Lua 5.1, which lacks the `continue` keyword
(Lua 5.2+ feature). Use `if/else` restructure or `goto` (LuaJIT extension) instead.

## Key Bug Found (Lua `string.find` literal vs pattern mode)

Every `html:find(pattern, pos, true)` call with the third argument `true` treats
the pattern as a **literal string**, not a Lua pattern. This was silently breaking
tag detection because patterns like `<[%w_]+%s*[^>]*>` contain Lua metacharacters
(`[`, `%`, `*`) that only have special meaning in pattern mode.

**Fix:** Remove the third argument (`true`) from all `html:find()` calls that use
Lua pattern syntax. Keep `true` only for pure literal searches like
`html:find("</nav>", pos, true)`.

## OpenResty Module Caching

OpenResty compiles Lua files once per worker process at startup. After editing
any `.lua` file in `lua/`, you **must reload nginx** for changes to take effect:

```bash
nginx -s reload
# or
systemctl restart nginx
```

If you're developing and want automatic reloading, add this inside the server block
in `nginx.conf`:

```nginx
lua_code_cache off;
```

## Class / ID Matching Strategy

The `NON_CONTENT_KEYWORDS` list uses **substring matching** (`class_val:find(kw)`)
rather than exact CSS class comparison. This catches both space-separated classes
(`"nav sidebar"`) and hyphenated ones (`"social-share"` matches keyword `"social"`).

Be aware that short keywords like `box`, `ad`, or `tab` may cause false positives
on unusual class names. If a real article element gets incorrectly stripped, add its
specific class/id to a whitelist or make the keyword more specific (e.g., `"navbox"`
instead of just `"box"`).

## Adding New Non-Content Keywords

Add entries to the `NON_CONTENT_KEYWORDS` table in `article_extract.lua`. Group them
by category with comments for maintainability. Prefer longer, more specific keywords
to avoid false positives on legitimate content classes.

## Wikipedia-Specific Issues (Session Notes)

### The `<main id="content">` Trap
Wikipedia wraps the entire page body in `<main id="content" class="mw-body">`.
My `id_patterns` had `"content"` which matched this, extracting ALL content including
nav/portlet elements. **Fix:** replace generic `"content"` with specific patterns like
`"mw-content-text"` and add `"mw-body-content"`, `"mw-parser-output"` to class_patterns.

### Nav Elements Are NOT in `<nav>` Tags (Anymore)
Modern Wikipedia uses `<div class="vector-menu ...">` and `<div class="mw-portlet ...">`
for navigation instead of semantic `<nav>` tags. The `strip_non_content` function must
catch these via class/id keyword matching, not just `<nav>` detection.

### Language Menus Live Inside Article Containers
Wikipedia puts language menus (e.g., `id="p-lang-btn"`) inside the same container as
article content (`mw-content-text`). Stripping them requires either:
- Adding `"lang-list"`, `"interlanguage"` to keywords (they contain "lang")
- OR extracting only `<p>` tag content after initial stripping

### The Two-Phase Approach That Worked Best
1. **Strip aggressively first** — remove nav, sidebar, ads, style/script blocks
2. **Extract from the right container** — `id="mw-content-text"` or `<article>` tags
3. **Filter remaining nav text** — keep only text chunks with periods/commas OR long words (≥13 chars)

### Common Pitfalls
- `strip_tags` removes ALL tags including newlines → prose becomes one jumble
- Over-aggressive `<ul>/<ol>` stripping removes legitimate article lists (taxonomy, disambiguation)
- Only strip lists that are clearly navigation: ≥3 items, all contain `<a>` links, no `<p>` or headings inside

## Adding New Non-Content Keywords

Add entries to the `NON_CONTENT_KEYWORDS` table in `article_extract.lua`. Group them
by category with comments for maintainability. Prefer longer, more specific keywords
to avoid false positives on legitimate content classes.

