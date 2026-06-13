local _M = {}

function _M.clean_str(str)
    if not str then return "" end
    str = str:gsub("\226\128\171", "'")
    str = str:gsub("\226\128\173", "'")
    str = str:gsub("\226\128\174", '"')
    str = str:gsub("\226\128\175", '"')
    str = str:gsub("\226\132\146", "-")
    str = str:gsub("&#x27;", "'")
    str = str:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
        :gsub("&quot;", '"'):gsub("&#39;", "'")
    return str
end

function _M.url_decode(str)
    if not str then return "" end
    str = str:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    str = str:gsub("%+", " ")
    return str
end

return _M
