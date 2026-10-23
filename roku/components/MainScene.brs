sub init()
    m.defaultBase = "https://dad2lna.duckdns.org:8443/mofin/free/"
    m.mode = "guide"
    m.sideFocus = false
    m.sideIndex = 0
    m.sideTop = 0
    m.row = 0
    m.block = 0
    m.cursorTime = 0
    m.filter = ""
    m.channels = []
    m.groups = []
    m.programs = {}
    m.visible = []
    m.recordings = []
    m.recordingIndex = 0
    m.recordBusy = false
    m.recordingsKnown = false
    m.settingsIndex = 0
    m.dialogIndex = 0
    m.dialogKind = "program"
    m.playingUrl = ""
    m.baseUrl = readSetting("baseUrl", m.defaultBase)
    m.token = readSetting("token", "")
    m.playerControls = false
    m.playerIndex = 0
    m.resumePlayer = false
    m.playingChannel = invalid
    m.statusHold = ""
    m.removeTvgId = ""
    m.removeName = ""
    m.reportedRes = {}
    m.pendingRes = invalid
    m.resEpoch = 0
    m.resWaitEpoch = 0
    m.resLive = false
    m.tmdbKey = readSetting("streamingTmdbKey", "")
    m.streamCache = {}
    m.streamEpoch = 0
    m.streamRow = 0
    m.streamCol = 0
    m.streamOnSearch = false
    m.streamQuery = ""
    m.streamLoading = false
    m.streamPayload = invalid
    m.streamDetail = invalid
    m.streamButton = 0
    m.streamPick = invalid

    m.preview = m.top.findNode("preview")
    m.preview.captionMode = "On"
    m.preview.observeField("state", "onVideoState")
    m.preview.observeField("availableSubtitleTracks", "onTracks")
    m.preview.observeField("streamingSegment", "onSegment")
    m.preview.observeField("downloadedSegment", "onSegment")
    m.previewFallback = m.top.findNode("previewFallback")
    m.logo = m.top.findNode("logo")
    m.chName = m.top.findNode("chName")
    m.progTitle = m.top.findNode("progTitle")
    m.progMeta = m.top.findNode("progMeta")
    m.progDesc = m.top.findNode("progDesc")
    m.progressFg = m.top.findNode("progressFg")
    m.sideList = m.top.findNode("sideList")
    m.grid = m.top.findNode("grid")
    m.status = m.top.findNode("status")
    m.clock = m.top.findNode("clock")
    m.dateLabel = m.top.findNode("dateLabel")
    m.hero = m.top.findNode("hero")
    m.dialog = m.top.findNode("dialog")
    m.settings = m.top.findNode("settings")
    m.recordingsPanel = m.top.findNode("recordings")
    m.recordingList = m.top.findNode("recordingList")
    m.playerHint = m.top.findNode("playerHint")
    m.playerBar = m.top.findNode("playerBar")
    m.sidebar = m.top.findNode("sidebar")
    m.brand = m.top.findNode("brand")
    m.brandSub = m.top.findNode("brandSub")
    m.streaming = m.top.findNode("streaming")

    m.smallFont = CreateObject("roSGNode", "Font")
    m.smallFont.uri = "font:SmallSystemFont"
    m.smallFont.size = 24
    m.clockTimer = m.top.findNode("clockTimer")
    m.clockTimer.observeField("fire", "onClock")
    m.clockTimer.control = "start"
    m.previewTimer = m.top.findNode("previewTimer")
    m.previewTimer.observeField("fire", "onPreview")
    m.resWait = m.top.findNode("resWait")
    m.resWait.observeField("fire", "onResWait")
    onClock()
    m.cursorTime = nowSeconds()
    m.status.text = "Loading Mo Fin..."
    m.top.setFocus(true)
    m.top.signalBeacon("AppLaunchComplete")
    loadGuide()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press = false then return true
    if key = "back" then return onBack()
    if m.mode = "dialog" then return onDialogKey(key)
    if m.mode = "settings" then return onSettingsKey(key)
    if m.mode = "recordings" then return onRecordingsKey(key)
    if m.mode = "player" then return onPlayerKey(key)
    if m.mode = "streaming" or m.mode = "streamDetail" then
        if m.mode = "streaming" and m.sideFocus then return onSidebarKey(key)
        return onStreamingKey(key)
    end if
    if m.sideFocus then return onSidebarKey(key)
    return onGridKey(key)
end function

function onBack() as boolean
    if m.mode = "dialog" then
        closeDialog()
        return true
    end if
    if m.mode = "streamDetail" then
        m.mode = "streaming"
        m.streamLoading = false
        showPanels()
        drawStreaming()
        return true
    end if
    if m.mode = "streaming" or m.mode = "player" or m.mode = "settings" or m.mode = "recordings" then
        showGuide()
        return true
    end if
    return false
end function

function onSidebarKey(key as string) as boolean
    items = sideItems()
    if key = "up" then
        if m.sideIndex > 0 then m.sideIndex = m.sideIndex - 1
    else if key = "down" then
        if m.sideIndex < items.Count() - 1 then m.sideIndex = m.sideIndex + 1
    else if key = "right" then
        if m.visible.Count() > 0 then m.sideFocus = false
    else if key = "OK" or key = "play" then
        activateSidebar()
    else
        return false
    end if
    keepSideVisible()
    drawAll()
    return true
end function

function onGridKey(key as string) as boolean
    if m.visible.Count() = 0 then
        m.sideFocus = true
        drawAll()
        return true
    end if
    if key = "up" then
        moveRow(-1)
    else if key = "down" then
        moveRow(1)
    else if key = "rewind" then
        moveRow(-4)
    else if key = "fastforward" then
        moveRow(4)
    else if key = "left" then
        moveBlock(-1)
    else if key = "right" then
        moveBlock(1)
    else if key = "OK" or key = "play" then
        openProgramDialog()
    else
        return false
    end if
    drawAll()
    schedulePreview()
    return true
end function

