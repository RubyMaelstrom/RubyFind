local http_fetch = require "RubyFind.http_fetch"
local html_utils = require "RubyFind.html"
local string_utils = require "RubyFind.string_util"

local _M = {}

-- Generic keywords that indicate non-article content. Any block-level element
-- whose class or id contains one of these (as a whole-class match) is removed.
local NON_CONTENT_KEYWORDS = {
    -- Navigation
    "nav", "navigation", "menu", "sidebar", "dropdown", "breadcrumbs",
    "main-menu", "primary-nav", "secondary-nav", "topnav", "hamburger",
    -- Structure / decoration
    "toc", "table-of-contents", "panel", "box", "widget", "module",
    "template", "layout", "wrapper", "container", "section-", "page-",
    -- Ads / promotion
    "ad", "ads", "advertisement", "banner", "promo", "sponsored",
    "affiliate", "native-ad", "taboola", "outbrain", "comscore",
    -- Social / sharing
    "social", "share", "sharing", "follow", "subscribe", "newsletter",
    "facebook", "twitter", "reddit", "linkedin", "whatsapp",
    "pinterest", "telegram", "email-this",
    -- Footer / header chrome
    "footer", "header", "top-bar", "bottom-bar", "sticky",
    "masthead", "toolbar", "action-bar", "tab-bar",
    -- Meta / utility
    "metadata", "meta", "related", "suggested", "recommended",
    "more-from", "read-next", "see-also", "sources", "citation",
    "references", "bibliography", "footnote", "footnotes", "cite",
    "edit", "talk", "history", "watchlist", "contribs",
    "print", "export", "pdf", "download", "tools", "actions",
    "language", "lang-list", "interlanguage",
    -- Specific UI patterns
    "skip-nav", "skip-link", "back-to-top", "scroll-to-top",
    "cookie", "consent", "popup", "modal", "lightbox",
    "carousel", "slider", "accordion", "tabs-", "tab-",
    "filter", "search-bar", "searchbox", "autcomplete",
    -- Wikipedia / general UI
    "jump", "link", "login", "signin", "register", "signup",
    "user", "portals", "portlet", "dock", "variant", "language",
}

