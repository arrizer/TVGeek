#!/usr/bin/env coffee

FileSystem = require 'fs'
Path       = require 'path'
HTTP       = require 'http'
sprintf    = require('sprintf').sprintf
LibXML     = require 'libxmljs'
Async      = require 'async'
CLIColor   = require 'cli-color'
Readline   = require('readline')

class Log
  LEVELS =
    debug:
      level: 0
      colors: ['blue']
      textColors: ['blackBright']
    info:
      level: 1
      colors: ['cyan']
      textColors: []
    warn:
      level: 2
      colors: ['black','bgYellow']
      textColors: ['yellow']
    error:
      level: 3
      colors: ['red']
      textColors: ['red']
    fatal:
      level: 4
      colors: ['white','bgRedBright']
      textColors: ['red']

  @StdErr: ->
    new Log(process.stderr)
    
  constructor: (@stream) ->
    @colored = yes
    @timestamp = no
    @level = 5
    @buffer = ''
    @paused = no
    for level of LEVELS
      do (level) =>
        @[level] = (message, parameters...) =>
          @log(level, message, parameters...)

  colorize: (string, colors...) ->
    return string if !@colored or !colors? or colors.length == 0
    chain = CLIColor
    for color in colors
      chain = chain[color]
    return chain(string)

  log: (level, message, parameters...) ->
    line = ''
    line += @colorize('[' + new Date() + '] ', 'blackBright') if @timestamp
    line += @colorize('[' + level.toUpperCase() + ']', LEVELS[level].colors...)
    line += ' ' + @colorize(sprintf(message, parameters...), LEVELS[level].textColors...)
    @write line + "\n"

  write: (message) ->
    if @paused
      @buffer += message
    else
      @stream.write message, 'utf8'

  pause: ->
    @paused = yes

  resume: ->
    @paused = no
    @write @buffer
    @buffer = ''

log = Log.StdErr()

class Config
  DEFAULTS =
    inbox: null
    library: null
    structure: '%show_sortable%/Season %season%/%show% S%season_00%E%episode_00% %title%'
    policy: 'replaceWhenBigger'
    considerExtensions: ["mp4","mkv","avi","mov"]
    deleteExtensions: []

  constructor: (@file) ->
  
  read: (next) ->
    FileSystem.readFile @file, (error, data) =>
      if error?
        next(error)
      else
        @load JSON.parse(data.toString())
        next()

  load: (config) ->
    @config = DEFAULTS
    for key of config
      if key of DEFAULTS
        @config[key] = config[key]
      else
        log.warn 'Unknown option "%s" in configuration file', key
    @config.considerExtensions = @config.considerExtensions.map (extension) -> '.'+extension

  get: ->
    @config


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
        xmlError = xml.get '/Data/Error'
        if xmlError?
          next new Error("TVDB API Error: " + xmlError.toString())
        else
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


class SizeFormatter
  UNITS = ['bytes','KiB','MiB','GiB','PiB']

  @Format: (bytes) ->
    factor = 1
    unit = 0
    while (factor * 1024) < bytes
      factor *= 1024
      unit++
    return (Math.round((bytes / factor) * 100) / 100) + ' ' + UNITS[unit]


class Lock
  constructor: ->
    @locked = no
    @queue = []

  acquire: (critical) ->
    @queue.push critical
    @next() unless @locked
    
  next: ->
    return if @queue.length == 0
    @locked = yes
    @queue.shift() =>
      @locked = no
      @next()


class UserPrompt
  constructor: ->
    @rl = Readline.createInterface
      input: process.stdin,
      output: process.stdout
    @rl.pause()
    @lock = new Lock()
  
  pick: (options, message, next) ->
    @lock.acquire (release) =>
      index = 1
      console.log message
      for option in options
        console.log "(#{index++}) " + option.label
      log.pause()
      @rl.resume()
      @rl.question 'Pick one: ', (index) =>
        next(options[index-1])
        @rl.pause()
        log.resume()
        release()

prompt = new UserPrompt()