function onDialogKey(key as string) as boolean
    count = dialogCount()
    if key = "up" then
        if m.dialogIndex > 0 then m.dialogIndex = m.dialogIndex - 1
    else if key = "down" then
        if m.dialogIndex < count - 1 then m.dialogIndex = m.dialogIndex + 1
    else if key = "OK" or key = "play" then
        activateDialog()
    else
        return false
    end if
    drawDialog()
    return true
end function

function onSettingsKey(key as string) as boolean
    if key = "up" then
        if m.settingsIndex > 0 then m.settingsIndex = m.settingsIndex - 1
    else if key = "down" then
        if m.settingsIndex < 4 then m.settingsIndex = m.settingsIndex + 1
    else if key = "OK" or key = "play" then
        activateSettings()
    else
        return false
    end if
    drawSettings()
    return true
end function

function onRecordingsKey(key as string) as boolean
    if key = "up" then
        if m.recordingIndex > 0 then m.recordingIndex = m.recordingIndex - 1
    else if key = "down" then
        if m.recordingIndex < m.recordings.Count() - 1 then m.recordingIndex = m.recordingIndex + 1
    else if key = "OK" or key = "play" then
        openDeleteDialog()
    else
        return false
    end if
    drawRecordings()
    return true
end function

function onPlayerKey(key as string) as boolean
    if m.playerControls then
        if key = "left" then
            if m.playerIndex > 0 then m.playerIndex = m.playerIndex - 1
        else if key = "right" then
            if m.playerIndex < 3 then m.playerIndex = m.playerIndex + 1
        else if key = "up" then
            m.playerControls = false
        else if key = "OK" or key = "play" then
            activatePlayerControl()
        else
            return false
        end if
        drawPlayerBar()
        return true
    end if
    if key = "down" or key = "left" or key = "right" then
        m.playerControls = true
        drawPlayerBar()
        return true
    end if
    if key = "OK" or key = "play" then
        if m.preview.state = "playing" then
            m.preview.control = "pause"
        else
            m.preview.control = "resume"
        end if
        return true
    end if
    return false
end function

sub activateSidebar()
    kind = sideKind(m.sideIndex)
    if kind = "settings" then
        m.mode = "settings"
        m.settingsIndex = 0
        showPanels()
        drawSettings()
        return
    end if
    if kind = "recordings" then
        m.mode = "recordings"
        m.recordingIndex = 0
        showPanels()
        drawRecordings()
        loadRecordings()
        return
    end if
    if kind = "streaming" then
        showStreaming()
        return
    end if
    if kind = "all" then
        m.filter = ""
    else
        m.filter = sideItems()[m.sideIndex]
    end if
    refreshVisible()
    m.row = 0
    m.cursorTime = nowSeconds()
    m.sideFocus = false
    if m.visible.Count() = 0 then m.sideFocus = true
end sub

sub moveRow(delta as integer)
    m.row = m.row + delta
    if m.row < 0 then m.row = 0
    if m.row > m.visible.Count() - 1 then m.row = m.visible.Count() - 1
    blocks = blocksFor(focusedChannel())
    m.block = blockIndexAt(blocks, m.cursorTime)
end sub

sub moveBlock(delta as integer)
    channel = focusedChannel()
    if channel = invalid then return
    blocks = blocksFor(channel)
    if delta < 0 and m.block = 0 then
        m.sideFocus = true
        return
    end if
    m.block = m.block + delta
    if m.block < 0 then m.block = 0
    if m.block > blocks.Count() - 1 then m.block = blocks.Count() - 1
    m.cursorTime = blocks[m.block].start
end sub

sub openProgramDialog()
    program = focusedProgram()
    if program = invalid then return
    m.dialogKind = "program"
    m.dialogIndex = 0
    m.mode = "dialog"
    showPanels()
    drawDialog()
end sub

sub openDeleteDialog()
    if m.recordings.Count() = 0 then return
    rec = m.recordings[m.recordingIndex]
    if rec.id = "" then return
    m.dialogKind = "delete"
    m.dialogIndex = 0
    m.pendingDelete = rec
    m.mode = "dialog"
    showPanels()
    drawDialog()
end sub

sub activateDialog()
    if m.dialogKind = "delete" then
        if m.dialogIndex = 0 then deleteRecording(m.pendingDelete)
        closeDialog()
        return
    end if
    if m.dialogKind = "remove" then
        if m.dialogIndex = 0 then postRemove()
        closeDialog()
        return
    end if
    if m.dialogIndex = 0 then
        closeDialog()
        enterPlayer()
        return
    end if
    if m.dialogIndex = 1 then
        toggleRecord()
        closeDialog()
        return
    end if
    closeDialog()
end sub

sub closeDialog()
    m.dialog.visible = false
    if m.mode <> "dialog" then return
    if m.resumePlayer = true then
        m.resumePlayer = false
        m.mode = "player"
        showPanels()
        m.top.setFocus(true)
        drawPlayerBar()
        return
    end if
    m.mode = "guide"
    showGuide()
end sub

sub activateSettings()
    if m.settingsIndex = 0 then
        openKeyboard("Playlist base URL", m.baseUrl, "base")
    else if m.settingsIndex = 1 then
        openKeyboard("Bearer token", m.token, "token")
    else if m.settingsIndex = 2 then
        openKeyboard("TMDB API key", m.tmdbKey, "tmdb")
    else if m.settingsIndex = 3 then
        saveSettings()
        showGuide()
        loadGuide()
    else
        showGuide()
    end if
end sub

sub openKeyboard(title as string, value as string, which as string)
    dialog = CreateObject("roSGNode", "KeyboardDialog")
    dialog.title = title
    dialog.buttons = ["Save", "Cancel"]
    if value = invalid then value = ""
    dialog.textEditBox.maxTextLength = 400
    dialog.textEditBox.text = value
    if which = "tmdb" then dialog.textEditBox.secureMode = true
    dialog.observeField("buttonSelected", "onKeyboard")
    m.keyboard = dialog
    m.keyboardWhich = which
    m.top.dialog = dialog