-- Strip block-level non-content elements from HTML
local function strip_non_content(html)
    if not html or #html == 0 then return html end

    -- Remove <nav> semantic elements entirely
    local result = ""
    local i = 1
    while i <= #html do
        local open_start, open_end = html:find("<nav[^>]*>", i)
        if not open_start then
            result = result .. html:sub(i)
            break
        end
        local close_pos = html:find("</nav>", open_end)
        if close_pos then
            result = result .. html:sub(i, open_start - 1)
            i = close_pos + 6
        else
            result = result .. html:sub(i, open_end)
            i = open_end + 1
        end
    end
    html = result

    -- Collect all tags with non-content class/id for removal
    local tags_to_remove = {}
    i = 1
    while i <= #html do
        local tag_start_pos, tag_end_pos = html:find("<[%w_]+%s[^>]*/>", i)
        if not tag_start_pos then
            tag_start_pos, tag_end_pos = html:find("<[%w_]+%s*[^>]*>", i)
        end
        if not tag_start_pos then break end

        local tag_str = html:sub(tag_start_pos, tag_end_pos)
        local tag_lower = tag_str:lower()
        local tag_name = tag_str:match("^<([%w_]+)")

        -- Only consider block-level elements for removal
        local block_tags = {
            ["div"] = true, ["section"] = true, ["aside"] = true,
            ["header"] = true, ["footer"] = true, ["main"] = true,
            ["form"] = true, ["article"] = true, ["figure"] = true,
        }
        if not block_tags[tag_name] then
            i = tag_end_pos + 1
        else
            local is_non_content = false

            -- Check class attribute — match keywords inside class values
            local class_val = tag_lower:match('class%s*=%s*"([^"]*)"') or tag_lower:match("class%s*=%s*'([^']*)'")
            if class_val then
                -- Protect known-good structural classes (especially MediaWiki mw-* classes)
                local has_good_class = false
                for cls in class_val:gmatch("[^%s]+") do
                    local lc = cls:lower()
                    if lc:find("^mw%-") or lc == "page" or lc == "content" then
                        has_good_class = true
                        break
                    end
                end
                if has_good_class then
                    is_non_content = false
                else
                    for _, kw in ipairs(NON_CONTENT_KEYWORDS) do
                        if class_val:find(kw) then
                            is_non_content = true
                            break
                        end
                    end
                end
            end

            -- Check id attribute — keyword search
            if not is_non_content then
                local id_val = tag_lower:match('id%s*=%s*"([^"]*)"') or tag_lower:match("id%s*=%s*'([^']*)'")
                if id_val then
                    for _, kw in ipairs(NON_CONTENT_KEYWORDS) do
                        if id_val:find(kw) then
                            is_non_content = true
                            break
                        end
                    end
                end
            end

            -- Check ARIA role attribute
            if not is_non_content then
                local has_role = tag_lower:match('role%s*=%s*"([^"]*)"')
                if has_role and (has_role == "navigation" or has_role == "banner" or has_role == "complementary") then
                    is_non_content = true
                end
            end

            if is_non_content and tag_name then
                local close_tag = "</" .. tag_name:lower() .. ">"
                local close_pos = html:find(close_tag, tag_end_pos + 1)
                if close_pos then
                    tags_to_remove[#tags_to_remove + 1] = {tag_start_pos, close_pos + #close_tag}
                    i = close_pos + #close_tag
                else
                    i = tag_end_pos + 1
                end
            else
                i = tag_end_pos + 1
            end
        end
    end

    -- Remove collected tags in reverse order to preserve positions
    if #tags_to_remove > 0 then
        local result = html
        for idx = #tags_to_remove, 1, -1 do
            local s, e = tags_to_remove[idx][1], tags_to_remove[idx][2]
            result = result:sub(1, s - 1) .. result:sub(e)
        end
        html = result
    end

    return html
end

  -- Strip <style>, <script>, <link>, and SVG blocks
local function strip_decorative(html)
    if not html or #html == 0 then return html end
    local result = html

    -- Remove style blocks
    while true do
        local s, e = result:find("<style[^>]*>", 1)
        if not s then break end
        local close = result:find("</style>", e)
        if not close then break end
        result = result:sub(1, s - 1) .. result:sub(close + 8)
    end

    -- Remove script blocks
    while true do
        local s, e = result:find("<script[^>]*>", 1)
        if not s then break end
        local close = result:find("</script>", e)
        if not close then break end
        result = result:sub(1, s - 1) .. result:sub(close + 9)
    end

    -- Remove <link> tags (self-closing, no content to leak)
    while true do
        local s, e = result:find("<link[^/>]*>", 1, true)
        if not s then break end
        result = result:sub(1, s - 1) .. result:sub(e + 1)
    end

    -- Remove <meta> tags (self-closing or bare)
    while true do
        local s, e = result:find("<meta[^/>]*>", 1, true)
        if not s then break end
        result = result:sub(1, s - 1) .. result:sub(e + 1)
    end

    -- Remove <img> tags (images are not text content)
    while true do
        local s, e = result:find("<img[^/>]*>", 1, true)
        if not s then break end
        result = result:sub(1, s - 1) .. result:sub(e + 1)
    end

    -- Remove <svg> blocks (icons, decorative paths contain gibberish text)
    while true do
        local s = result:find("<svg[^>]*>", 1)
        if not s then break end
        local close = result:find("</svg>", s + 1)
        if not close then break end
        result = result:sub(1, s - 1) .. result:sub(close + 6)
    end

    -- Remove <input>, <button>, <select>, <textarea> form elements
    local form_tags = {"input", "button", "select", "textarea"}
    for _, ft in ipairs(form_tags) do
        while true do
            local s, e = result:find("<" .. ft .. "[^/>]*>", 1, true)
            if not s then break end
            result = result:sub(1, s - 1) .. result:sub(e + 1)
        end
    end

    -- Remove <hr> tags (horizontal rules are decorative)
    while true do
        local s, e = result:find("<hr[^/>]*>", 1, true)
        if not s then break end
        result = result:sub(1, s - 1) .. result:sub(e + 1)
    end

    -- Remove <br> tags (keep them as spaces for readability)
    result = result:gsub("<br[^/>]*>", " ")

    -- Remove <!-- ... --> comments
    while true do
        local s, e = result:find("<!--", 1, true)
        if not s then break end
        local close = result:find("-->", e)
        if not close then break end
        result = result:sub(1, s - 1) .. result:sub(close + 4)
    end

    return result
end

-- Strip nav/sidebar/etc elements that may be nested inside article containers.
-- This runs AFTER the main strip_non_content pass to catch anything inside
-- content divs that wasn't caught earlier (e.g., Wikipedia language menus).
local function strip_inner_nav(html)
    if not html or #html == 0 then return html end

    -- Remove any remaining <nav> elements (including role="navigation" divs)
    local result = ""
    local i = 1
    while i <= #html do
        local open_start, open_end = html:find("<nav[^>]*>", i)
        if not open_start then
            result = result .. html:sub(i)
            break
        end
        local close_pos = html:find("</nav>", open_end)
        if close_pos then
            result = result .. html:sub(i, open_start - 1)
            i = close_pos + 6
        else
            result = result .. html:sub(i, open_end)
            i = open_end + 1
        end
    end
    html = result

    -- Strip ALL <ul>/<ol> lists with substantial text inside article containers.
    -- Language menus, navigation lists, and other UI lists always have more text
    -- than the occasional bullet list in an article. This catches everything
    -- regardless of class/id names.
    local list_tags = {["ul"] = true, ["ol"] = true}

    local lists_to_remove = {}
    i = 1
    while i <= #html do
        local tag_start_pos, tag_end_pos = html:find("<[%w_]+%s[^>]*/>", i)
        if not tag_start_pos then
            tag_start_pos, tag_end_pos = html:find("<[%w_]+%s*[^>]*>", i)
        end
        if not tag_start_pos then break end

        local tag_str = html:sub(tag_start_pos, tag_end_pos)
        local tag_name = tag_str:match("^<([%w_]+)")

        if list_tags[tag_name] then
            local close_tag = "</" .. tag_name:lower() .. ">"
            local close_pos = html:find(close_tag, tag_end_pos + 1)
            if not close_pos then
                i = tag_end_pos + 1
            else
                local list_content = html:sub(tag_end_pos + 1, close_pos - 1)
                local plain = list_content:gsub("<[^>]*>", " ")
                plain = plain:gsub("^%s+", ""):gsub("%s+$", "")

                if #plain > 20 then
                    lists_to_remove[#lists_to_remove + 1] = {tag_start_pos, close_pos + #close_tag}
                end

                i = close_pos + #close_tag
            end
        else
            i = tag_end_pos + 1
        end
    end

    if #lists_to_remove > 0 then
        local result = html
        for idx = #lists_to_remove, 1, -1 do
            local s, e = lists_to_remove[idx][1], lists_to_remove[idx][2]
            result = result:sub(1, s - 1) .. result:sub(e)
        end
        html = result
    end

    return html
end

-- Count actual text characters (excluding HTML tags and whitespace-only sections)
local function count_chars(text)
    -- Remove all tags
    local plain = text:gsub("<[^>]*>", " ")
    -- Collapse whitespace
    plain = plain:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return #plain
end

-- Count paragraphs (sequences of non-empty text between blank lines or <p>/<br>/paragraph breaks)
local function count_paragraphs(text)
    local plain = text:gsub("<[^>]*>", "\n"):gsub("<!--.--->", "")
    -- Split on double newlines, <p> tags, and multiple <br> sequences
    local count = 0
    local in_para = false
    for line in plain:gmatch("[^\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed and #trimmed > 10 then
            if not in_para then
                count = count + 1
                in_para = true
            end
        else
            in_para = false
        end
    end
    return count
end

-- Calculate link-to-text ratio (lower is better for article content)
local function calc_link_ratio(content)
    local total_chars = count_chars(content)
    if total_chars == 0 then return 1.0 end

    -- Remove all links and count remaining chars
    local without_links = content:gsub("<a[^>]*>.-</a>", " ")
    local text_chars = count_chars(without_links)

    local link_chars = total_chars - text_chars
    if link_chars < 0 then link_chars = 0 end

    -- Ratio of link-characters to text-characters
    return link_chars / math.max(text_chars, 1)
end

-- Score a content container. Higher is better.
local function score_content(content)
    local chars = count_chars(content)
    local paragraphs = count_paragraphs(content)
    local link_ratio = calc_link_ratio(content)
    local raw_len = #content

    -- Must have some substance
    if chars < 100 then return 0 end

    local score = 0

    -- Total text characters (not density — size wins for article bodies)
    score = score + chars * 0.8

    -- Bonus for having multiple paragraphs (indicates real prose, not just a header)
    score = score + math.max(0, paragraphs - 1) * 30

    -- Bonus for presence of headings
    local has_h1 = content:find("<h[1][^>]*>") ~= nil
    local has_h = content:find("<h[1-6][^>]*>") ~= nil
    if has_h1 then score = score + 25 end
    if has_h then score = score + 10 end

    -- Bonus for overall container size — larger containers tend to be full articles
    -- A full article body with 30K+ chars gets a significant boost over section fragments
    if raw_len > 5000 then
        score = score + math.min(raw_len / 100, 2000)
    end

    -- Penalty for high link ratio (navigation-heavy containers)
    if link_ratio > 0.5 then
        score = score * (1 - math.min(link_ratio, 1))
    elseif link_ratio > 0.2 then
        score = score * (1 - link_ratio * 0.3)
    end

    return score
end

-- Extract the text content of a tag given its opening position
local function extract_tag_content(html, tag_open_pos)
    local gt_pos = html:find(">", tag_open_pos)
    if not gt_pos then return nil end

    local tag_str = html:sub(tag_open_pos, gt_pos)
    local tag_name = tag_str:match("^<([%w_]+)")
    if not tag_name then return nil end

    local content_start = gt_pos + 1
    local depth = 1
    local pos = content_start

    -- Handle nesting by counting opening vs closing tags
    while depth > 0 do
        local open_tag = html:find(string.format("<%s[^a-zA-Z/]", tag_name), pos)
        local close_tag = html:find("</" .. tag_name .. ">", pos)

        if not close_tag then return nil end

        if open_tag and open_tag < close_tag then
            depth = depth + 1
            pos = open_tag + 1
        else
            depth = depth - 1
            if depth == 0 then
                return html:sub(content_start, close_tag - 1), tag_str
            end
            pos = close_tag + 1
        end
    end
end

-- Find the best content container in the HTML
local function find_best_container(html)
    local best_score = 0
    local best_content = nil
    local best_title = ""

    -- Generic article-like class patterns (without Wikipedia specifics)
    local class_patterns = {
        "article-body", "articlebody", "article__body", "article_body",
        "entry-content", "entrycontent", "post-body", "postbody",
        "story-body", "storybody", "content-body", "contentbody",
        "post-content", "postcontent", "blog-post", "articulo",
        "article-content", "main-content", "page-content",
        "text-content", "full-article", "entry-body",
        -- Ghost / modern blog platforms
        "post-content", "gh-article", "c-entry-content",
        -- WordPress common themes
        "entry-content", "post-content", "article__content",
        -- Medium-like
        "pr-content", "rich-text",
        -- Wikipedia / Wikimedia specific
        "mw-body-content", "mw-parser-output", "mw-content-ltr",
    }

    -- Generic article-like id patterns
    local id_patterns = {
        "article-body", "articlebody", "storytext", "post_content",
        "article-content", "main-article", "article-text",
        "mw-content-text", "contentText",
        "postbody", "storybody", "post-content",
        "entry-content", "main-content", "page-content",
    }

    -- Wikipedia-specific: these classes are the actual article content containers.
    -- mw-parser-output is where prose lives on all Wikimedia wikis.
    local wikipedia_patterns = {
        class_patterns = {"mw-parser-output"},
        id_patterns = {"content-text"},
    }

    -- Search by class patterns
    for _, pat in ipairs(class_patterns) do
        local escaped = pat:gsub("%%", "%%%%")
        local pattern = 'class="[^"]*' .. escaped
        local start = html:find(pattern)
        if not start then
            pattern = "class='[^']*" .. escaped
            start = html:find(pattern)
        end
        if start then
            local search_start = math.max(1, start - 200)
            for p = start - 1, search_start, -1 do
                if html:sub(p, p) == "<" then
                    local content, tag_str = extract_tag_content(html, p)
                    if content then
                        local s = score_content(content)
                        if s > best_score then
                            best_score = s
                            best_content = content
                            best_title = content:match("<h[1-6][^>]*>(.-)</h[1-6]>") or best_title
                        end
                    end
                    break
                end
            end
        end
    end

    -- Search by id patterns
    for _, pat in ipairs(id_patterns) do
        local escaped = pat:gsub("%%", "%%%%")
        local pattern = 'id="[^"]*' .. escaped
        local start = html:find(pattern)
        if not start then
            pattern = "id='[^']*" .. escaped
            start = html:find(pattern)
        end
        if start then
            local search_start = math.max(1, start - 200)
            for p = start - 1, search_start, -1 do
                if html:sub(p, p) == "<" then
                    local content, tag_str = extract_tag_content(html, p)
                    if content then
                        local s = score_content(content)
                        if s > best_score then
                            best_score = s
                            best_content = content
                            best_title = content:match("<h[1-6][^>]*>(.-)</h[1-6]>") or best_title
                        end
                    end
                    break
                end
            end
        end
    end

    -- Wikipedia-specific: mw-parser-output is the article content container.
    -- Check this FIRST with highest priority — it contains ALL article prose,
    -- tables, figures etc. This must run before generic pattern matching.
    local wp_found = false
    for _, pat in ipairs(wikipedia_patterns.class_patterns) do
        local pattern = 'class="[^"]*' .. pat
        local start = html:find(pattern)
        if not start then
            pattern = "class='[^']*" .. pat
            start = html:find(pattern)
        end
        if start then
            local search_start = math.max(1, start - 200)
            for p = start - 1, search_start, -1 do
                if html:sub(p, p) == "<" then
                    local content, _ = extract_tag_content(html, p)
                    if content then
                        best_score = score_content(content) + 10000
                        best_content = content
                        best_title = content:match("<h[1-6][^>]*>(.-)</h[1-6]>") or best_title
                    end
                    wp_found = true
                end
                break
            end
        end
    end

    -- Only run generic patterns if Wikipedia pattern was found (Wikipedia pages
    -- have many nested divs with article-like names that would confuse generic matching)
    if not wp_found then
        -- Search by class patterns
        for _, pat in ipairs(class_patterns) do
            local escaped = pat:gsub("%%", "%%%%")
            local pattern = 'class="[^"]*' .. escaped
            local start = html:find(pattern)
            if not start then
                pattern = "class='[^']*" .. escaped
                start = html:find(pattern)
            end
            if start then
                local search_start = math.max(1, start - 200)
                for p = start - 1, search_start, -1 do
                    if html:sub(p, p) == "<" then
                        local content, tag_str = extract_tag_content(html, p)
                        if content then
                            local s = score_content(content)
                            if s > best_score then
                                best_score = s
                                best_content = content
                                best_title = content:match("<h[1-6][^>]*>(.-)</h[1-6]>") or best_title
                            end
                        end
                        break
                    end
                end
            end
        end

        -- Search by id patterns
        for _, pat in ipairs(id_patterns) do
            local escaped = pat:gsub("%%", "%%%%")
            local pattern = 'id="[^"]*' .. escaped
            local start = html:find(pattern)
            if not start then
                pattern = "id='[^']*" .. escaped
                start = html:find(pattern)
            end
            if start then
                local search_start = math.max(1, start - 200)
                for p = start - 1, search_start, -1 do
                    if html:sub(p, p) == "<" then
                        local content, tag_str = extract_tag_content(html, p)
                        if content then
                            local s = score_content(content)
                            if s > best_score then
                                best_score = s
                                best_content = content
                                best_title = content:match("<h[1-6][^>]*>(.-)</h[1-6]>") or best_title
                            end
                        end
                        break
                    end
                end
            end
        end
    end

    -- Fallback 1: <article> tag (semantic HTML5)
    if not best_content then
        local art_start = html:find("<article[^>]*>")
        if art_start then
            local content, _ = extract_tag_content(html, art_start)
            if content then
                best_score = score_content(content)
                best_content = content
                best_title = content:match("<h[1-6][^>]*>(.-)</h[1-6]>") or best_title
            end
        end
    end

    -- Fallback 1b: <main> tag (common on modern sites)
    if not best_content then
        local main_start = html:find("<main[^>]*>")
        if main_start then
            local content, _ = extract_tag_content(html, main_start)
            if content then
                -- Extract paragraphs from <main> to avoid nav/footer contamination
                local all_paras = {}
                local para_count = 0
                local pos = 1
                while true do
                    local p_start = content:find("<p[^>]*>", pos)
                    if not p_start then break end
                    local p_close = content:find("</p>", p_start + 1)
                    if not p_close then break end

                    local para_content = content:sub(p_start + 2, p_close - 1)
                    local plain = para_content:gsub("<[^>]*>", " ")
                    plain = plain:gsub("^%s+", ""):gsub("%s+$", "")
                    local text_chars = #plain
                    local has_periods = plain:find("%.+") and 1 or 0
                    local alpha_ratio = (#plain:gsub("[^a-zA-Z]", "")) / math.max(text_chars, 1)

                    if text_chars > 80 and has_periods > 0 and alpha_ratio > 0.3 then
                        table.insert(all_paras, plain)
                        para_count = para_count + 1
                    end
                    pos = p_close + 4
                end

                if para_count >= 2 then
                    local combined = ""
                    for i, plain in ipairs(all_paras) do
                        if i > 1 then combined = combined .. "\n\n" end
                        combined = combined .. "<p>" .. plain .. "</p>"
                    end
                    best_content = combined
                    best_score = score_content(combined) * 0.8
                else
                    -- Fall back to full <main> content with reduced score
                    best_score = score_content(content) * 0.5
                    best_content = content
                    best_title = content:match("<h[1-6][^>]*>(.-)</h[1-6]>") or best_title
                end
            end
        end
    end

    -- Fallback 2: <body> tag — collect all meaningful article paragraphs
    if not best_content then
        local body_start, body_end = html:find("<body[^>]*>")
        if body_start then
            local close_pos = html:find("</body>", body_end)
            if close_pos then
                local body_content = html:sub(body_end + 1, close_pos - 1)
                -- Extract title from <title> tag in the head
                local title_match = html:match("<title>(.-)</title>")
                if title_match and #title_match > 3 then
                    best_title = title_match
                end

                -- Find article section by looking for <h1> heading,
                -- then collect all substantial paragraphs after it.
                -- This handles modern sites (Astro, Next.js) that lack
                -- semantic article class names like "article-body".
                local h1_pos = html:find("<h[1][^>]*>")
                if h1_pos and h1_pos > body_start then
                    local article_start = h1_pos
                    local article_end = math.min(h1_pos + 200000, close_pos)

                    -- Collect all substantial paragraphs from the article area
                    local all_paras = {}
                    local para_count = 0
                    local total_text = 0
                    local pos = article_start
                    while pos < article_end do
                        local p_start = html:find("<p[^>]*>", pos)
                        if not p_start or p_start >= article_end then break end
                        local p_close = html:find("</p>", p_start + 1)
                        if not p_close or p_close > article_end then break end

                        local para_content = html:sub(p_start + 2, p_close - 1)
                        local plain = para_content:gsub("<[^>]*>", " ")
                        plain = plain:gsub("^%s+", ""):gsub("%s+$", "")

                        -- Score this paragraph as prose vs noise
                        local text_chars = #plain
                        local has_periods = plain:find("%.+") and 1 or 0
                        local has_commas = plain:find(",") and 1 or 0
                        local alpha_ratio = (#plain:gsub("[^a-zA-Z]", "")) / math.max(text_chars, 1)

                        -- Prose heuristic: must have text content with punctuation (not JS/HTML noise)
                         if text_chars > 80 and has_periods > 0 and alpha_ratio > 0.3 then
                             table.insert(all_paras, plain)
                             para_count = para_count + 1
                             total_text = total_text + text_chars
                         end

                         pos = p_close + 4
                     end

                     if para_count >= 2 then
                         -- Combine all good paragraphs into one content block,
                         -- wrapping each in <p> tags so Phase 4 extraction works
                         local combined = ""
                         for i, plain in ipairs(all_paras) do
                             if i > 1 then combined = combined .. "\n\n" end
                             combined = combined .. "<p>" .. plain .. "</p>"
                         end
                        best_content = combined
                        best_score = score_content(combined)
                    end
                end

                -- If still nothing, fall back to collecting ALL substantial p tags from body
                if not best_content then
                    local all_paras2 = {}
                    local para_count2 = 0
                    local pos2 = body_start
                    while true do
                        local p_start = html:find("<p[^>]*>", pos2)
                        if not p_start then break end
                        local p_close = html:find("</p>", p_start + 1)
                        if not p_close then break end

                        local para_content = html:sub(p_start + 2, p_close - 1)
                        local plain = para_content:gsub("<[^>]*>", " ")
                        plain = plain:gsub("^%s+", ""):gsub("%s+$", "")

                        if #plain > 80 then
                            -- Check it looks like prose (has alpha chars and punctuation)
                            local has_periods = plain:find("%.+") and 1 or 0
                            local alpha_ratio = (#plain:gsub("[^a-zA-Z]", "")) / math.max(#plain, 1)
                            if has_periods > 0 and alpha_ratio > 0.3 then
                                table.insert(all_paras2, plain)
                                para_count2 = para_count2 + 1
                            end
                        end
                        pos2 = p_close + 4
                    end

                    if para_count2 >= 2 then
                        local combined2 = ""
                        for i, plain in ipairs(all_paras2) do
                            if i > 1 then combined2 = combined2 .. "\n\n" end
                            combined2 = combined2 .. "<p>" .. plain .. "</p>"
                        end
                        best_content = combined2
                        best_score = score_content(combined2)
                    end
                end
            end
        end
    end

    if not best_content then
        return nil, ""
    end

    return best_content, best_title
end

function _M.fetch_and_extract(article_url)
    local body = http_fetch.http_get(article_url)
    if not body or #body == 0 then
        return nil, ""
    end

    -- Save original body for fallback extraction.
    -- Phase 1+ can destroy structure needed to find the article container.
    local raw_body = body

    -- Phase 1: Strip all non-content elements (menus, ads, sidebars, etc.)
    body = strip_non_content(body)

    -- Phase 2: Remove decorative HTML (style, script, img, hr, br, comments)
    body = strip_decorative(body)

    -- Phase 3: Find and extract the best content container
    local content, title = find_best_container(body)

    if not content then
        return nil, ""
    end

    -- Phase 4: Remove non-prose elements from inside the content container.
    -- On Wikipedia, infoboxes are <table> elements (not <div>s), so we remove
    -- tables with infobox/navbox class. We also strip nav/hatnote divs that
    -- contain only links and no prose paragraphs.

    -- Remove non-prose <table> elements (infoboxes, navboxes, etc.)
    local table_nav_keywords = {
        "infobox", "navbox", "metadata", "vegan", "ambox", "tmbox",
        "cmbox", "fmbox", "dmbox", "sister-project", "short description",
    }
    pos = 1
    while true do
        local s, e = content:find("<table[^>]*>", pos)
        if not s then break end
        local class_val = content:sub(s, e):lower():match('class%s*=%s*"([^"]*)"') or
                          content:sub(s, e):lower():match("class%s*=%s*'([^']*)'")
        local id_val = content:sub(s, e):lower():match('id%s*=%s*"([^"]*)"') or
                       content:sub(s, e):lower():match("id%s*=%s*'([^']*)'")
        if class_val or id_val then
            local is_nav = false
            for _, kw in ipairs(table_nav_keywords) do
                if (class_val and class_val:find(kw)) or (id_val and id_val:find(kw)) then
                    is_nav = true
                    break
                end
            end
            if is_nav then
                local close = content:find("</table>", e)
                if close then
                    content = content:sub(1, s - 1) .. content:sub(close + 8)
                    goto skip_table
                end
            end
        end
        pos = e + 1
        ::skip_table::
    end

    -- Remove <div> elements that are clearly non-prose (hatnotes, nav templates)
    local div_nav_keywords = {
        "hatnote", "disambig", "navbox", "sidebar", "stub", "clean-up",
        "more-citations-needed", "citation needed", "when-", "by whom",
    }
    pos = 1
    while true do
        local s, e = content:find("<div[^>]*>", pos)
        if not s then break end
        local class_val = content:sub(s, e):lower():match('class%s*=%s*"([^"]*)"') or
                          content:sub(s, e):lower():match("class%s*=%s*'([^']*)'")
        local id_val = content:sub(s, e):lower():match('id%s*=%s*"([^"]*)"') or
                       content:sub(s, e):lower():match("id%s*=%s*'([^']*)'")
        if class_val or id_val then
            local is_nav = false
            for _, kw in ipairs(div_nav_keywords) do
                if (class_val and class_val:find(kw)) or (id_val and id_val:find(kw)) then
                    is_nav = true
                    break
                end
            end
            if is_nav then
                local close = content:find("</div>", e)
                if close then
                    content = content:sub(1, s - 1) .. content:sub(close + 6)
                    goto skip_div
                end
            end
        end
        pos = e + 1
        ::skip_div::
    end

    -- Extract ALL <p> tag content from the article container.
    -- mw-parser-output contains paragraphs as direct children — we collect them all.
    result = ""
    pos = 1
    while true do
        local p_start = content:find("<p[^>]*>", pos)
        if not p_start then break end
        local p_close = content:find("</p>", p_start)
        if not p_close then break end

        -- Extract raw text between <p> and </p>, stripping inner HTML tags
        local para_text = content:sub(p_start + 2, p_close - 1)
        para_text = para_text:gsub("<[^>]*>", " ")
        para_text = para_text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

        -- Skip reference links and citation markers (e.g. "^[1]", "[edit]")
        local plain_check = para_text:gsub("[%u%p%s]", "")
        if #plain_check < 5 then
            pos = p_close + 4
            goto next_para
        end

        result = result .. (result ~= "" and "\n\n" or "") .. para_text
        ::next_para::
        pos = p_close + 4
    end

    -- If no paragraphs found, fall back to stripped container content.
    if result == "" then
        local allowed_tags = "<p><a><strong><b><em><i><blockquote><pre><code>"
            .. "<h1><h2><h3><h4><h5><h6><ul><ol><li><sup><sub><br><kbd><var><samp>"
        local stripped = html_utils.strip_tags(content, allowed_tags)
        result = string_utils.clean_str(stripped)
    else
        result = string_utils.clean_str(result)
    end

    return result, title
end

return _M
