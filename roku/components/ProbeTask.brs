sub init()
    m.top.functionName = "run"
end sub

sub run()
    url = m.top.url
    if url = invalid then url = ""
    m.top.member = peekMemberHeader(url)
    m.top.done = true
end sub
