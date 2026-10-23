sub init()
    m.top.functionName = "run"
end sub

sub run()
    m.cache = m.top.cache
    if m.cache = invalid then m.cache = {}
    key = ""
    if m.top.apiKey <> invalid then key = m.top.apiKey.Trim()
    kind = m.top.kind
    if kind = invalid or kind = "" then kind = "home"
    payload = {
        needsKey: false
        rows: []
        titles: []
        detail: invalid
        cache: m.cache
        epoch: m.top.epoch
        kind: kind
        error: ""
    }
    if key = "" then
        payload.needsKey = true
        m.top.payload = payload
        return
    end if
    movieIds = providerIds(key, "movie")
    if m.failed <> invalid and m.failed <> "" then
        payload.error = m.failed
        payload.cache = m.cache
        m.top.payload = payload
        m.top.error = m.failed
        return
    end if
    tvIds = providerIds(key, "tv")
    if m.failed <> invalid and m.failed <> "" then
        payload.error = m.failed
        payload.cache = m.cache
        m.top.payload = payload
        m.top.error = m.failed
        return
    end if
    if kind = "detail" then
        mediaType = m.top.mediaType
        if mediaType <> "tv" then mediaType = "movie"
        payload.detail = loadDetail(key, mediaType, m.top.tmdbId, movieIds, tvIds)
    else if kind = "search" then
        payload.titles = loadSearch(key, m.top.query, movieIds, tvIds)
    else
        payload.rows = loadHome(key, movieIds, tvIds)
    end if
    if m.failed <> invalid and m.failed <> "" then
        payload.error = m.failed
        m.top.error = m.failed
    end if
    payload.cache = m.cache
    m.top.payload = payload
end sub

function loadHome(apiKey as string, movieIds as object, tvIds as object) as object
    rows = []
    rows.Push({ title: "Trending", items: trending(apiKey, movieIds, tvIds) })
    for each service in streamingServices()
        if movieIds.DoesExist(service.id) = false and tvIds.DoesExist(service.id) = false then
            continue for
        end if
        rows.Push({
            title: service.label
            service: service.id
            items: discoverService(apiKey, service.id, movieIds, tvIds)
        })
    end for
    return rows
end function

function trending(apiKey as string, movieIds as object, tvIds as object) as object
    result = cachedGet(tmdbUrl("/trending/all/week", { language: "en-US" }, apiKey))
    parsed = okJson(result)
    if parsed = invalid or parsed.results = invalid then return []
    titles = []
    for each raw in parsed.results
        if raw = invalid then continue for
        mediaType = ""
        if raw.media_type <> invalid then mediaType = raw.media_type
        if mediaType <> "movie" and mediaType <> "tv" then continue for
        id = jsonInt(raw.id)
        if id <= 0 then continue for
        services = servicesFor(apiKey, mediaType, id, movieIds, tvIds)
        if services.Count() = 0 then continue for
        titles.Push(titleFrom(raw, mediaType, services))
    end for
    return titles
end function

function discoverService(apiKey as string, service as string, movieIds as object, tvIds as object) as object
    found = {}
    order = []
    types = ["movie", "tv"]
    for each mediaType in types
        ids = movieIds
        if mediaType = "tv" then ids = tvIds
        if ids.DoesExist(service) = false then continue for
        providerId = Int(ids[service])
        if providerId <= 0 then continue for
        result = cachedGet(tmdbUrl("/discover/" + mediaType, {
            with_watch_providers: providerId.ToStr()
            watch_region: "US"
            with_watch_monetization_types: "flatrate"
            sort_by: "popularity.desc"
            include_adult: "false"
            language: "en-US"
        }, apiKey))
        parsed = okJson(result)
        if parsed = invalid or parsed.results = invalid then continue for
        kept = 0
        for each raw in parsed.results
            if kept >= 12 then exit for
            id = jsonInt(raw.id)
            if id <= 0 then continue for
            services = servicesFor(apiKey, mediaType, id, movieIds, tvIds)
            if hasService(services, service) = false then continue for
            key = mediaType + ":" + id.ToStr()
            if found.DoesExist(key) then continue for
            found[key] = titleFrom(raw, mediaType, services)
            order.Push(key)
            kept = kept + 1
        end for
    end for
    titles = []
    for each key in order
        titles.Push(found[key])
    end for
    return titles
end function

function loadSearch(apiKey as string, query as string, movieIds as object, tvIds as object) as object
    if query = invalid then return []
    query = query.Trim()
    if query = "" then return []
    result = cachedGet(tmdbUrl("/search/multi", {
        query: query
        include_adult: "false"
        language: "en-US"
    }, apiKey))
    parsed = okJson(result)
    if parsed = invalid or parsed.results = invalid then return []
    titles = []
    for each raw in parsed.results
        if titles.Count() >= 24 then exit for
        mediaType = ""
        if raw.media_type <> invalid then mediaType = raw.media_type
        if mediaType <> "movie" and mediaType <> "tv" then continue for
        id = jsonInt(raw.id)
        if id <= 0 then continue for
        services = servicesFor(apiKey, mediaType, id, movieIds, tvIds)
        if services.Count() = 0 then continue for
        titles.Push(titleFrom(raw, mediaType, services))
    end for
    return titles
