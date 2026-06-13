local string_utils = require "RubyFind.string_util"
local html_utils = require "RubyFind.html"
local http_fetch = require "RubyFind.http_fetch"
local article_extract = require "RubyFind.article_extract"

local function send_response(status_code, body)
    ngx.status = status_code
    ngx.header["Content-Type"] = "text/html; charset=utf-8"
    if status_code >= 400 then
        ngx.header["X-Robots-Tag"] = "noindex, nofollow"
    end
    ngx.say(body)
    ngx.exit(ngx.OK)
end

local function get_param(name)
    local val = ngx.var["arg_" .. name]
    if val then return val end
    return nil
end

local function handle()
    ngx.header["X-Robots-Tag"] = "noindex, nofollow"

    local article_url = get_param("a") or ""
    if not article_url or article_url == "" then
        send_response(400, 'What do you think you\'re doing... >;(')
        return
    end

    if article_url:sub(1, 4) ~= "http" then
        send_response(400, "That's not a web page :(")
        return
    end

    local url = article_url
    local host = url:match("https?://([^/]+)") or ""

    -- Check content type via HEAD request
    local timeout_s = 15000 / 1000
    local head_cmd = string.format(
        'curl -sS --max-time %d -I -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" "%s"',
        timeout_s,
        article_url
    )
    local head_reader = io.popen(head_cmd, "r")
    local headers_body = ""
    if head_reader then
        headers_body = head_reader:read("*a")
        head_reader:close()
    end

    local compatible_types = {"text/html", "text/plain"}
    local content_type = headers_body:match("Content%-Type:%s*(.-)\r\n") or ""
    local content_length = tonumber(headers_body:match("Content%-Length:%s*(%d+)")) or 0

    -- Handle non-compatible content types as downloads
    if content_type ~= "" and not compatible_types[content_type] then
        if content_length > 8000000 then
            send_response(413, 'Failed to proxy file download, it\'s too large. :( <br>You can try downloading the file directly: ' .. article_url)
            return
        end

        local filename = article_url:match("/([^?]+)$") or "download"
        -- Remove query string from filename
        filename = filename:match("([^?]+)")

        ngx.header["Content-Type"] = content_type
        ngx.header["Content-Length"] = tostring(content_length)
        ngx.header["Content-Disposition"] = 'attachment; filename="' .. filename .. '"'

        local fetch_cmd = string.format(
            'curl -sS --max-time %d -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" "%s"',
            timeout_s,
            article_url
        )
        local reader = io.popen(fetch_cmd, "r")
        if reader then
            while true do
                local chunk = reader:read(8192)
                if not chunk then break end
                ngx.print(chunk)
            end
            reader:close()
        end
        ngx.exit(ngx.OK)
        return
    end

    -- Extract article content
    local readable_article, title = article_extract.fetch_and_extract(article_url)

    if not readable_article or readable_article == "" then
        send_response(500, 'Sorry! Failed to extract article content.<br>')
        return
    end

    readable_article = string_utils.clean_str(readable_article)
    readable_article = readable_article:gsub("strong>", "b>"):gsub("em>", "i>")

    -- Strip leftover HTML attributes (class, id, style) — these leak through tag stripping
    readable_article = readable_article:gsub('class="[^"]*"', "")
    readable_article = readable_article:gsub("id=\"[^\"]*\"", "")
    readable_article = readable_article:gsub("style=\"[^\"]*\"", "")
    readable_article = readable_article:gsub("class='[^']*'", "")
    readable_article = readable_article:gsub("id='[^']*'", "")
    readable_article = readable_article:gsub("style='[^']*'", "")
    -- Remove breadcrumb and FAQ schema markers
    readable_article = readable_article:gsub("breadcrumbs", ""):gsub("schema-faq-answer", "")

    -- Remove leading > from blockquote paragraphs (per-line)
    local cleaned = ""
    for line in readable_article:gmatch("[^\n]+") do
      line = line:gsub("^%s*>%s?", "")
      cleaned = cleaned .. (cleaned ~= "" and "\n" or "") .. line
    end
    readable_article = cleaned

    -- Normalize spacing: collapse multiple spaces, ensure paragraph breaks
    readable_article = readable_article:gsub("%s+", " ")  -- collapse spaces
    readable_article = readable_article:gsub("([.!?])%s+([A-Z])", "%1\n\n%2")  -- add breaks after sentences
    readable_article = readable_article:gsub("\n\n", "<br><br>")

    -- Route internal links through our proxy
    readable_article = readable_article:gsub('href="http', 'href="/search/read?a=http')

    local page_title = string_utils.clean_str(title or "RubyFind Article")

    local out = {}
    out[#out + 1] = '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 2.0//EN">'
    out[#out + 1] = '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">'
    out[#out + 1] = '<body bgcolor="#2d2d2d" text="#ffffff" link="#ff69b4" vlink="#87ceeb">'

    out[#out + 1] = '   <center>'
    out[#out + 1] = '   <small><a href="/search"> < Back to <font color="#ff69b4">Ruby</font><font color="#4a90d9">Find!</font></a></small>'
    out[#out + 1] = '   <form action="/search/read" method="get">'
    out[#out + 1] = '   Browsing URL: <input type="text" size="38" name="a" value="' .. article_url .. '"> <input type="submit" value="Find!">'
    out[#out + 1] = '   </form>'
    out[#out + 1] = '   </center>'
    out[#out + 1] = '   <hr>'
    out[#out + 1] = '   <h1>' .. page_title .. '</h1>'
    out[#out + 1] = '   <p><font size="4">' .. readable_article .. '</font></p>'
    out[#out + 1] = '   <center><small><a href="/search"> < Back to <font color="#ff69b4">Ruby</font><font color="#4a90d9">Find!</font></a></small></center>'

    out[#out + 1] = '</body>'

    send_response(200, table.concat(out))
end

local ok, err = pcall(handle)
if not ok then
    ngx.header["Content-Type"] = "text/html; charset=utf-8"
    ngx.status = 502
    ngx.say("<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 2.0//EN\"><meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\"><body bgcolor=\"#2d2d2d\" text=\"#ffffff\" link=\"#ff69b4\" vlink=\"#87ceeb\"><center><h1><font color=\"#ff69b4\">Ruby</font><font color=\"#4a90d9\">Find!</font></h1></center><hr>Error: " .. tostring(err) .. "</body>")
    ngx.exit(ngx.OK)
end