class File
  SEASON_EPISODE_RE = [
    # Extract <showName> <seasonNumber> <episodeNumber> from filename
    /^(.*) s(\d+)e(\d+)/gi,
    /^(.*?) (\d{1})(\d{2}) /gi,
    /^(.*?) (\d{1,2})x(\d{1,2})/gi
  ]
  AIRDATE_RE = [
    # Extract <year> <month> <day> from filename
    /^(.*) (\d{4}) (\d{2}) (\d{2})/gi
  ]
  TVDB = new TheTVDBAPI()
  DELIMITERS = /[\s,\.\-\+]+/g

  sortable = (string) ->
    for prefix in ['The','Der','Die','Das','Le','Les','La','Los']
      regexp = new RegExp('^'+prefix+' ', 'i')
      return string.replace(regexp, '') + ', ' + prefix if regexp.test string
    return string

  constructor: (@directory, @filename) ->
    @extension = Path.extname @filename
    @name = Path.basename @filename, @extension
    @filepath = Path.join(@directory, @filename)
    @info = FileSystem.statSync @filepath

  match: (next) ->
    log.info 'Matching "%s"', @filename  
    @nameNormalized = @name.replace DELIMITERS, ' '
    Async.series [@extract.bind(@), @fetchShow.bind(@), @fetchEpisode.bind(@)], (error) =>
      log.error "%s: %s", @filename, error if error?
      next error
    
  extract: (next) ->
    for method in ['extractSeasonAndEpisode','extractAirdate']
      return next() if @[method]()
    return next(new Error("Could not extract season/episode or airdate from '#{@nameNormalized}'"))

  extractSeasonAndEpisode: ->
    log.debug 'Extracting season/episode from "%s"', @nameNormalized
    for regexp in SEASON_EPISODE_RE
      match = regexp.exec @nameNormalized
      if match?
        @extracted =
          fetch: 'fetchEpisodeBySeasonAndEpisode'
          show: match[1]
          season: parseInt(match[2])
          episode: parseInt(match[3])
        log.debug 'Extracted -> "%s" S%02fE%02f', @extracted.show, @extracted.season, @extracted.episode
        regexp.lastIndex = 0
        return yes
    return no

  extractAirdate: (next) ->
    log.debug 'Extracting airdate from "%s"', @nameNormalized
    for regexp in AIRDATE_RE
      match = regexp.exec @nameNormalized
      if match?
        @extracted =
          fetch: 'fetchEpisodeByAirdate'
          show: match[1]
          airdate: new Date(match[2], parseInt(match[3]) - 1, match[4])
        log.debug 'Extracted -> "%s" airdate %s', @extracted.show, @extracted.airdate
        regexp.lastIndex = 0
        return yes
    return no

  fetchShow: (next) ->
    TVDB.show @extracted.show, (error, shows) =>
      if error?
        next new Error("Failed to get show information: " + error)
      else
        if shows.length == 1
          next(null, @show = shows[0])
        else if shows.length == 0
          next new Error("Show named '#{@extracted.show}' not found")
        else
          show.label = show.name for show in shows
          prompt.pick shows, "To which show does #{@filename} belong?", (show) =>
            next(null, @show = show)

  fetchEpisode: (next) ->
    @[@extracted.fetch] (error, episode) =>
      if error?
        next new Error("Failed to get episode information: " + error)
      else
        next(null, @episode = episode)
    
  fetchEpisodeBySeasonAndEpisode: (next) ->
    TVDB.episodeBySeasonAndEpisode @show.id, @extracted.season, @extracted.episode, next

  fetchEpisodeByAirdate: (next) ->
    TVDB.episodeByAirdate @show.id, @extracted.airdate, next

  libraryPath: (pattern) ->
    path = pattern
    placeholders =
      show: @show.name
      season: @episode.season
      episode: @episode.episode
      title: @episode.titlewww
    for key, value of placeholders
      value = '' unless value?
      value = value.toString().replace /(\/|\\|:|;)/g, ''
      placeholders[key] = value
      placeholders[key + '_sortable'] = sortable value 
      placeholders[key + '_00'] = sprintf('%02f', parseInt(value)) if /^\d+$/.test value
    escapeRegExp = (string) -> string.replace(/([.*+?^=!:${}()|\[\]\/\\])/g, "\\$1")
    for key, value of placeholders
      path = path.replace new RegExp(escapeRegExp('%'+key+'%'),'g'), value
    return path

  move: (libraryDir, pattern, overwritePolicy, next) ->
    path = @libraryPath(pattern)
    basename = Path.basename path
    directory = Path.join(libraryDir, Path.dirname (path))
    @makeLibraryPath libraryDir, Path.dirname(path), (error, existed) =>
      if error?
        next error
      else
        @overwrite directory, basename, overwritePolicy, (fileExisted, move) =>
          if move
            @moveTo libraryDir, path, next 
          else
            FileSystem.unlink Path.join(@directory, @filename), (error) =>
              next(error, yes)

  overwrite: (directory, basename, overwritePolicy, next) ->
    FileSystem.readdir directory, (error, files) =>
      for file in files
        if Path.basename(file, Path.extname(file)) is basename
          filename = Path.join(directory, file)
          stat = FileSystem.statSync filename
          overwrite = no
          if overwritePolicy is 'replaceWhenBigger'
            if stat.size < @info.size
              log.warn "Smaller file '%s' in library will be replaced", file
              overwrite = yes
            else if stat.size > @info.size
              log.warn "Bigger file '%s' (%s > %s) already in library", file, 
                SizeFormatter.Format(stat.size), SizeFormatter.Format(@info.size)
            else
              log.warn "File '%s' already in library", file
          else if overwritePolicy is 'always'
            log.warn "File '%s' in library will be replaced", file
            overwrite = yes
          if overwrite
            FileSystem.unlink filename, (error) =>
              log.error "Failed to remove existing file '%s' in library: %s", filename, error
              return next yes, !error?
          else
            return next yes, no
      next no, yes

  moveTo: (library, path, next) ->
    origin = Path.join(@directory, @filename)
    destination = Path.join(library, path + @extension)
    FileSystem.rename origin, destination, next

  makeLibraryPath: (library, directory, next) ->
    @makeLibraryPathRecursive library, '', directory.split(Path.sep), next

  makeLibraryPathRecursive: (library, path, remaining, next) ->
    directory = Path.join library, path
    recurse = =>
      if remaining.length > 0
        @makeLibraryPathRecursive library, Path.join(path, remaining.shift()), remaining, next
      else
        next()
    FileSystem.exists directory, (exists) =>
      unless exists
        log.debug 'Creating directory "%s"', directory
        FileSystem.mkdir directory, (error) =>
          if error then next(error) else recurse()
      else
        recurse()

  toString: ->
    sprintf('%s S%02fE%02f "%s" (%s)', @show.name, parseInt(@episode.season), parseInt(@episode.episode), 
      @episode.title, SizeFormatter.Format(@info.size))

class App
  main: ->
    @config = new Config(__dirname + '/config.json')
    @config.read =>
      @config = @config.get()
      @processFiles @config.inbox

  processFiles: (inbox) ->
    FileSystem.readdir inbox, (error ,files) =>
      if error?
        log.error 'Failed to enumerate files in inbox "%s": %s', inbox, error
      else
        for file in files
          if @config.considerExtensions.indexOf(Path.extname(file)) >= 0
            @processFile inbox, file
          else
            for extension in @config.deleteExtensions
              if Path.extname(file) is '.' + extension
                log.info "Deleting file '%s' from inbox", file
                FileSystem.unlink Path.join(inbox, file)

  processFile: (inbox, file) ->
    item = new File(inbox, file)
    item.match (error) =>
      unless error?
        log.info '-> %s', item.toString()
        item.move @config.library, @config.structure, @config.policy, (error) =>
          log.error "Failed to move '%s' to library: %s", item.filename, error if error?


app = new App()
app.main()