end sub

sub onKeyboard()
    if m.keyboard = invalid then return
    button = m.keyboard.buttonSelected
    text = ""
    if m.keyboard.textEditBox <> invalid and m.keyboard.textEditBox.text <> invalid then
        text = m.keyboard.textEditBox.text
    end if
    which = m.keyboardWhich
    m.top.dialog = invalid
    m.keyboard = invalid
    m.top.setFocus(true)
    if button <> 0 then return
    if which = "base" then m.baseUrl = text.Trim()
    if which = "token" then m.token = text.Trim()
    if which = "tmdb" then
        m.tmdbKey = text.Trim()
        writeStreamingKey(m.tmdbKey)
        drawSettings()
        return
    end if
    if which = "streamSearch" then
        m.streamQuery = text.Trim()
        m.streamRow = 0
        m.streamCol = 0
        m.streamOnSearch = false
        loadStreaming()
        return
    end if
    saveSettings()
    drawSettings()
end sub

sub showGuide()
    m.mode = "guide"
    m.playerControls = false
    m.preview.width = 440
    m.preview.height = 248
    m.preview.translation = [0, 0]
    m.playerHint.visible = false
    showPanels()
    m.top.setFocus(true)
    drawAll()
    schedulePreview()
end sub

sub enterPlayer()
    channel = focusedChannel()
    if channel = invalid or channel.url = "" then return
    m.mode = "player"
    m.playingChannel = channel
    m.playerControls = false
    m.playerIndex = 0
    m.hero.visible = true
    m.grid.visible = false
    m.dialog.visible = false
    m.settings.visible = false
    m.recordingsPanel.visible = false
    m.sidebar.visible = false
    m.brand.visible = false
    m.brandSub.visible = false
    m.sideList.visible = false
    m.clock.visible = false
    m.dateLabel.visible = false
    m.playerHint.visible = true
    playUrl(channel.url, true)
    drawPlayerBar()
end sub

sub showPanels()
    removing = (m.mode = "dialog" and m.dialogKind = "remove")
    guide = (m.mode = "guide" or (m.mode = "dialog" and removing = false))
    m.hero.visible = (m.mode = "guide" or m.mode = "dialog" or m.mode = "player")
    m.grid.visible = guide
    m.sidebar.visible = (m.mode <> "player" and removing = false)
    m.brand.visible = (m.mode <> "player" and removing = false)
    m.brandSub.visible = (m.mode <> "player" and removing = false)
    m.sideList.visible = (m.mode <> "player" and removing = false)
    m.clock.visible = (m.mode <> "player" and removing = false)
    m.dateLabel.visible = (m.mode <> "player" and removing = false)
    m.dialog.visible = (m.mode = "dialog")
    m.settings.visible = (m.mode = "settings")
    m.recordingsPanel.visible = (m.mode = "recordings")
    m.playerHint.visible = (m.mode = "player")
    if m.playerBar <> invalid then m.playerBar.visible = (m.mode = "player")
    if m.streaming <> invalid then
        m.streaming.visible = (m.mode = "streaming" or m.mode = "streamDetail")
    end if
end sub

sub loadGuide()
    m.status.text = "Loading Mo Fin..."
    task = CreateObject("roSGNode", "GuideTask")
    task.baseUrl = activeBase()
    task.token = m.token
    task.observeField("payload", "onGuide")
    task.observeField("error", "onGuideError")
    m.guideTask = task
    task.control = "RUN"
end sub

sub onGuide()
    payload = m.guideTask.payload
    if payload = invalid then return
    m.channels = payload.channels
    if m.channels = invalid then m.channels = []
    m.groups = payload.groups
    if m.groups = invalid then m.groups = []
    m.programs = payload.programs
    if m.programs = invalid then m.programs = {}
    refreshVisible()
    if m.mode = "player" and m.playingChannel <> invalid then
        m.row = 0
        for i = 0 to m.visible.Count() - 1
            if m.visible[i].url = m.playingChannel.url then
                m.row = i
                exit for
            end if
        end for
    else
        m.row = 0
        m.block = 0
        m.cursorTime = nowSeconds()
    end if
    if payload.guideError <> invalid and payload.guideError <> "" then
        m.status.text = payload.guideError
        m.statusHold = ""
    else if m.statusHold <> invalid and m.statusHold <> "" then
        m.status.text = m.statusHold
        m.statusHold = ""
    else
        m.status.text = m.channels.Count().ToStr() + " channels"
    end if
    drawAll()
    schedulePreview()
    loadRecordings()
end sub

sub onGuideError()
    if m.guideTask = invalid then return
    if m.guideTask.error <> invalid and m.guideTask.error <> "" then
        m.status.text = m.guideTask.error
    end if
end sub

sub loadRecordings()
    if m.recordBusy then return
    startRecord("GET", joinUrl(activeBase(), "rec/list"), "", "list", "")
end sub

sub toggleRecord()
    channel = focusedChannel()
    program = focusedProgram()
    if channel = invalid or program = invalid then return
    existing = recordingMatch(channel.tvgId, program.start)
    if existing <> invalid and existing.id <> "" then
        deleteRecording(existing)
        return
    end if
    body = {}
    body.tvg_id = channel.tvgId
    body.title = program.title
    body.start = isoTime(program.start)
    body["end"] = isoTime(program.endAt)
    m.recordings.Push({
        id: ""
        tvgId: channel.tvgId
        title: program.title
        start: program.start
        endAt: program.endAt
        status: "scheduled"
    })
    drawAll()
    startRecord("POST", joinUrl(activeBase(), "rec/schedule"), FormatJSON(body), "schedule", "")
end sub

sub deleteRecording(rec as object)
    if rec = invalid or rec.id = "" then return
    xfer = CreateObject("roUrlTransfer")
    escaped = rec.id
    if xfer <> invalid then escaped = xfer.Escape(rec.id)
    startRecord("DELETE", joinUrl(activeBase(), "rec/" + escaped), "", "delete", "")
