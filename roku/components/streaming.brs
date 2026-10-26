' Streaming tab. Talks only to TMDB. The four Roku channels
' (Netflix 12, Disney+ 291097, Max 61322, Prime Video 13) deep link with
' their own channel ID. When a provider content ID is unavailable, launching
' the channel opens the provider app.

sub showStreaming()
    m.mode = "streaming"
    m.sideFocus = false
    m.streamOnSearch = false
    m.streamRow = 0
    m.streamCol = 0
    m.streamDetail = invalid
    m.preview.control = "stop"
    m.playingUrl = ""
    showPanels()
    loadStreaming()
end sub

sub loadStreaming()
    m.tmdbKey = readSetting("streamingTmdbKey", "")
    m.streamLoading = true
    m.streamDetail = invalid
    m.mode = "streaming"
    drawStreaming()
    if m.tmdbKey = invalid or m.tmdbKey.Trim() = "" then
        m.streamLoading = false
        m.streamPayload = { needsKey: true, rows: [], titles: [], error: "" }
        drawStreaming()
        return
    end if
    startStreamTask("home", m.streamQuery, "", 0)
end sub

sub openStreamDetail(item as object)
    if item = invalid then return
    m.streamPick = item
    m.streamDetail = invalid
    m.streamButton = 0
    m.mode = "streamDetail"
    m.streamLoading = true
    m.sideFocus = false
    showPanels()
    drawStreaming()
    startStreamTask("detail", "", item.mediaType, item.id)
end sub

sub startStreamTask(kind as string, query as string, mediaType as string, tmdbId as integer)
    m.streamEpoch = m.streamEpoch + 1
    task = CreateObject("roSGNode", "StreamingTask")
    task.apiKey = m.tmdbKey
    task.kind = kind
    if kind = "search" then task.query = query
    if kind = "home" and query <> invalid and query.Trim() <> "" then
        task.kind = "search"
        task.query = query
    end if
    task.mediaType = mediaType
    task.tmdbId = tmdbId
    task.epoch = m.streamEpoch
    if m.streamCache = invalid then m.streamCache = {}
    task.cache = m.streamCache
    task.observeField("payload", "onStream")
    task.observeField("error", "onStreamError")
    m.streamTask = task
    task.control = "RUN"
end sub

sub onStream()
    if m.streamTask = invalid then return
    payload = m.streamTask.payload
    if payload = invalid then return
    if payload.epoch <> invalid and Int(payload.epoch) <> m.streamEpoch then return
    if payload.cache <> invalid then m.streamCache = payload.cache
    m.streamLoading = false
    if payload.kind = "detail" then
        m.streamDetail = payload.detail
        m.mode = "streamDetail"
    else
        m.streamPayload = payload
    end if
    if payload.error <> invalid and payload.error <> "" then
        m.status.text = payload.error
    end if
    if payload.kind <> "detail" then clampStreamCol()
    if m.mode = "streaming" or m.mode = "streamDetail" then
        showPanels()
        drawStreaming()
    end if
end sub

sub onStreamError()
    if m.streamTask = invalid then return
    if m.streamTask.payload <> invalid then return
    if m.streamTask.error = invalid or m.streamTask.error = "" then return
    m.streamLoading = false
    m.status.text = m.streamTask.error
    if m.mode = "streaming" or m.mode = "streamDetail" then drawStreaming()
end sub

