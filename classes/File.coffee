#_require TheTVDBAPI
#_require SizeFormatter

sortable = (string) ->
  for prefix in ['The','Der','Die','Das','Le','Les','La', 'Los']
    regexp = new RegExp('^'+prefix+' ', 'i')
    return string.replace(regexp, '') + ', ' + prefix if regexp.test string
  return string

class File
  SEASON_EPISODE_RE = [
    # Extract <showName> <seasonNumber> <episodeNumber> from filename
    /^(.*) s(\d+)e(\d+)/gi,
    /^(.*?) (\d{1})(\d{2})[^\d]/gi,
    /^(.*?) (\d{1,2})x(\d{1,2})/gi
  ]
  AIRDATE_RE = [
    # Extract <year> <month> <day> from filename
    /^(.*) (\d{4}) (\d{2}) (\d{2})/gi
  ]
  TVDB = new TheTVDBAPI()
  DELIMITERS = /[\s,\.\-\+]+/g

  constructor: (@directory, @filename) ->
    @extension = Path.extname @filename
    @name = Path.basename @filename, @extension
    @filepath = Path.join(@directory, @filename)
    @fileinfo = FileSystem.statSync @filepath

  match: (next) ->
    log.info 'Matching "%s"', @filename  
    @nameNormalized = @name.replace DELIMITERS, ' '
    Async.series [@extract.bind(@), @fetchShow.bind(@), @fetchEpisode.bind(@)], (error) =>
      log.error "Could not match '%s': %s", @filename, error if error?
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
        log.debug 'Extracted -> "%s" S%02fE%02f', @extracted.shpw, @extracted.season, @extracted.episode
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
          next new Error("Show named '#{name}' not found")
        else
          next new Error("Show name '#{name}' is ambigious")

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
      title: @episode.title
    for key, value of placeholders
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
    @makeLibraryPath libraryDir, directory, (error, existed) =>
      if error?
        next error
      else
        @overwrite directory, basename, overwritePolicy, (fileExisted, move) =>
          if move
            @moveTo libraryDir, path, next 
          else 
            next(null, yes)

  overwrite: (directory, basename, overwritePolicy, next) ->
    FileSystem.readdir directory, (error, files) =>
      for file in files
        if Path.basename(file, Path.extname(file)) is basename
          filename = Path.join(directory, file)
          stat = FileSystem.statSync filename
          overwrite = no
          if overwritePolicy is 'replaceWhenBigger'
            if stat.size < @stat.size
              log.warn "Smaller file '%s' in library will be replaced", file
              overwrite = yes
            else if stat.size > @stat.size
              log.warn "Bigger file '%s' (%s > %s) already in library", file, SizeFormatter.Format(stat.size), SizeFormatter.Format(@stat.size)
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
    FileSystem.exists library, (exists) =>
      return next(new Error("Library path #{library} does not exist")) unless exists
      FileSystem.stat directory, (error, stat) =>
        if error? and error.name is 'ENOENT'
          log.debug "Creting subdirectory '%s' in library", directory
          FileSystem.mkdir directory, (error) =>
            next error, no
        else if error?
          next error
        else
          if stat.isDirectory()
            next null, yes
          else
            next(new Error("Path #{directory} exists but is not a directory"))

  toString: ->
    sprintf('%s S%02fE%02f "%s" (%s)', @show.name, parseInt(@episode.season), parseInt(@episode.episode), @episode.title, SizeFormatter.Format(@fileinfo.size))