end sub

sub startRecord(method as string, url as string, body as string, op as string, tokenHeader as dynamic)
    m.recordBusy = true
    m.recordOp = op
    task = CreateObject("roSGNode", "RecordTask")
    task.method = method
    task.url = url
    task.body = body
    task.token = m.token
    if tokenHeader = invalid then tokenHeader = ""
    task.tokenHeader = tokenHeader
    task.observeField("done", "onRecordDone")
    m.recordTask = task
    task.control = "RUN"
end sub

sub onRecordDone()
    task = m.recordTask
    if task = invalid or task.done <> true then return
    m.recordBusy = false
    code = task.code
    op = m.recordOp
    if op = "remove" then
        handleRemove(code, task.response)
        return
    end if
    if op = "report" then
        handleReport(code, task.response)
        return
    end if
    if code = 404 or code = 405 or code = 501 then
        m.recordingsKnown = true
        m.status.text = "Recordings aren't available on this source"
        if op <> "list" then dropOptimistic()
        drawAll()
        return
    end if
    if code < 200 or code >= 300 then
        if task.error <> invalid and task.error <> "" then
            m.status.text = task.error
        else
            m.status.text = "Recording request failed"
        end if
        if op <> "list" then dropOptimistic()
        drawAll()
        return
    end if
    if op = "list" then
        m.recordings = parseRecordingList(task.response)
        if m.recordingIndex > m.recordings.Count() - 1 then m.recordingIndex = 0
    else
        if op = "schedule" then m.status.text = "Scheduled on the server"
        if op = "delete" then m.status.text = "Recording removed"
        drawAll()
        loadRecordings()
        return
    end if
    drawAll()
    if m.mode = "recordings" then drawRecordings()
end sub

sub dropOptimistic()
    kept = []
    for each rec in m.recordings
        if rec.id <> "" then kept.Push(rec)
    end for
    m.recordings = kept
end sub

sub schedulePreview()
    if m.mode = "player" then return
    m.previewTimer.control = "stop"
    m.previewTimer.duration = 0.4
    m.previewTimer.control = "start"
end sub

sub onPreview()
    if m.mode = "player" or m.mode = "settings" or m.mode = "recordings" then return
    if m.mode = "streaming" or m.mode = "streamDetail" then return
    channel = focusedChannel()
    if channel = invalid then return
    playUrl(channel.url, false)
end sub

sub playUrl(url as string, fullscreen as boolean)
    if url = invalid or url = "" then return
    if fullscreen then
        m.preview.translation = [-320, -16]
        m.preview.width = 1920
        m.preview.height = 1080
    else
        m.preview.translation = [0, 0]
        m.preview.width = 440
        m.preview.height = 248
    end if
    if m.playingUrl = url and (m.preview.state = "playing" or m.preview.state = "buffering") then
        if fullscreen and m.preview.state = "playing" then
            m.resLive = true
            noteResolution()
        end if
        return
    end if
    m.resLive = false
    content = CreateObject("roSGNode", "ContentNode")
    content.url = url
    content.streamformat = "hls"
    content.title = "MoFin"
    m.preview.content = content
    m.preview.captionMode = "On"
    m.preview.control = "play"
    m.playingUrl = url
end sub

sub onVideoState()
    state = m.preview.state
    m.previewFallback.visible = (state <> "playing")
    if state = "error" then
        msg = m.preview.errorMsg
        if msg = invalid or msg = "" then msg = "Playback failed"
        m.status.text = msg
    end if
    if state = "playing" then
        onTracks()
        m.resLive = true
        noteResolution()
    else
        m.resLive = false
    end if
end sub

sub onSegment()
    if m.resLive <> true then return
    if m.preview.state <> "playing" then return
    noteResolution()
end sub

sub noteResolution()
    if m.mode <> "player" then return
    channel = m.playingChannel
    if channel = invalid then return
    tvgId = channel.tvgId
    if tvgId = invalid or tvgId = "" then return
    if m.reportedRes.DoesExist(tvgId) then return
    if m.pendingRes <> invalid and m.pendingRes.tvgId = tvgId then return
    if isMofinFreeBase(activeBase()) = false then return
    height = segmentHeight()
    res = resolutionForHeight(height)
    if res = "" then return
    m.resEpoch = m.resEpoch + 1
    epoch = m.resEpoch
    stack = stackOf(channel)
    m.pendingRes = { tvgId: tvgId, res: res, stack: stack, epoch: epoch }
    if stack >= 1 then
        startMemberProbe(channel.url, epoch)
        m.resWaitEpoch = epoch
        m.resWait.control = "stop"
        m.resWait.duration = 4
        m.resWait.control = "start"
        return
    end if
    postResolution("")
end sub

sub startMemberProbe(url as string, epoch as integer)
    task = CreateObject("roSGNode", "ProbeTask")
    task.url = url
    task.epoch = epoch
    task.observeField("done", "onMemberProbe")
    m.probeTask = task
    task.control = "RUN"
end sub

sub onMemberProbe()
    if m.pendingRes = invalid or m.probeTask = invalid then return
    if m.probeTask.done <> true then return
    if m.probeTask.epoch <> m.pendingRes.epoch then return
    member = m.probeTask.member
    if member = invalid then member = ""
    m.resWait.control = "stop"
    postResolution(member)
end sub

sub onResWait()
    if m.pendingRes = invalid then return
    if m.pendingRes.epoch <> m.resWaitEpoch then return
    postResolution("")
end sub

sub postResolution(member as string)
    pending = m.pendingRes
    if pending = invalid then return
    m.pendingRes = invalid
    m.reportedRes[pending.tvgId] = true
    body = {}
    body.tvg_id = pending.tvgId
    body.res = pending.res
    if pending.stack >= 1 and member <> invalid and member.Trim() <> "" then
        body.member = member.Trim()
    end if
    task = CreateObject("roSGNode", "RecordTask")
    task.method = "POST"
    task.url = joinUrl(activeBase(), "resolution")
    task.body = FormatJSON(body)
    task.token = m.token
    task.control = "RUN"
    m.resolutionTask = task
