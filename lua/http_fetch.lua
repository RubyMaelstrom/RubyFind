local _M = {}

function _M.http_get(url, timeout_ms)
    local timeout = (timeout_ms or 15000) / 1000
    local cmd = string.format(
        'curl -sS --max-time %d -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" "%s"',
        timeout,
        url
    )

    local reader = io.popen(cmd, "r")
    if not reader then
        return nil
    end

    local body = reader:read("*a")
    reader:close()

    if not body or #body == 0 then
        return nil
    end

    return body
end

return _M
