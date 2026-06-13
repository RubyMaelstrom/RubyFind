local string_utils = require "RubyFind.string_util"
local http_fetch = require "RubyFind.http_fetch"

local function log(level, msg)
    ngx.log(level, "[RubyFind] " .. tostring(msg))
end

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
    log(ngx.ERR, "=== HANDLER START ===")

    local query = get_param("q")

    if not query then
        -- Homepage - no query
        local out = {
            '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 2.0//EN">',
            '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">',
            '<body bgcolor="#2d2d2d" text="#ffffff" link="#ff69b4" vlink="#87ceeb">',
            '    <br><br><center><h1><font size=7><font color="#ff69b4">Ruby</font><font color="#4a90d9">Find!</font></font></h1>',
            '    <center><h3>The Search Engine for Text Enthusiasts</h3></center>',
            '    <br><br>',
            '    <center>',
            '    <form action="/search" method="get">',
            '    Leap to: <input type="text" size="30" name="q"> <input type="submit" value="Find!">',
            '    </center></center>',
            '    <br><br><br>',
            '    <center><small>Built by <b><a href="https://youtube.com/ActionRetro">Action Retro</a></b> on YouTube, updated by <b><a href="https://www.rubymaelstrom.com/">Ruby</a></b> to Lua.</small><br>',
            '    <small>Powered by DuckDuckGo</small></center>'
        }

        send_response(200, table.concat(out))
        return
    end

    -- URL encoding: convert + to space (nginx doesn't decode + as space)
    local decoded_query = query:gsub("%+", " ")
    local encoded_query = ngx.escape_uri(decoded_query)

    -- Fetch DuckDuckGo HTML search results
    local search_url = "https://html.duckduckgo.com/html/?q=" .. encoded_query
    local html_response = http_fetch.http_get(search_url, 15000)

    if not html_response or #html_response == 0 then
        local out = {
            '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 2.0//EN">',
            '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">',
            '<body bgcolor="#2d2d2d" text="#ffffff" link="#ff69b4" vlink="#87ceeb">',
            '    <center>',
            '    <form action="/search" method="get">',
            '    <a href="/search"><font size=6 color="#ff69b4">Ruby</font><font size=6 color="#4a90d9">Find!</font></a> Leap again: <input type="text" size="30" name="q" value="' .. string_utils.clean_str(decoded_query) .. '"> <input type="submit" value="Find!">',
            '    </form>',
            '    <hr><br>',
            '    <center>Search Results for <b>' .. string_utils.clean_str(decoded_query) .. '</b></center>',
            '    </center><br><br>Failed to get results from DuckDuckGo.'
        }
        send_response(200, table.concat(out))
        return
    end

    -- Parse HTML results: extract title + URL from each result__a tag
    local items = {}

    html_response:gsub('class="result__a"[^>]*href="(//duckduckgo%.com/l/[^"%s]+)"[^>]*>([^<]*)', function(href, title_text)
        -- Extract uddg value (URL-encoded destination)
        local uddg_val = href:match("uddg=([^&]+)")
        if not uddg_val then return end

        local real_url = string_utils.url_decode(uddg_val)

        -- Skip ads (duckduckgo.com/y.js redirect links)
        if real_url:find("duckduckgo%.com/y%.js") then return end

        table.insert(items, { Text = string_utils.clean_str(title_text), URL = real_url })
    end)

    -- Limit to 20 results
    if #items > 20 then
        for i = 21, #items do
            items[i] = nil
        end
    end

    -- Build result HTML
    local result_html = ""
    for _, item in ipairs(items) do
        local title = string_utils.clean_str(item.Text or "")
        local url = item.URL or ""

        -- Escape HTML entities
        title = title:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
        url = url:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")

        local proxy_url = "/search/read?a=" .. url

        result_html = result_html ..
            "<br><a href='" .. proxy_url .. "'><font size='4'><b>" .. title .. "</b></font><br>" ..
            "<font color='#4a90d9' size='2'>" .. url .. "</font></a><br><br><hr>"
    end

    -- Build output
      local decoded = string_utils.clean_str(decoded_query)
    local out = {
        '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 2.0//EN">',
        '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">',
        '<body bgcolor="#2d2d2d" text="#ffffff" link="#ff69b4" vlink="#87ceeb">',
        '    <center>',
        '    <form action="/search" method="get">',
        '    <a href="/search"><font size=6 color="#ff69b4">Ruby</font><font size=6 color="#4a90d9">Find!</font></a> Leap again: <input type="text" size="30" name="q" value="' .. decoded .. '"> <input type="submit" value="Find!">',
        '    </form>',
        '    <hr><br>',
        '    <center>Search Results for <b>' .. decoded .. '</b></center>',
        '    </center>',
        '    <br>',
        '    ' .. result_html,
        '</body>'
    }

    send_response(200, table.concat(out))
end

local ok, err = pcall(handle)
if not ok then
    ngx.header["Content-Type"] = "text/html; charset=utf-8"
    ngx.status = 502
    local out = {
        '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 2.0//EN">',
        '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">',
        '<body bgcolor="#2d2d2d" text="#ffffff" link="#ff69b4" vlink="#87ceeb">',
        '    <center><h1><font color="#ff69b4">Ruby</font><font color="#4a90d9">Find!</font></h1></center>',
        '    <hr>Error: ' .. tostring(err)
    }
    ngx.say(table.concat(out))
    ngx.exit(ngx.OK)
end