end sub

function segmentHeight() as integer
    h = fieldHeight(m.preview.streamingSegment)
    if h > 0 then return h
    return fieldHeight(m.preview.downloadedSegment)
end function

function fieldHeight(seg as object) as integer
    if seg = invalid then return 0
    if type(seg) <> "roAssociativeArray" then return 0
    h = numberField(seg, "height")
    if h > 0 then return h
    return numberField(seg, "Height")
end function

function numberField(seg as object, name as string) as integer
    if seg.DoesExist(name) = false then return 0
    value = seg[name]
    if value = invalid then return 0
    return value.ToStr().ToInt()
end function

function resolutionForHeight(height as integer) as string
    if height <= 0 then return ""
    if height >= 2160 then return "2160p"
    if height >= 1440 then return "1440p"
    if height >= 1080 then return "1080p"
    if height >= 720 then return "720p"
    if height >= 480 then return "480p"
    return "SD"
end function

function isMofinFreeBase(baseUrl as string) as boolean
    if baseUrl = invalid then return false
    raw = LCase(baseUrl.Trim())
    slash = raw.Instr("://")
    if slash < 0 then return false
    rest = raw.Mid(slash + 3)
    pathAt = rest.Instr("/")
    if pathAt < 0 then return false
    path = rest.Mid(pathAt)
    if path.Len() > 1 and path.Right(1) = "/" then path = path.Left(path.Len() - 1)
    return path.Right(11) = "/mofin/free"
end function

sub onTracks()
    tracks = m.preview.availableSubtitleTracks
    if tracks = invalid or tracks.Count() = 0 then return
    current = m.preview.subtitleTrack
    if current <> invalid and current <> "" then return
    name = tracks[0].TrackName
    if name = invalid or name = "" then name = tracks[0].Language
    if name = invalid or name = "" then name = tracks[0].Description
    if name <> invalid and name <> "" then m.preview.subtitleTrack = name
end sub

sub onClock()
    dt = CreateObject("roDateTime")
    dt.ToLocalTime()
    m.clock.text = formatClock(dt)
    m.dateLabel.text = dt.GetDayOfWeek() + " " + dt.GetMonth().ToStr() + "/" + dt.GetDayOfMonth().ToStr()
    if m.mode = "guide" then drawHero()
end sub

sub drawAll()
    refreshVisible()
    drawSidebar()
    drawHero()
    drawGrid()
    if m.mode = "dialog" then drawDialog()
    if m.mode = "settings" then drawSettings()
    if m.mode = "recordings" then drawRecordings()
end sub

sub drawSidebar()
    clearGroup(m.sideList)
    items = sideItems()
    keepSideVisible()
    y = 0
    last = m.sideTop + 14
    if last > items.Count() then last = items.Count()
    for i = m.sideTop to last - 1
        focused = (m.sideFocus and i = m.sideIndex)
        if focused then
            m.sideList.appendChild(makeRect(0, y, 300, 48, "0x1E3A5FFF"))
            m.sideList.appendChild(makeRect(0, y, 4, 48, "0x3B82F6FF"))
        end if
        color = "0xE2E8F0FF"
        if focused then color = "0xFFFFFFFF"
        m.sideList.appendChild(makeLabel(items[i], 24, y + 8, 250, 32, color))
        y = y + 48
    end for
end sub

sub drawHero()
    channel = focusedChannel()
    program = focusedProgram()
    if channel = invalid then
        m.chName.text = "MoFin"
        m.progTitle.text = ""
        m.progMeta.text = ""
        m.progDesc.text = "No channels"
        m.progressFg.width = 0
        m.logo.visible = false
        return
    end if
    number = channel.number
    if number <> "" then
        m.chName.text = number + "   " + channel.name
    else
        m.chName.text = channel.name
    end if
    if channel.logo <> "" then
        m.logo.visible = true
        m.logo.uri = channel.logo
    else
        m.logo.visible = false
    end if
    if program = invalid then
        m.progTitle.text = ""
        m.progMeta.text = ""
        m.progDesc.text = ""
        m.progressFg.width = 0
        return
    end if
    m.progTitle.text = program.title
    meta = formatTime(program.start) + " - " + formatTime(program.endAt)
    if program.category <> "" then meta = program.category + "   " + meta
    matched = recordingMatch(channel.tvgId, program.start)
    if matched <> invalid then meta = meta + "   REC"
    m.progMeta.text = meta
    m.progDesc.text = program.desc
    span = program.endAt - program.start
    frac = 0.0
    if span > 0 then frac = (nowSeconds() - program.start) / span
    if frac < 0 then frac = 0
    if frac > 1 then frac = 1
    m.progressFg.width = Int(700 * frac)
end sub

