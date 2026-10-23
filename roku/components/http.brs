function joinUrl(base as string, path as string) as string
    if base = invalid then base = ""
    if path = invalid then path = ""
    b = base.Trim()
    p = path.Trim()
    if b.Right(1) <> "/" then b = b + "/"
    if p.Left(1) = "/" then p = p.Mid(1)
    return b + p
end function

function httpRequest(url as string, method as string, body as string, token as string, tokenHeader as dynamic) as object
    result = { code: 0, body: "", error: "" }
    xfer = CreateObject("roUrlTransfer")
    if xfer = invalid then
        result.error = "No HTTP client"
        return result
    end if
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.InitClientCertificates()
    xfer.EnablePeerVerification(true)
    xfer.EnableHostVerification(true)
    xfer.SetUrl(url)
    xfer.AddHeader("Accept", "*/*")
    if token <> invalid and token <> "" then
        headerName = "Authorization"
        headerValue = "Bearer " + token
        if tokenHeader <> invalid and tokenHeader <> "" then
            headerName = tokenHeader
            headerValue = token
        end if
        xfer.AddHeader(headerName, headerValue)
    end if
    xfer.SetMinimumTransferRate(100, 45)
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    started = false
    if method = "POST" then
        xfer.AddHeader("Content-Type", "application/json")
        started = xfer.AsyncPostFromString(body)
    else
        if method = "DELETE" then xfer.SetRequest("DELETE")
        started = xfer.AsyncGetToString()
    end if
    if started <> true then
        result.error = "HTTP start failed"
        return result
    end if
    ' The code and body live on the event. roUrlTransfer has neither.
    elapsed = CreateObject("roTimespan")
    elapsed.Mark()
    while true
        left = 120000 - elapsed.TotalMilliseconds()
        if left < 1 then
            xfer.AsyncCancel()
            result.error = "HTTP timeout"
            return result
        end if
        msg = wait(left, port)
        if type(msg) = "roUrlEvent" and msg.GetInt() = 1 then
            result.code = msg.GetResponseCode()
            fetched = msg.GetString()
            if type(fetched) = "String" or type(fetched) = "roString" then result.body = fetched
            exit while
        else if msg = invalid then
            xfer.AsyncCancel()
            result.error = "HTTP timeout"
            return result
        end if
    end while
    xfer.AsyncCancel()
    if result.code < 200 or result.code >= 300 then
        if result.error = "" then result.error = "HTTP " + result.code.ToStr()
    end if
    return result
end function

function peekMemberHeader(url as string) as string
    if url = invalid or url = "" then return ""
    xfer = CreateObject("roUrlTransfer")
    if xfer = invalid then return ""
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.InitClientCertificates()
    xfer.EnablePeerVerification(true)
    xfer.EnableHostVerification(true)
    xfer.SetUrl(url)
    xfer.AddHeader("Accept", "*/*")
    xfer.AddHeader("Range", "bytes=0-1023")
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    if xfer.AsyncGetToString() <> true then
        xfer.AsyncCancel()
        return ""
    end if
    msg = wait(4000, port)
    member = ""
    if type(msg) = "roUrlEvent" then
        member = memberFromHeaders(msg.GetResponseHeaders())
    end if
    xfer.AsyncCancel()
    return member
end function

function memberFromHeaders(headers as object) as string
    if headers = invalid then return ""
    if type(headers) <> "roAssociativeArray" then return ""
    keys = headers.Keys()
    if keys = invalid then return ""
    for each key in keys
        if key = invalid then continue for
        if LCase(key) = "x-mofin-member" then
            value = headers[key]
            if value = invalid then return ""
            return value.ToStr().Trim()
        end if
    end for
    return ""
end function
