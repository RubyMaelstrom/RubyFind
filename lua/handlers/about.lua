local string_utils = require "RubyFind.string_util"

local function send_response(status_code, body)
    ngx.status = status_code
    ngx.header["Content-Type"] = "text/html; charset=utf-8"
    if status_code >= 400 then
        ngx.header["X-Robots-Tag"] = "noindex, nofollow"
    end
    ngx.say(body)
    ngx.exit(ngx.OK)
end

local function handle()
    local out = {}
    out[#out + 1] = '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 2.0//EN">'
    out[#out + 1] = '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">'
    out[#out + 1] = '<html><head>'
    out[#out + 1] = '\t<title>RubyFind!</title>'
    out[#out + 1] = '</head><body bgcolor="#2d2d2d" text="#ffffff" link="#ff69b4" vlink="#87ceeb">'

    out[#out + 1] = '    <center>'
    out[#out + 1] = '    <form action="/search" method="get">'
    out[#out + 1] = '    <a href="/search"><font size=6 color="#ff69b4">Ruby</font><font size=6 color="#4a90d9">Find!</font></a> Leap again: <input type="text" size="30" name="q"> <input type="submit" value="Find!">'
    out[#out + 1] = '    </form>'
    out[#out + 1] = '    </center>'
    out[#out + 1] = '    <hr><br>'

    out[#out + 1] = '    <center>'
    out[#out + 1] = '    <h1>What in the world is RubyFind?</h1>'
    out[#out + 1] = '    <small>A quick FAQ on an unconventional search engine</small>'
    out[#out + 1] = '    </center>'
    out[#out + 1] = '    <br>'

    out[#out + 1] = '    <h3>Who made RubyFind?</h3>'
    out[#out + 1] = '    Hi, I\'m Sean, A.K.A. <a href="https://youtube.com/ActionRetro">Action Retro</a> on YouTube. I work on a lot of 80\'s and 90\'s Macs (and other vintage machines), and I really like to try and get them online. However, the modern internet is not kind to old machines, which generally cannot handle the complicated javascript, CSS, and encryption that modern sites have. However, they can browse basic websites just fine. So I decided to see how much of the internet I could turn into basic websites, so that old machines can browse the modern internet once again!'

    out[#out + 1] = '    <h3>How does RubyFind work?</h3>'
    out[#out + 1] = '    The search functionality of RubyFind is basically a custom wrapper for DuckDuckGo search, converting the results to extremely basic HTML that old browsers can read. When clicking through to pages from search results, those pages are processed through a custom content extraction engine (similar to Mozilla\'s Readability), which extracts the main article content. I then further strip down the results to be as basic HTML as possible.'

    out[#out + 1] = '    <h3>What machines do you test RubyFind on?</h3>'
    out[#out + 1] = '    I designed RubyFind with classic Macs in mind, so I\'ve been testing on my SE/30 to make sure it looks good in 1 bit color with a 512x384 resolution. Most of my testing has been on Netscape 1.1N and 2.0.2, as well as a few 68k Mac versions of iCab. RubyFind should also work great on any text-based web browser!'

    out[#out + 1] = '    <h3>How can I get in touch with you?</h3>'
    out[#out + 1] = '    Send me an email! <a href="mailto:actionretro@pm.me">actionretro@pm.me</a>'

    out[#out + 1] = '</body></html>'

    send_response(200, table.concat(out))
end

local ok, err = pcall(handle)
if not ok then
    ngx.header["Content-Type"] = "text/html; charset=utf-8"
    ngx.status = 502
    ngx.say("<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 2.0//EN\"><meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\"><body bgcolor=\"#2d2d2d\" text=\"#ffffff\" link=\"#ff69b4\" vlink=\"#87ceeb\"><center><h1><font color=\"#ff69b4\">Ruby</font><font color=\"#4a90d9\">Find!</font></h1></center><hr>Error: " .. tostring(err) .. "</body>")
    ngx.exit(ngx.OK)
end