sub drawGrid()
    clearGroup(m.grid)
    window = guideWindow()
    for slot = 0 to 5
        label = formatTime(window.start + slot * 1800)
        m.grid.appendChild(makeLabel(label, 250 + slot * 220, 0, 210, 28, "0x94A3B8FF"))
    end for
    if m.visible.Count() = 0 then
        m.grid.appendChild(makeLabel("No channels in this group", 0, 48, 800, 40, "0xFFFFFFFF"))
        return
    end if
    top = m.row - 3
    if top < 0 then top = 0
    if m.visible.Count() > 8 and top > m.visible.Count() - 8 then top = m.visible.Count() - 8
    if top < 0 then top = 0
    last = top + 8
    if last > m.visible.Count() then last = m.visible.Count()
    for i = top to last - 1
        y = 36 + (i - top) * 68
        channel = m.visible[i]
        rowFocused = (m.sideFocus = false and i = m.row and m.mode = "guide")
        if rowFocused then m.grid.appendChild(makeRect(0, y, 250, 64, "0x12263CFF"))
        name = channel.name
        if channel.number <> "" then name = channel.number + "  " + name
        if stackOf(channel) >= 1 then name = name + "  ×" + stackOf(channel).ToStr()
        m.grid.appendChild(makeLabel(name, 8, y + 16, 234, 32, "0xFFFFFFFF"))
        blocks = blocksFor(channel)
        for b = 0 to blocks.Count() - 1
            item = blocks[b]
            box = spanBox(item.start, item.endAt, window.start, window.endAt, 250, 1320)
            if box = invalid then continue for
            color = "0x14304EFF"
            if item.endAt <= nowSeconds() then color = "0x10263CFF"
            if rowFocused and b = m.block then color = "0x1E4B8CFF"
            m.grid.appendChild(makeRect(box.x + 2, y + 6, box.w - 4, 52, color))
            m.grid.appendChild(makeLabel(item.title, box.x + 8, y + 18, box.w - 28, 28, "0xFFFFFFFF"))
            if recordingMatch(channel.tvgId, item.start) <> invalid then
                m.grid.appendChild(makeRect(box.x + box.w - 18, y + 12, 10, 10, "0xEF4444FF"))
            end if
        end for
    end for
    frac = (nowSeconds() - window.start) / (window.endAt - window.start)
    if frac < 0 then frac = 0
    if frac > 1 then frac = 1
    nx = 250 + Int(frac * 1320)
    m.grid.appendChild(makeRect(nx, 28, 2, 8 * 68, "0x60A5FAFF"))
    m.grid.appendChild(makeLabel("NOW", nx + 6, 28, 60, 24, "0x60A5FAFF"))
end sub

sub drawDialog()
    showPanels()
    title = "Program"
    body = ""
    labels = ["Play", "Record", "Close"]
    if m.dialogKind = "remove" then
        title = "Remove from lineup?"
        body = "Remove " + m.removeName + " from lineup?"
        labels = ["Yes", "No", ""]
    else if m.dialogKind = "program" then
        channel = focusedChannel()
        program = focusedProgram()
        if channel <> invalid then title = channel.name
        if program <> invalid then
            body = program.title + "   " + formatTime(program.start) + " - " + formatTime(program.endAt)
            matched = invalid
            if channel <> invalid then matched = recordingMatch(channel.tvgId, program.start)
            if matched <> invalid then labels = ["Play", "Cancel recording", "Close"]
        end if
    else
        title = "Delete recording?"
        if m.pendingDelete <> invalid then body = m.pendingDelete.title
        labels = ["Delete", "Cancel", ""]
    end if
    m.top.findNode("dialogTitle").text = title
    m.top.findNode("dialogBody").text = body
    for i = 0 to 2
        node = m.top.findNode("dialog" + i.ToStr())
        node.text = labels[i]
        if labels[i] = "" then
            node.color = "0x00000000"
        else if i = m.dialogIndex then
            node.color = "0x93C5FDFF"
        else
            node.color = "0xFFFFFFFF"
        end if
    end for
end sub

sub drawSettings()
    showPanels()
    rows = ["Base URL    " + shown(m.baseUrl, "default"), "Bearer token    " + shownSecret(m.token), "TMDB API key    " + shownSecret(m.tmdbKey), "Reload guide", "Back"]
    for i = 0 to 4
        node = m.top.findNode("settings" + i.ToStr())
        prefix = "  "
        if i = m.settingsIndex then prefix = "> "
        node.text = prefix + rows[i]
        if i = m.settingsIndex then
            node.color = "0x93C5FDFF"
        else
            node.color = "0xFFFFFFFF"
        end if
    end for
end sub

sub drawRecordings()
    showPanels()
    clearGroup(m.recordingList)
    if m.recordings.Count() = 0 then
        m.recordingList.appendChild(makeLabel("No recordings", 0, 0, 800, 40, "0xFFFFFFFF"))
        return
    end if
    top = m.recordingIndex - 4
    if top < 0 then top = 0
    last = top + 12
    if last > m.recordings.Count() then last = m.recordings.Count()
    y = 0
    for i = top to last - 1
        rec = m.recordings[i]
        color = "0xFFFFFFFF"
        if i = m.recordingIndex then color = "0x93C5FDFF"
        text = rec.title
        if rec.status <> "" then text = text + "   " + rec.status
        if rec.start > 0 then text = formatTime(rec.start) + "   " + text
        m.recordingList.appendChild(makeLabel(text, 0, y, 1200, 40, color))
        y = y + 44
    end for
end sub

function dialogCount() as integer
    if m.dialogKind = "delete" or m.dialogKind = "remove" then return 2
    return 3
end function

sub drawPlayerBar()
    if m.playerBar = invalid then return
    m.playerBar.visible = (m.mode = "player")
    labels = ["Info", "🙂", "☹️", "🖕"]
    for i = 0 to 3
        node = m.top.findNode("pbtn" + i.ToStr())
        if node = invalid then continue for
        prefix = "  "
        if m.playerControls and i = m.playerIndex then prefix = "> "
        node.text = prefix + labels[i]
        if m.playerControls and i = m.playerIndex then
            node.color = "0x93C5FDFF"
        else
            node.color = "0xFFFFFFFF"
        end if
    end for
end sub

sub activatePlayerControl()
    channel = m.playingChannel
    if channel = invalid then channel = focusedChannel()
    if channel = invalid then return
    if m.playerIndex = 0 then
        text = channel.name
        if channel.number <> "" then text = channel.number + "  " + text
        if channel.tvgId <> "" then text = text + "  " + channel.tvgId
        if stackOf(channel) >= 1 then text = text + "  ×" + stackOf(channel).ToStr()
        m.status.text = text
        return
    end if
    if channel.tvgId = invalid or channel.tvgId = "" then
        m.status.text = "This channel has no guide id"
        return
    end if
    if m.playerIndex = 1 then
        postReport(true, channel)
        return
    end if
    if m.playerIndex = 2 then
        postReport(false, channel)
        return
    end if
    m.removeTvgId = channel.tvgId
    m.removeName = channel.name
    m.dialogKind = "remove"
    m.dialogIndex = 0
    m.resumePlayer = true
    m.mode = "dialog"
    showPanels()
    drawDialog()
