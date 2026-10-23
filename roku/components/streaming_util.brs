function streamingServices() as object
    return [
        { id: "netflix", label: "Netflix" },
        { id: "disney", label: "Disney+" },
        { id: "max", label: "Max" },
        { id: "prime", label: "Prime Video" }
    ]
end function

function serviceForName(providerName as string) as string
    if providerName = invalid then return ""
    name = LCase(providerName.Trim())
    if name = "netflix" then return "netflix"
    if name = "disney plus" or name = "disney+" then return "disney"
    if name = "max" or name = "hbo max" then return "max"
    if name = "amazon prime video" or name = "prime video" then return "prime"
    return ""
end function

function serviceLabels(ids as object) as object
    labels = []
    if ids = invalid then return labels
    for each service in streamingServices()
        if hasService(ids, service.id) then labels.Push(service.label)
    end for
    return labels
end function

function orderServices(ids as object) as object
    ordered = []
    for each service in streamingServices()
        if hasService(ids, service.id) then ordered.Push(service.id)
    end for
    return ordered
end function

function hasService(ids as object, service as string) as boolean
    if ids = invalid then return false
    for each id in ids
        if id = service then return true
    end for
    return false
end function

function jsonInt(value as dynamic) as integer
    if value = invalid then return 0
    return Int(value)
end function

function unixNow() as integer
    dt = CreateObject("roDateTime")
    return dt.AsSeconds()
end function

function urlEncode(value as string) as string
    if value = invalid or value = "" then return ""
    xfer = CreateObject("roUrlTransfer")
    if xfer = invalid then return value
    return xfer.Escape(value)
end function
