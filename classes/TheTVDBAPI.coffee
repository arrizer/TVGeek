class TheTVDBAPI
  API_KEY = '5EFCC7790F190138'
  BASE = 'http://thetvdb.com'

  request: (url, next) ->
    log.debug '<TVDB> GET %s', url
    req = HTTP.request url, (res) =>
      if res.statusCode is 200
        body = ''
        res.on 'data', (data) => 
          body += data.toString()
        res.on 'end', =>
          next null, body
      else
        next new Error("tvdb API request to #{url} failed with HTTP error #{res.statusCode}")
    req.on 'error', (error) =>
      next error
    req.end()

  requestXML: (url, next) ->
    @request url, (error, data) =>
      if error?
        next error
      else
        xml = LibXML.parseXmlString data
        next null, xml

  show: (name, next) ->
    @requestXML "#{BASE}/api/GetSeries.php?seriesname=" + encodeURIComponent(name), (error, xml) =>
      if error?
        next error
      else
        shows = []
        for node in xml.find '/Data/Series'
          get = (path) ->
            subnode = node.get(path)
            if subnode? then subnode.text() else null
          shows.push
            id: get('seriesid')
            language: get('language')
            name: get('SeriesName')
            since: get('FirstAired')
        next null, shows

  episodeByAirdate: (showID, airdate, next) ->
    airdate = sprintf('%04f-%02f-%02f', airdate.getFullYear(), airdate.getMonth() + 1, airdate.getDate())
    @episodeByURL "#{BASE}/api/GetEpisodeByAirDate.php?apikey=#{API_KEY}&seriesid=#{showID}&airdate=#{airdate}", next

  episodeBySeasonAndEpisode: (showID, season, episode, next) ->
    @episodeByURL "#{BASE}/api/#{API_KEY}/series/#{showID}/default/#{season}/#{episode}/en.xml", next

  episodeByURL: (url, next) ->
    @requestXML url, (error, xml) =>
      if error?
        next error
      else
        get = (key) ->
          node = xml.get('/Data/Episode/' + key)
          if node? then node.text() else null
        episode = 
          id: get 'id'
          airdate: get 'FirstAired'
          title: get 'EpisodeName'
          season: get 'SeasonNumber'
          episode: get 'EpisodeNumber'
          director: get 'Director'
        next null, episode