end sub

sub postReport(working as boolean, channel as object)
    if m.recordBusy then
        m.status.text = "Busy, try again"
        return
    end if
    body = {}
    body.tvg_id = channel.tvgId
    body.working = working
    body.name = channel.name
    startRecord("POST", joinUrl(activeBase(), "report"), FormatJSON(body), "report", "")
end sub

sub postRemove()
    if m.recordBusy then
        m.status.text = "Busy, try again"
        return
    end if
    body = {}
    body.tvg_id = m.removeTvgId
    body.name = m.removeName
    startRecord("POST", joinUrl(activeBase(), "remove"), FormatJSON(body), "remove", "X-Mofin-Key")
end sub

sub handleReport(code as integer, body as string)
    if code = 429 then
        m.status.text = "Too many reports, try later"
    else if code = 200 and jsonOk(body) then
        m.status.text = "Thanks, saved"
    else
        m.status.text = "Not saved"
    end if
end sub

sub handleRemove(code as integer, body as string)
    if code = 200 and jsonOk(body) then
        m.status.text = "Removed"
        m.statusHold = "Removed"
        dropAndPlayNext(m.removeTvgId, m.removeName)
        loadGuide()
        return
    end if
    if code = 403 then
        m.status.text = "Not allowed from this network"
    else if code = 404 then
        m.status.text = "Channel not found"
    else if code = 429 then
        m.status.text = "Too many requests, try later"
    else
        m.status.text = "Not removed"
    end if
end sub

function jsonOk(body as string) as boolean
    if body = invalid or body = "" then return false
    parsed = ParseJSON(body)
    if type(parsed) <> "roAssociativeArray" then return false
    if parsed.ok = true then return true
    return false
end function

sub dropAndPlayNext(tvgId as string, name as string)
    idx = -1
    for i = 0 to m.visible.Count() - 1
        if sameChannel(m.visible[i], tvgId, name) then
            idx = i
            exit for
        end if
    end for
    kept = []
    for each channel in m.channels
        if sameChannel(channel, tvgId, name) = false then kept.Push(channel)
    end for
    m.channels = kept
    m.groups = groupsStillPresent()
    refreshVisible()
    if m.visible.Count() = 0 and m.channels.Count() > 0 then
        m.filter = ""
        m.sideIndex = 0
        refreshVisible()
    end if
    if m.visible.Count() = 0 then
        m.playingChannel = invalid
        showGuide()
        return
    end if
    nextIndex = idx
    if nextIndex < 0 or nextIndex > m.visible.Count() - 1 then nextIndex = 0
    m.row = nextIndex
    m.block = 0
    channel = m.visible[nextIndex]
    m.playingChannel = channel
    if m.mode <> "player" then m.mode = "player"
    playUrl(channel.url, true)
    drawPlayerBar()
end sub

function sameChannel(channel as object, tvgId as string, name as string) as boolean
    if channel = invalid then return false
    if tvgId <> "" and channel.tvgId = tvgId then return true
    if tvgId = "" and channel.name = name then return true
    return false
end function

function groupsStillPresent() as object
    seen = {}
    for each channel in m.channels
        group = channel.group
        if group = invalid then group = ""
        group = group.Trim()
        if group <> "" then seen[LCase(group)] = true
    end for
    kept = []
    added = {}
    for each group in m.groups
        key = LCase(group)
        if seen.DoesExist(key) and added.DoesExist(key) = false then
            kept.Push(group)
            added[key] = true
        end if
    end for
    return kept
end function

function stackOf(channel as object) as integer
    if channel = invalid then return 0
    raw = channel.stack
    if raw = invalid then return 0
    value = raw.ToStr().ToInt()
    if value < 1 then return 0
    return value
end function

function sideItems() as object
    items = ["All Channels"]
    for each group in m.groups
        items.Push(group)
    end for
    items.Push("Streaming")
    items.Push("Recordings")
    items.Push("Settings")
    return items
end function

function sideKind(index as integer) as string
    items = sideItems()
    last = items.Count() - 1
    if index = last then return "settings"
    if index = last - 1 then return "recordings"
    if index = last - 2 then return "streaming"
    if index = 0 then return "all"
    return "group"
end function

sub keepSideVisible()
    if m.sideIndex < m.sideTop then m.sideTop = m.sideIndex
    if m.sideIndex >= m.sideTop + 14 then m.sideTop = m.sideIndex - 13
    if m.sideTop < 0 then m.sideTop = 0
end sub

sub refreshVisible()
    out = []
    for each channel in m.channels
        if m.filter = "" or channel.group = m.filter then out.Push(channel)
    end for
    m.visible = out
    if m.row > out.Count() - 1 then m.row = 0
    if m.row < 0 then m.row = 0
end sub

function focusedChannel() as object
    if m.visible = invalid or m.visible.Count() = 0 then return invalid
    if m.row < 0 or m.row >= m.visible.Count() then return invalid
    return m.visible[m.row]
end function

function focusedProgram() as object
    channel = focusedChannel()
    if channel = invalid then return invalid
    blocks = blocksFor(channel)
    if blocks.Count() = 0 then return invalid
    if m.block < 0 or m.block >= blocks.Count() then m.block = 0
    return blocks[m.block]
end function

function blocksFor(channel as object) as object
    window = guideWindow()
    list = []
    if channel <> invalid and channel.tvgId <> "" and m.programs.DoesExist(channel.tvgId) then
        for each item in m.programs[channel.tvgId]
            if item.endAt > window.start and item.start < window.endAt then list.Push(item)
        end for
    end if
    if list.Count() = 0 then
        list.Push({
            title: "On now"
            start: window.start
            endAt: window.endAt
            desc: ""
            category: ""
        })
    end if
    return list
end function

