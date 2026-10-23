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
    if method = "POST" then
        xfer.SetRequest("POST")
        xfer.AddHeader("Content-Type", "application/json")
        posted = xfer.PostFromString(body)
        if type(posted) = "String" or type(posted) = "roString" then result.body = posted
    else
        if method = "DELETE" then xfer.SetRequest("DELETE")
        fetched = xfer.GetToString()
        if type(fetched) = "String" or type(fetched) = "roString" then result.body = fetched
    end if
    result.code = xfer.GetResponseCode()
    reason = xfer.GetFailureReason()
    if result.code < 200 or result.code >= 300 then
        if reason <> invalid and reason <> "" then result.error = reason
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
    if xfer.AsyncGetToString() = false then return ""
    wait(4000, port)
    headers = xfer.GetResponseHeaders()
    xfer.AsyncCancel()
    return memberFromHeaders(headers)
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