function onStreamingKey(key as string) as boolean
    if m.mode = "streamDetail" then return onStreamDetailKey(key)
    if key = "left" and (m.streamOnSearch or m.streamCol = 0) then
        m.sideFocus = true
        drawSidebar()
        drawStreaming()
        return true
    end if
    if m.streamPayload <> invalid and m.streamPayload.needsKey = true then
        if key = "OK" or key = "play" then
            m.mode = "settings"
            m.settingsIndex = 2
            showPanels()
            drawSettings()
        end if
        return true
    end if
    if m.streamOnSearch then
        if key = "down" then
            if streamRowCount() > 0 then m.streamOnSearch = false
        else if key = "OK" or key = "play" then
            openKeyboard("Search your subscriptions", m.streamQuery, "streamSearch")
        else
            return false
        end if
        drawStreaming()
        return true
    end if
    rows = streamRows()
    if rows.Count() = 0 then
        if key = "up" or key = "OK" or key = "play" then
            m.streamOnSearch = true
            if key = "OK" or key = "play" then
                openKeyboard("Search your subscriptions", m.streamQuery, "streamSearch")
            end if
        else
            return false
        end if
        drawStreaming()
        return true
    end if
    row = rows[m.streamRow]
    if key = "left" then
        if m.streamCol > 0 then m.streamCol = m.streamCol - 1
    else if key = "right" then
        if m.streamCol < row.items.Count() - 1 then m.streamCol = m.streamCol + 1
    else if key = "up" then
        if m.streamRow = 0 then
            m.streamOnSearch = true
        else
            m.streamRow = m.streamRow - 1
            clampStreamCol()
        end if
    else if key = "down" then
        if m.streamRow < rows.Count() - 1 then
            m.streamRow = m.streamRow + 1
            clampStreamCol()
        end if
    else if key = "OK" or key = "play" then
        if row.items.Count() > 0 then openStreamDetail(row.items[m.streamCol])
        return true
    else
        return false
    end if
    drawStreaming()
    return true
end function

function onStreamDetailKey(key as string) as boolean
    buttons = streamButtons()
    if buttons.Count() = 0 then return false
    if key = "up" then
        if m.streamButton > 0 then m.streamButton = m.streamButton - 1
    else if key = "down" then
        if m.streamButton < buttons.Count() - 1 then m.streamButton = m.streamButton + 1
    else if key = "OK" or key = "play" then
        launchRokuDeepLink(buttons[m.streamButton])
    else
        return false
    end if
    drawStreaming()
    return true
end function

sub clampStreamCol()
    rows = streamRows()
    if m.streamRow > rows.Count() - 1 then m.streamRow = 0
    if rows.Count() = 0 then
        m.streamCol = 0
        return
    end if
    last = rows[m.streamRow].items.Count() - 1
    if last < 0 then last = 0
    if m.streamCol > last then m.streamCol = last
    if m.streamCol < 0 then m.streamCol = 0
end sub

function streamRows() as object
    payload = m.streamPayload
    if payload = invalid then return []
    if m.streamQuery <> invalid and m.streamQuery.Trim() <> "" then
        titles = payload.titles
        if titles = invalid then titles = []
        return [{ title: "Search", items: titles }]
    end if
    rows = payload.rows
    if rows = invalid then return []
    return rows
end function

function streamRowCount() as integer
    count = 0
    for each row in streamRows()
        if row.items <> invalid and row.items.Count() > 0 then count = count + 1
    end for
    return count
end function