function blockIndexAt(blocks as object, when as integer) as integer
    if blocks.Count() = 0 then return 0
    for i = 0 to blocks.Count() - 1
        item = blocks[i]
        if item.start <= when and when < item.endAt then return i
    end for
    return 0
end function

function guideWindow() as object
    startAt = floorHalfHour(nowSeconds())
    return { start: startAt, endAt: startAt + 6 * 1800 }
end function

function spanBox(startAt as integer, endAt as integer, windowStart as integer, windowEnd as integer, origin as integer, width as integer) as object
    if endAt <= windowStart or startAt >= windowEnd then return invalid
    if startAt < windowStart then startAt = windowStart
    if endAt > windowEnd then endAt = windowEnd
    span = windowEnd - windowStart
    if span <= 0 then return invalid
    x = origin + Int(((startAt - windowStart) / span) * width)
    w = Int(((endAt - startAt) / span) * width)
    if w < 12 then w = 12
    return { x: x, w: w }
end function

function recordingMatch(tvgId as string, startAt as integer) as object
    if tvgId = invalid or tvgId = "" then return invalid
    for each rec in m.recordings
        if rec.tvgId = tvgId and marksGuide(rec.status) then
            delta = rec.start - startAt
            if delta < 0 then delta = 0 - delta
            if delta <= 90 then return rec
        end if
    end for
    return invalid
end function

function marksGuide(status as string) as boolean
    if status = "cancelled" or status = "canceled" or status = "failed" or status = "deleted" or status = "missed" or status = "completed" then return false
    return true
end function

function parseRecordingList(body as string) as object
    out = []
    if body = invalid or body = "" then return out
    parsed = ParseJSON(body)
    items = []
    if type(parsed) = "roArray" then
        items = parsed
    else if type(parsed) = "roAssociativeArray" then
        if type(parsed.recordings) = "roArray" then
            items = parsed.recordings
        else if type(parsed.items) = "roArray" then
            items = parsed.items
        else if type(parsed.jobs) = "roArray" then
            items = parsed.jobs
        end if
    end if
    for each item in items
        if type(item) = "roAssociativeArray" then
            status = stringOr(firstField(item, ["status", "state"]))
            if status = "" then status = "scheduled"
            out.Push({
                id: stringOr(firstField(item, ["id", "job_id", "recording_id"]))
                tvgId: stringOr(firstField(item, ["tvg_id", "tvgId"]))
                title: stringOr(firstField(item, ["title", "name"]))
                start: isoEpoch(firstField(item, ["start", "start_time"]))
                endAt: isoEpoch(firstField(item, ["end", "stop", "end_time"]))
                status: LCase(status)
            })
        end if
    end for
    return out
end function

function firstField(item as object, keys as object) as dynamic
    for each key in keys
        if item.DoesExist(key) then return item.Lookup(key)
    end for
    return invalid
end function

function stringOr(value as dynamic) as string
    if value = invalid then return ""
    return value.ToStr()
end function

function isoEpoch(raw as dynamic) as integer
    if raw = invalid then return 0
    text = raw.ToStr()
    if text = "" then return 0
    dt = CreateObject("roDateTime")
    if dt.FromISO8601String(text) then return dt.AsSeconds()
    return 0
end function

function isoTime(epoch as integer) as string
    dt = CreateObject("roDateTime")
    dt.FromSeconds(epoch)
    return dt.ToISOString()
end function

function nowSeconds() as integer
    return CreateObject("roDateTime").AsSeconds()
end function

function floorHalfHour(epoch as integer) as integer
    return epoch - (epoch mod 1800)
end function

function formatTime(epoch as integer) as string
    dt = CreateObject("roDateTime")
    dt.FromSeconds(epoch)
    dt.ToLocalTime()
    return formatClock(dt)
end function

function formatClock(dt as object) as string
    h = dt.GetHours()
    minutes = dt.GetMinutes()
    suffix = "AM"
    if h >= 12 then suffix = "PM"
    h12 = h mod 12
    if h12 = 0 then h12 = 12
    mm = minutes.ToStr()
    if minutes < 10 then mm = "0" + mm
    return h12.ToStr() + ":" + mm + " " + suffix
end function

function shown(value as string, fallback as string) as string
    if value = invalid or value.Trim() = "" then return fallback
    return value
end function

function shownSecret(value as string) as string
    if value = invalid or value.Trim() = "" then return "not set"
    return "set"
end function

function activeBase() as string
    if m.baseUrl = invalid or m.baseUrl.Trim() = "" then return m.defaultBase
    return m.baseUrl.Trim()
end function

function readSetting(key as string, fallback as string) as string
    reg = CreateObject("roRegistrySection", "mofin")
    if reg = invalid then return fallback
    value = reg.Read(key)
    if value = invalid or value = "" then return fallback
    return value
end function

sub saveSettings()
    reg = CreateObject("roRegistrySection", "mofin")
    if reg = invalid then return
    reg.Write("baseUrl", activeBase())
    if m.token = invalid then m.token = ""
    reg.Write("token", m.token)
    reg.Flush()
end sub

sub writeStreamingKey(value as string)
    reg = CreateObject("roRegistrySection", "mofin")
    if reg = invalid then return
    if value = invalid then value = ""
    reg.Write("streamingTmdbKey", value)
    reg.Flush()
end sub

sub clearGroup(group as object)
    if group = invalid then return
    while group.getChildCount() > 0
        group.removeChildIndex(group.getChildCount() - 1)
    end while
end sub

function makeRect(x as integer, y as integer, w as integer, h as integer, color as string) as object
    node = CreateObject("roSGNode", "Rectangle")
    node.translation = [x, y]
    node.width = w
    node.height = h
    node.color = color
    return node
end function

function makeLabel(text as string, x as integer, y as integer, w as integer, h as integer, color as string) as object
    node = CreateObject("roSGNode", "Label")
    if text = invalid then text = ""
    node.text = text
    node.translation = [x, y]
    node.width = w
    node.height = h
    node.color = color
    node.font = m.smallFont
    return node
end function
