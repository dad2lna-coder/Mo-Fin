sub init()
    m.top.functionName = "run"
end sub

sub run()
    method = m.top.method
    if method = invalid or method = "" then method = "GET"
    body = m.top.body
    if body = invalid then body = ""
    token = m.top.token
    if token = invalid then token = ""
    tokenHeader = m.top.tokenHeader
    if tokenHeader = invalid then tokenHeader = ""
    result = httpRequest(m.top.url, method, body, token, tokenHeader)
    m.top.code = result.code
    m.top.response = result.body
    m.top.error = result.error
    m.top.done = true
end sub