sub drawStreaming()
    body = m.top.findNode("streamBody")
    clearGroup(body)
    if m.mode = "streamDetail" then
        drawStreamDetail(body)
        return
    end if
    searchColor = "0xFFFFFFFF"
    searchBg = "0x12263CFF"
    if m.streamOnSearch and m.sideFocus = false then searchBg = "0x1E4B8CFF"
    body.appendChild(makeRect(0, 0, 520, 48, searchBg))
    searchText = "Search your subscriptions"
    if m.streamQuery <> invalid and m.streamQuery.Trim() <> "" then
        searchText = "Search: " + m.streamQuery
    end if
    body.appendChild(makeLabel(searchText, 16, 8, 490, 32, searchColor))
    if m.streamLoading then
        body.appendChild(makeLabel("Loading...", 0, 70, 800, 40, "0xFFFFFFFF"))
        return
    end if
    payload = m.streamPayload
    if payload <> invalid and payload.needsKey = true then
        body.appendChild(makeLabel("Add a TMDB key in Settings", 0, 80, 1200, 48, "0xFFFFFFFF"))
        body.appendChild(makeLabel("OK opens Settings", 0, 130, 800, 32, "0x94A3B8FF"))
        return
    end if
    if payload <> invalid and payload.error <> invalid and payload.error <> "" and streamRows().Count() = 0 then
        body.appendChild(makeLabel(payload.error, 0, 80, 1200, 40, "0xFCA5A5FF"))
        return
    end if
    rows = streamRows()
    if m.streamQuery <> invalid and m.streamQuery.Trim() <> "" and (rows.Count() = 0 or rows[0].items.Count() = 0) then
        body.appendChild(makeLabel("Nothing on Netflix, Disney+, Max, or Prime Video", 0, 80, 1200, 40, "0xFFFFFFFF"))
        return
    end if
    if rows.Count() = 0 then return
    top = m.streamRow - 1
    if top < 0 then top = 0
    last = top + 3
    if last > rows.Count() then last = rows.Count()
    y = 64
    for i = top to last - 1
        row = rows[i]
        body.appendChild(makeLabel(row.title, 0, y, 800, 32, "0xFFFFFFFF"))
        y = y + 36
        if row.items = invalid or row.items.Count() = 0 then
            body.appendChild(makeLabel("Nothing on this service right now", 0, y, 800, 32, "0x94A3B8FF"))
            y = y + 48
            continue for
        end if
        left = m.streamCol - 4
        if i <> m.streamRow then left = 0
        if left < 0 then left = 0
        right = left + 8
        if right > row.items.Count() then right = row.items.Count()
        x = 0
        for c = left to right - 1
            item = row.items[c]
            focused = (m.sideFocus = false and m.streamOnSearch = false and i = m.streamRow and c = m.streamCol)
            if focused then body.appendChild(makeRect(x, y, 148, 250, "0x3B82F6FF"))
            if item.poster <> invalid and item.poster <> "" then
                poster = CreateObject("roSGNode", "Poster")
                poster.translation = [x + 4, y + 4]
                poster.width = 140
                poster.height = 196
                poster.loadWidth = 140
                poster.loadHeight = 196
                poster.uri = item.poster
                body.appendChild(poster)
            else
                body.appendChild(makeRect(x + 4, y + 4, 140, 196, "0x10263CFF"))
            end if
            caption = item.title
            if item.year <> invalid and item.year > 0 then caption = caption + " " + item.year.ToStr()
            body.appendChild(makeLabel(caption, x, y + 204, 148, 28, "0xFFFFFFFF"))
            badges = ""
            if item.services <> invalid then
                for each label in item.services
                    if badges <> "" then badges = badges + " "
                    badges = badges + label
                end for
            end if
            body.appendChild(makeLabel(badges, x, y + 228, 148, 22, "0x93C5FDFF"))
            x = x + 160
        end for
        y = y + 268
    end for
end sub

sub drawStreamDetail(body as object)
    if m.streamLoading then
        body.appendChild(makeLabel("Loading...", 0, 40, 800, 40, "0xFFFFFFFF"))
        return
    end if
    if m.streamDetail = invalid then
        body.appendChild(makeLabel("That title is not available", 0, 40, 1000, 40, "0xFFFFFFFF"))
        return
    end if
    item = m.streamDetail
    if item.poster <> invalid and item.poster <> "" then
        poster = CreateObject("roSGNode", "Poster")
        poster.width = 220
        poster.height = 330
        poster.loadWidth = 220
        poster.loadHeight = 330
        poster.uri = item.poster
        body.appendChild(poster)
    end if
    body.appendChild(makeLabel(item.title, 250, 0, 1000, 48, "0xFFFFFFFF"))
    meta = detailMeta(item)
    body.appendChild(makeLabel(meta, 250, 52, 1000, 32, "0x93C5FDFF"))
    overview = item.overview
    if overview = invalid or overview.Trim() = "" then overview = "No overview"
    about = CreateObject("roSGNode", "Label")
    about.text = overview
    about.translation = [250, 96]
    about.width = 1100
    about.height = 180
    about.wrap = true
    about.color = "0xE2E8F0FF"
    about.font = m.smallFont
    body.appendChild(about)
    buttons = streamButtons()
    if buttons.Count() = 0 then
        body.appendChild(makeLabel(servicesLine(item), 250, 290, 1100, 40, "0xFFFFFFFF"))
        return
    end if
    y = 290
    for i = 0 to buttons.Count() - 1
        color = "0xFFFFFFFF"
        prefix = "  "
        if i = m.streamButton then
            prefix = "> "
            color = "0x93C5FDFF"
            body.appendChild(makeRect(240, y - 4, 520, 48, "0x1E4B8CFF"))
        end if
        body.appendChild(makeLabel(prefix + buttons[i].btnLabel, 250, y, 500, 40, color))
        y = y + 56
    end for
