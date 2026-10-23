sub init()
    m.top.functionName = "run"
end sub

sub run()
    base = m.top.baseUrl
    token = m.top.token
    if token = invalid then token = ""
    playlist = httpRequest(joinUrl(base, "playlist.m3u"), "GET", "", token)
    if playlist.code < 200 or playlist.code >= 300 or playlist.body = "" then
        m.top.error = "Playlist failed. " + playlist.error
        return
    end if
    channels = parseM3u(playlist.body)
    programs = {}
    guideError = ""
    guide = httpRequest(joinUrl(base, "guide.xml"), "GET", "", token)
    if guide.code >= 200 and guide.code < 300 and guide.body <> "" then
        programs = parseXmltv(guide.body)
    else
        guideError = "Guide failed. " + guide.error
    end if
    m.top.payload = {
        channels: sortChannels(channels)
        groups: groupNames(channels)
        programs: programs
        guideError: guideError
    }
end sub

function parseM3u(body as string) as object
    channels = []
    info = invalid
    lines = body.Split(chr(10))
    for each raw in lines
        line = raw.Trim()
        if line.Len() = 0 then continue for
        if line.Left(7) = "#EXTINF" then
            info = line
        else if line.Left(1) <> "#" and info <> invalid then
            channels.Push(channelFromExtinf(info, line))
            info = invalid
        end if
    end for
    return channels
end function

function channelFromExtinf(info as string, url as string) as object
    name = info
    comma = info.Instr(",")
    if comma >= 0 then name = info.Mid(comma + 1).Trim()
    if name = "" then name = "Channel"
    tvgId = quotedAttr(info, "tvg-id")
    return {
        name: name
        number: quotedAttr(info, "tvg-chno")
        logo: quotedAttr(info, "tvg-logo")
        group: quotedAttr(info, "group-title")
        url: url.Trim()
        tvgId: tvgId
    }
end function

function quotedAttr(line as string, name as string) as string
    needle = name + "=" + chr(34)
    at = line.Instr(needle)
    if at < 0 then return ""
    rest = line.Mid(at + needle.Len())
    endq = rest.Instr(chr(34))
    if endq < 0 then return rest
    return rest.Mid(0, endq)
end function

function groupNames(channels as object) as object
    seen = {}
    names = []
    for each channel in channels
        group = channel.group
        if group = invalid then group = ""
        group = group.Trim()
        if group <> "" and seen.DoesExist(LCase(group)) = false then
            seen[LCase(group)] = true
            names.Push(group)
        end if
    end for
    return sortStrings(names)
end function

function sortStrings(items as object) as object
    for i = 1 to items.Count() - 1
        key = items[i]
        j = i - 1
        while j >= 0 and LCase(items[j]) > LCase(key)
            items[j + 1] = items[j]
            j = j - 1
        end while
        items[j + 1] = key
    end for
    return items
end function

function channelNumber(channel as object) as integer
    raw = channel.number
    if raw = invalid or raw = "" then return -1
    value = raw.ToInt()
    if value = 0 and raw.Left(1) <> "0" then return -1
    return value
end function

function sortChannels(items as object) as object
    for i = 1 to items.Count() - 1
        key = items[i]
        j = i - 1
        while j >= 0 and channelBefore(key, items[j])
            items[j + 1] = items[j]
            j = j - 1
        end while
        items[j + 1] = key
    end for
    return items
end function

function channelBefore(a as object, b as object) as boolean
    an = channelNumber(a)
    bn = channelNumber(b)
    if an >= 0 and bn >= 0 and an <> bn then return an < bn
    if an >= 0 and bn < 0 then return true
    if an < 0 and bn >= 0 then return false
    return LCase(a.name) < LCase(b.name)
end function

function parseXmltv(body as string) as object
    programs = {}
    xml = CreateObject("roXMLElement")
    if xml = invalid then return programs
    if not xml.Parse(body) then return programs
    entries = xml.GetNamedElements("programme")
    for each entry in entries
        attrs = entry.GetAttributes()
        if attrs = invalid then continue for
        tvgId = attrs.Lookup("channel")
        if tvgId = invalid or tvgId = "" then continue for
        startAt = xmltvEpoch(attrs.Lookup("start"))
        endAt = xmltvEpoch(attrs.Lookup("stop"))
        if startAt = 0 or endAt = 0 or endAt <= startAt then continue for
        title = elementText(entry, "title")
        if title = "" then title = "Program"
        item = {
            title: title
            start: startAt
            endAt: endAt
            desc: elementText(entry, "desc")
            category: elementText(entry, "category")
        }
        if programs.DoesExist(tvgId) = false then programs[tvgId] = []
        programs[tvgId].Push(item)
    end for
    for each key in programs
        programs[key] = sortPrograms(programs[key])
    end for
    return programs
end function

function elementText(entry as object, name as string) as string
    nodes = entry.GetNamedElements(name)
    if nodes = invalid or nodes.Count() = 0 then return ""
    text = nodes[0].GetText()
    if text = invalid then return ""
    return text.Trim()
end function

function sortPrograms(items as object) as object
    for i = 1 to items.Count() - 1
        key = items[i]
        j = i - 1
        while j >= 0 and key.start < items[j].start
            items[j + 1] = items[j]
            j = j - 1
        end while
        items[j + 1] = key
    end for
    return items
end function

function xmltvEpoch(raw as dynamic) as integer
    if raw = invalid then return 0
    text = raw.ToStr().Trim()
    digits = ""
    for i = 0 to text.Len() - 1
        ch = text.Mid(i, 1)
        if ch >= "0" and ch <= "9" then
            digits = digits + ch
        else
            exit for
        end if
    end for
    if digits.Len() < 12 then return 0
    if digits.Len() < 14 then digits = digits + "00"
    iso = digits.Mid(0, 4) + "-" + digits.Mid(4, 2) + "-" + digits.Mid(6, 2) + "T" + digits.Mid(8, 2) + ":" + digits.Mid(10, 2) + ":" + digits.Mid(12, 2) + "Z"
    dt = CreateObject("roDateTime")
    if not dt.FromISO8601String(iso) then return 0
    epoch = dt.AsSeconds()
    rest = text.Mid(digits.Len()).Trim()
    if rest.Len() >= 5 then
        sign = rest.Mid(0, 1)
        hours = rest.Mid(1, 2).ToInt()
        minutes = rest.Mid(3, 2).ToInt()
        delta = hours * 3600 + minutes * 60
        if sign = "+" then
            epoch = epoch - delta
        else if sign = "-" then
            epoch = epoch + delta
        end if
    end if
    return epoch
end function