end function

function loadDetail(apiKey as string, mediaType as string, id as integer, movieIds as object, tvIds as object) as object
    if id <= 0 then return invalid
    path = "/movie/" + id.ToStr()
    if mediaType = "tv" then path = "/tv/" + id.ToStr()
    result = cachedGet(tmdbUrl(path, { language: "en-US" }, apiKey))
    raw = okJson(result)
    if raw = invalid or raw.id = invalid then return invalid
    services = servicesFor(apiKey, mediaType, id, movieIds, tvIds)
    item = titleFrom(raw, mediaType, services)
    item.overview = ""
    if raw.overview <> invalid then item.overview = raw.overview
    item.rating = 0
    if raw.vote_average <> invalid then item.rating = raw.vote_average
    item.runtime = jsonInt(raw.runtime)
    item.seasons = jsonInt(raw.number_of_seasons)
    return item
end function

function servicesFor(apiKey as string, mediaType as string, id as integer, movieIds as object, tvIds as object) as object
    result = cachedGet(tmdbUrl("/" + mediaType + "/" + id.ToStr() + "/watch/providers", {}, apiKey))
    parsed = okJson(result)
    if parsed = invalid or parsed.results = invalid then return []
    region = parsed.results.US
    if region = invalid or region.flatrate = invalid then return []
    ids = movieIds
    if mediaType = "tv" then ids = tvIds
    seen = {}
    matched = []
    for each entry in region.flatrate
        if entry = invalid then continue for
        name = ""
        if entry.provider_name <> invalid then name = entry.provider_name
        service = serviceForName(name)
        if service = "" then continue for
        if ids.DoesExist(service) = false then continue for
        if Int(ids[service]) <> jsonInt(entry.provider_id) then continue for
        if seen.DoesExist(service) then continue for
        seen[service] = true
        matched.Push(service)
    end for
    return orderServices(matched)
end function

function providerIds(apiKey as string, mediaType as string) as object
    m.failed = ""
    result = cachedGet(tmdbUrl("/watch/providers/" + mediaType, { watch_region: "US" }, apiKey))
    found = {}
    if result.code < 200 or result.code >= 300 then
        if result.error <> invalid and result.error <> "" then
            m.failed = "TMDB " + result.error
        else
            m.failed = "TMDB failed"
        end if
        return found
    end if
    parsed = ParseJSON(result.body)
    if parsed = invalid or parsed.results = invalid then return found
    for each entry in parsed.results
        if entry = invalid then continue for
        name = ""
        if entry.provider_name <> invalid then name = entry.provider_name
        service = serviceForName(name)
        id = jsonInt(entry.provider_id)
        if service = "" or id <= 0 or found.DoesExist(service) then continue for
        found[service] = id
    end for
    return found
end function

function cachedGet(url as string) as object
    now = unixNow()
    hit = m.cache[url]
    if hit <> invalid and hit.at <> invalid and hit.body <> invalid then
        age = now - Int(hit.at)
        if age >= 0 and age < 21600 then
            return { code: 200, body: hit.body, error: "" }
        end if
    end if
    result = httpRequest(url, "GET", "", "", "")
    if result.code >= 200 and result.code < 300 then
        m.cache[url] = { at: now, body: result.body }
    end if
    return result
end function

function tmdbUrl(path as string, params as object, apiKey as string) as string
    url = "https://api.themoviedb.org/3" + path + "?api_key=" + urlEncode(apiKey)
    if params = invalid then return url
    for each key in params.Keys()
        value = params[key]
        if value = invalid then value = ""
        url = url + "&" + key + "=" + urlEncode(value.ToStr())
    end for
    return url
end function

function okJson(result as object) as object
    if result = invalid then return invalid
    if result.code < 200 or result.code >= 300 then
        if m.failed = invalid or m.failed = "" then
            if result.error <> invalid and result.error <> "" then
                m.failed = "TMDB " + result.error
            else
                m.failed = "TMDB failed"
            end if
        end if
        return invalid
    end if
    if result.body = invalid or result.body = "" then return invalid
    return ParseJSON(result.body)
end function

function titleFrom(raw as object, mediaType as string, services as object) as object
    name = ""
    date = ""
    if mediaType = "tv" then
        if raw.name <> invalid then name = raw.name
        if name = "" and raw.title <> invalid then name = raw.title
        if raw.first_air_date <> invalid then date = raw.first_air_date
    else
        if raw.title <> invalid then name = raw.title
        if name = "" and raw.name <> invalid then name = raw.name
        if raw.release_date <> invalid then date = raw.release_date
    end if
    year = 0
    if date <> invalid and date.Len() >= 4 then year = date.Left(4).ToInt()
    poster = ""
    if raw.poster_path <> invalid and raw.poster_path <> "" then
        poster = "https://image.tmdb.org/t/p/w185" + raw.poster_path
    end if
    return {
        id: jsonInt(raw.id)
        mediaType: mediaType
        title: name
        year: year
        poster: poster
        services: serviceLabels(services)
        serviceIds: services
        overview: ""
        rating: 0
        runtime: 0
        seasons: 0
    }
end function