end sub

function streamButtons() as object
    item = m.streamDetail
    buttons = []
    if item = invalid or item.serviceIds = invalid then return buttons
    for each service in streamingServices()
        if hasService(item.serviceIds, service.id) = false then continue for
        contentId = ""
        mediaType = "movie"
        if item.mediaType <> invalid and item.mediaType <> "" then mediaType = item.mediaType
        if item.providerTitleIds <> invalid and item.providerTitleIds[service.id] <> invalid then
            contentId = item.providerTitleIds[service.id]
        end if
        link = rokuDeepLink(service.id, item.title, contentId, mediaType)
        if link = invalid then continue for
        link.label = service.label
        if contentId <> "" then
            link.btnLabel = "Play on " + service.label
        else
            link.btnLabel = "Open " + service.label
        end if
        buttons.Push(link)
    end for
    return buttons
end function

function rokuDeepLink(service as string, title as string, contentId as string, mediaType as string) as object
    channelId = ""
    if service = "netflix" then channelId = "12"
    if service = "disney" then channelId = "291097"
    if service = "max" then channelId = "61322"
    if service = "prime" then channelId = "13"
    if channelId = "" then return invalid
    return {
        channelId: channelId,
        contentId: contentId,
        mediaType: mediaType
    }
end function

function servicesLine(item as object) as string
    if item = invalid or item.services = invalid or item.services.Count() = 0 then
        return "Not on Netflix, Disney+, Max, or Prime Video"
    end if
    text = ""
    for each label in item.services
        if text <> "" then text = text + ", "
        text = text + label
    end for
    return "On " + text
end function

function detailMeta(item as object) as string
    bits = []
    if item.year <> invalid and item.year > 0 then bits.Push(item.year.ToStr())
    if item.rating <> invalid and item.rating > 0 then
        bits.Push(Str(item.rating).Trim() + " / 10")
    end if
    if item.mediaType = "tv" then
        count = jsonInt(item.seasons)
        if count = 1 then
            bits.Push("1 season")
        else if count > 1 then
            bits.Push(count.ToStr() + " seasons")
        end if
    else
        minutes = jsonInt(item.runtime)
        if minutes > 0 then
            hours = Int(minutes / 60)
            rest = minutes - hours * 60
            if hours > 0 and rest > 0 then
                bits.Push(hours.ToStr() + "h " + rest.ToStr() + "m")
            else if hours > 0 then
                bits.Push(hours.ToStr() + "h")
            else
                bits.Push(rest.ToStr() + "m")
            end if
        end if
    end if
    text = ""
    for each bit in bits
        if text <> "" then text = text + "  "
        text = text + bit
    end for
    return text
end function

sub launchRokuDeepLink(link as object)
    if link = invalid or link.channelId = invalid or link.channelId = "" then return
    url = "http://127.0.0.1:8060/launch/" + link.channelId
    if link.contentId <> invalid and link.contentId <> "" then
        url = url + "?contentId=" + urlEncode(link.contentId) + "&mediaType=" + urlEncode(link.mediaType)
    end if
    httpRequest(url, "POST", "", "", "")
end sub
